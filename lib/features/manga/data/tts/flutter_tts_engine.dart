import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

/// [TtsEngine] over flutter_tts: Android TextToSpeech, AVSpeechSynthesizer on
/// Apple platforms, SAPI/WinRT on Windows.
///
/// Completion is tracked here through the plugin's handlers rather than
/// `awaitSpeakCompletion`, because on Android a stopped utterance never
/// completes that future and the reader would wait on it forever. A finish
/// only counts once the utterance has started: the cancel for the sentence
/// just stopped can arrive after the next one was handed over.
class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _injected = tts;

  final FlutterTts? _injected;
  FlutterTts? _tts;
  Completer<bool>? _pending;
  bool _started = false;
  Timer? _watchdog;

  @override
  bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  Future<FlutterTts> _engine() async {
    final existing = _tts;
    if (existing != null) return existing;
    final tts = _injected ?? FlutterTts();
    _tts = tts;
    tts.setStartHandler(() {
      _started = true;
      _watchdog?.cancel();
    });
    tts.setCompletionHandler(() {
      if (_started) _finish(true);
    });
    tts.setCancelHandler(() {
      if (_started) _finish(false);
    });
    tts.setErrorHandler((_) => _finish(false));
    await _quietly(() => tts.awaitSpeakCompletion(false));
    if (!kIsWeb && Platform.isIOS) {
      // Playback, so the ring/silent switch does not mute a chapter somebody
      // asked to hear.
      await _quietly(() => tts.setSharedInstance(true));
      await _quietly(
        () => tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.allowAirPlay,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        ),
      );
    }
    return tts;
  }

  void _finish(bool ok) {
    _watchdog?.cancel();
    _started = false;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(ok);
  }

  @override
  Future<bool> speak(String text) async {
    if (!isSupported) return false;
    final tts = await _engine();
    _finish(false);
    final done = Completer<bool>();
    _pending = done;
    // An engine that never starts (a voice still downloading, a dead service)
    // would otherwise hold the reader silent with no way to tell.
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (identical(_pending, done) && !_started) _finish(false);
    });
    try {
      final started = await tts.speak(text);
      if (started != 1 && !done.isCompleted) _finish(false);
    } catch (_) {
      _finish(false);
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    _finish(false);
    final tts = _tts;
    if (tts == null) return;
    await _quietly(tts.stop);
  }

  @override
  Future<void> setRate(double multiplier) async {
    if (!isSupported) return;
    final tts = await _engine();
    await _quietly(
      () => tts.setSpeechRate(
        platformSpeechRate(multiplier, defaultTargetPlatform),
      ),
    );
  }

  @override
  Future<void> setPitch(double pitch) async {
    if (!isSupported) return;
    final tts = await _engine();
    await _quietly(() => tts.setPitch(pitch.clamp(0.5, 2.0)));
  }

  @override
  Future<bool> setLanguage(String lang) async {
    if (!isSupported) return false;
    final tts = await _engine();
    try {
      return await tts.setLanguage(lang) == 1;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setVoice(TtsVoice? voice) async {
    if (!isSupported) return false;
    final tts = await _engine();
    try {
      if (voice == null) {
        if (!kIsWeb && Platform.isAndroid) await tts.clearVoice();
        return true;
      }
      return await tts.setVoice(voice.raw) == 1;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<TtsVoice>> voices() async {
    if (!isSupported) return const [];
    final tts = await _engine();
    try {
      final list = await tts.getVoices;
      if (list is! List) return const [];
      final out = <TtsVoice>[];
      for (final v in list) {
        if (v is! Map) continue;
        final raw = {
          for (final e in v.entries)
            if (e.value != null) e.key.toString(): e.value.toString(),
        };
        final name = raw['name'] ?? '';
        final locale = raw['locale'] ?? '';
        if (name.isEmpty || locale.isEmpty) continue;
        out.add(TtsVoice(name: name, locale: locale, raw: raw));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _quietly(Future<dynamic> Function() call) async {
    try {
      await call();
    } catch (_) {}
  }
}
