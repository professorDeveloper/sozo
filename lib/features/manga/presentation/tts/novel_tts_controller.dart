import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/manga/data/tts/tts_engine.dart';
import 'package:soplay/features/manga/domain/reading/tts_language.dart';
import 'package:soplay/features/manga/domain/reading/tts_segmenter.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

enum TtsStatus { idle, playing, paused, loading }

/// Something the reader should tell the listener about.
enum TtsNotice { noVoiceForLanguage, failed, sleepStopped }

/// The next chapter, as the reader hands it over for auto-continue.
class TtsChapter {
  const TtsChapter(this.blocks, {this.preface});

  final List<NovelBlock> blocks;

  /// Said before the text when the chapter does not open with its own title.
  final String? preface;
}

/// Where the read-aloud settings live. Behind an interface so the controller
/// can be tested without Hive.
abstract class TtsPreferences {
  double get rate;
  set rate(double v);
  double get pitch;
  set pitch(double v);
  bool get autoNext;
  set autoNext(bool v);
  String? voiceFor(String lang);
  void setVoiceFor(String lang, String? name);
}

class HiveTtsPreferences implements TtsPreferences {
  HiveTtsPreferences(this._hive);

  final HiveService _hive;

  @override
  double get rate => _hive.getTtsRate();
  @override
  set rate(double v) => _hive.saveTtsRate(v);
  @override
  double get pitch => _hive.getTtsPitch();
  @override
  set pitch(double v) => _hive.saveTtsPitch(v);
  @override
  bool get autoNext => _hive.getTtsAutoNext();
  @override
  set autoNext(bool v) => _hive.saveTtsAutoNext(v);
  @override
  String? voiceFor(String lang) => _hive.getTtsVoice(lang);
  @override
  void setVoiceFor(String lang, String? name) => _hive.saveTtsVoice(lang, name);
}

/// Reads a novel chapter aloud one sentence at a time.
///
/// One engine call per sentence, advancing on completion, is what makes the
/// rest possible: the sentence being spoken is known, so it can be painted;
/// pause is a stop that remembers the sentence (Android's engine has no real
/// pause); and a changed speed or voice takes effect by saying the current
/// sentence again.
///
/// Every run of the speaking loop carries a generation. Anything that
/// interrupts it — pause, skip, stop, a new setting — bumps the generation, so
/// a sentence finishing late can never move a loop that has been replaced.
class NovelTtsController extends ChangeNotifier {
  NovelTtsController({required TtsEngine engine, required TtsPreferences prefs})
    : _engine = engine,
      _prefs = prefs,
      _rate = prefs.rate,
      _pitch = prefs.pitch,
      _autoNext = prefs.autoNext;

  static const List<double> speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// Minutes on the sleep timer's menu. [sleepEndOfChapter] is its own entry.
  static const List<int> sleepChoices = [15, 30, 45, 60];
  static const int sleepEndOfChapter = -1;

  final TtsEngine _engine;
  final TtsPreferences _prefs;

  /// Asked for the next chapter when this one runs out. Null, or an answer
  /// of null, stops at the end.
  Future<TtsChapter?> Function()? onChapterEnd;
  void Function(TtsNotice notice)? onNotice;

  TtsStatus _status = TtsStatus.idle;
  TtsScript? _script;
  int _index = 0;
  int _gen = 0;
  int _failures = 0;
  bool _disposed = false;

  String _language = '';
  List<TtsVoice> _voices = const [];
  TtsVoice? _voice;
  Future<void>? _configured;

  double _rate;
  double _pitch;
  bool _autoNext;

  int _sleepMinutes = 0;
  DateTime? _sleepEndsAt;
  Timer? _sleepTimer;
  bool _sleepDue = false;

  bool get isSupported => _engine.isSupported;
  TtsStatus get status => _status;
  bool get isActive => _status != TtsStatus.idle;
  bool get isPlaying =>
      _status == TtsStatus.playing || _status == TtsStatus.loading;
  TtsScript? get script => _script;
  int get index => _index;
  String get language => _language;
  List<TtsVoice> get voices => _voices;
  TtsVoice? get voice => _voice;
  double get rate => _rate;
  double get pitch => _pitch;
  bool get autoNext => _autoNext;
  int get sleepMinutes => _sleepMinutes;
  DateTime? get sleepEndsAt => _sleepEndsAt;

  /// The sentence being spoken, or held while paused.
  TtsUtterance? get current {
    final s = _script;
    if (!isActive || s == null || _index < 0 || _index >= s.length) {
      return null;
    }
    return s[_index];
  }

  /// How much of the chapter has been spoken, in thousandths.
  int get spokenPermille {
    final s = _script;
    if (s == null || _index <= 0) return 0;
    return s.permilleAfter(_index - 1);
  }

  /// Replaces what is to be read. Stops anything in progress: the old
  /// chapter's sentence indices mean nothing in the new one.
  void setChapter(List<NovelBlock> blocks, {String? preface}) {
    _halt();
    _script = TtsScript.fromBlocks(blocks, preface: preface);
    _index = 0;
    _notify();
  }

  /// Loads the voices for [lang] and brings back the one chosen for it.
  Future<void> setLanguage(String lang) async {
    if (lang == _language && _configured != null) return;
    _language = lang;
    final all = await _engine.voices();
    if (_disposed) return;
    final matching = all.where((v) => voiceSpeaks(v.locale, lang)).toList()
      ..sort((a, b) {
        final pa = _localePreference(a.locale, lang);
        final pb = _localePreference(b.locale, lang);
        if (pa != pb) return pa - pb;
        if (a.isNetwork != b.isNetwork) return a.isNetwork ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    _voices = matching;
    final saved = _prefs.voiceFor(lang);
    _voice = saved == null
        ? null
        : matching.where((v) => v.name == saved).firstOrNull;
    _configured = null;
    _notify();
  }

  Future<void> play({int? from}) async {
    final s = _script;
    if (s == null || s.isEmpty) return;
    if (from != null) _index = from.clamp(0, s.length - 1);
    if (_index >= s.length) _index = 0;
    _startAfter(Future<void>.value());
  }

  void pause() {
    // Not while fetching the next chapter: the fetch is already under way and
    // resuming would ask for the one after it.
    if (_status != TtsStatus.playing) return;
    _gen++;
    _status = TtsStatus.paused;
    unawaited(_engine.stop());
    _notify();
  }

  void resume() {
    if (_status != TtsStatus.paused) return;
    _startAfter(Future<void>.value());
  }

  void toggle() {
    switch (_status) {
      case TtsStatus.playing:
        pause();
      case TtsStatus.paused:
        resume();
      case TtsStatus.idle:
        play();
      case TtsStatus.loading:
        break;
    }
  }

  void stop() {
    if (_status == TtsStatus.idle) return;
    _halt();
    _clearSleep();
    _notify();
  }

  void next() {
    final s = _script;
    if (s == null || s.isEmpty) return;
    if (_status == TtsStatus.playing) {
      _index++;
      _restart();
    } else if (_status == TtsStatus.paused) {
      _index = (_index + 1).clamp(0, s.length - 1);
      _notify();
    }
  }

  void previous() {
    final s = _script;
    if (s == null || s.isEmpty) return;
    _index = (_index - 1).clamp(0, s.length - 1);
    if (_status == TtsStatus.playing) {
      _restart();
    } else {
      _notify();
    }
  }

  /// Moves to [index] and keeps whatever state the reader is in.
  void seek(int index) {
    final s = _script;
    if (s == null || s.isEmpty) return;
    _index = index.clamp(0, s.length - 1);
    if (_status == TtsStatus.playing) {
      _restart();
    } else {
      _notify();
    }
  }

  Future<void> setRate(double multiplier) async {
    _rate = multiplier.clamp(0.5, 2.0);
    _prefs.rate = _rate;
    await _engine.setRate(_rate);
    _restartIfPlaying();
    _notify();
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    _prefs.pitch = _pitch;
    await _engine.setPitch(_pitch);
    _restartIfPlaying();
    _notify();
  }

  Future<void> setVoice(TtsVoice? voice) async {
    _voice = voice;
    _prefs.setVoiceFor(_language, voice?.name);
    _configured = null;
    _restartIfPlaying();
    _notify();
  }

  void setAutoNext(bool value) {
    _autoNext = value;
    _prefs.autoNext = value;
    _notify();
  }

  /// Minutes until reading stops after the sentence in progress, 0 for off,
  /// or [sleepEndOfChapter].
  void setSleep(int minutes) {
    _clearSleep();
    _sleepMinutes = minutes;
    if (minutes > 0) {
      final d = Duration(minutes: minutes);
      _sleepEndsAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, _onSleepTimer);
    }
    _notify();
  }

  void _onSleepTimer() {
    _sleepTimer = null;
    if (_status == TtsStatus.playing || _status == TtsStatus.loading) {
      _sleepDue = true;
    } else {
      _clearSleep();
      _notify();
    }
  }

  void _clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMinutes = 0;
    _sleepEndsAt = null;
    _sleepDue = false;
  }

  void _restartIfPlaying() {
    if (_status == TtsStatus.playing) _restart();
  }

  void _restart() => _startAfter(_engine.stop());

  void _startAfter(Future<void> before) {
    final gen = ++_gen;
    _status = TtsStatus.playing;
    _failures = 0;
    _notify();
    unawaited(_run(gen, before));
  }

  void _halt() {
    _gen++;
    if (_status != TtsStatus.idle) unawaited(_engine.stop());
    _status = TtsStatus.idle;
  }

  Future<void> _run(int gen, Future<void> before) async {
    await before;
    await (_configured ??= _configure());
    while (gen == _gen && !_disposed) {
      final s = _script;
      if (s == null) return;
      if (_index >= s.length) {
        if (!await _nextChapter(gen)) return;
        continue;
      }
      if (_sleepDue) {
        _halt();
        _clearSleep();
        _notify();
        onNotice?.call(TtsNotice.sleepStopped);
        return;
      }
      _notify();
      final ok = await _engine.speak(s[_index].text);
      if (gen != _gen || _disposed) return;
      if (!ok) {
        // Retried twice before giving up, because the cheap failures — an
        // engine still binding, a voice switching — clear on the next call.
        if (++_failures >= 3) {
          _halt();
          _notify();
          onNotice?.call(TtsNotice.failed);
          return;
        }
        continue;
      }
      _failures = 0;
      _index++;
    }
  }

  Future<bool> _nextChapter(int gen) async {
    if (_sleepMinutes == sleepEndOfChapter || _sleepDue) {
      _halt();
      _clearSleep();
      _notify();
      onNotice?.call(TtsNotice.sleepStopped);
      return false;
    }
    final load = onChapterEnd;
    if (!_autoNext || load == null) {
      _halt();
      _notify();
      return false;
    }
    _status = TtsStatus.loading;
    _notify();
    TtsChapter? chapter;
    try {
      chapter = await load();
    } catch (_) {
      chapter = null;
    }
    if (gen != _gen || _disposed) return false;
    final script = chapter == null
        ? null
        : TtsScript.fromBlocks(chapter.blocks, preface: chapter.preface);
    if (script == null || script.isEmpty) {
      _halt();
      _notify();
      return false;
    }
    _script = script;
    _index = 0;
    _status = TtsStatus.playing;
    _notify();
    return true;
  }

  Future<void> _configure() async {
    if (_language.isNotEmpty) {
      final locale = _voices.isNotEmpty ? _voices.first.locale : _language;
      final ok = await _engine.setLanguage(locale);
      if (!ok && _voices.isEmpty) onNotice?.call(TtsNotice.noVoiceForLanguage);
    }
    if (_voice != null) await _engine.setVoice(_voice);
    await _engine.setRate(_rate);
    await _engine.setPitch(_pitch);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _sleepTimer?.cancel();
    unawaited(_engine.stop());
    super.dispose();
  }
}

/// Lower sorts first: the language's home region, then the rest.
int _localePreference(String locale, String lang) {
  final l = locale.toLowerCase().replaceAll('_', '-');
  const home = {
    'en': 'en-us',
    'pt': 'pt-br',
    'es': 'es-es',
    'zh': 'zh-cn',
    'ar': 'ar-sa',
    'yue': 'yue-hk',
  };
  final want = home[lang] ?? '$lang-$lang';
  return l == want ? 0 : 1;
}
