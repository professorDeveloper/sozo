import 'dart:async';

import 'package:soplay/features/manga/data/tts/tts_engine.dart';

/// An engine whose sentences finish when the test says so.
class FakeEngine implements TtsEngine {
  final spoken = <String>[];
  final calls = <String>[];
  Completer<bool>? _pending;
  List<TtsVoice> voiceList = const [];
  bool failEverything = false;

  @override
  bool get isSupported => true;

  @override
  Future<bool> speak(String text) {
    spoken.add(text);
    if (failEverything) return Future.value(false);
    _pending?.complete(false);
    final c = Completer<bool>();
    _pending = c;
    return c.future;
  }

  /// The sentence being spoken reaches its end.
  void finish() {
    final p = _pending;
    _pending = null;
    p?.complete(true);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final p = _pending;
    _pending = null;
    p?.complete(false);
  }

  @override
  Future<void> setRate(double multiplier) async =>
      calls.add('rate $multiplier');

  @override
  Future<void> setPitch(double pitch) async => calls.add('pitch $pitch');

  @override
  Future<bool> setLanguage(String lang) async {
    calls.add('lang $lang');
    return voiceList.isNotEmpty;
  }

  @override
  Future<bool> setVoice(TtsVoice? voice) async {
    calls.add('voice ${voice?.name}');
    return true;
  }

  @override
  Future<List<TtsVoice>> voices() async => voiceList;
}
