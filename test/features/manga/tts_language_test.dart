import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/data/tts/tts_engine.dart';
import 'package:soplay/features/manga/domain/reading/tts_language.dart';

void main() {
  group('resolveTtsLanguage', () {
    test('a declared language matching the text wins', () {
      expect(resolveTtsLanguage(declared: 'es', sample: 'Hola, amigo.'), 'es');
      expect(
        resolveTtsLanguage(declared: 'uk', sample: 'Добрий вечір, друже.'),
        'uk',
      );
      expect(resolveTtsLanguage(declared: 'pt-BR', sample: 'Olá.'), 'pt');
    });

    test('the script overrules a declaration it contradicts', () {
      // Sites tagged English that serve a Russian translation, and the
      // other way round.
      expect(
        resolveTtsLanguage(declared: 'en', sample: 'Все смешалось в доме.'),
        'ru',
      );
      expect(
        resolveTtsLanguage(declared: 'ru', sample: 'It was a dark night.'),
        'en',
      );
    });

    test('undeclared or "all" falls back to the script, then English', () {
      expect(resolveTtsLanguage(declared: 'all', sample: '吾輩は猫である。'), 'ja');
      expect(resolveTtsLanguage(declared: '', sample: '混沌未分天地亂。'), 'zh');
      expect(resolveTtsLanguage(declared: null, sample: '나는 고양이다.'), 'ko');
      expect(resolveTtsLanguage(declared: null, sample: 'كان يا ما كان'), 'ar');
      expect(resolveTtsLanguage(declared: null, sample: 'Once upon.'), 'en');
    });

    test('Cantonese survives as itself', () {
      expect(resolveTtsLanguage(declared: 'zh-hk', sample: '佢哋走咗。'), 'yue');
    });
  });

  group('voiceSpeaks', () {
    test('matches by language across the engines\' locale spellings', () {
      expect(voiceSpeaks('en-US', 'en'), isTrue);
      expect(voiceSpeaks('en_GB', 'en'), isTrue);
      expect(voiceSpeaks('es-ES', 'en'), isFalse);
      expect(voiceSpeaks('in-ID', 'id'), isTrue);
      expect(voiceSpeaks('yue-HK', 'yue'), isTrue);
      expect(voiceSpeaks('zh-HK', 'yue'), isTrue);
      expect(voiceSpeaks('zh-HK', 'zh'), isFalse);
      expect(voiceSpeaks('zh-CN', 'zh'), isTrue);
    });
  });

  group('platformSpeechRate', () {
    test('normal speed is each engine\'s own normal', () {
      expect(platformSpeechRate(1, TargetPlatform.android), 0.5);
      expect(platformSpeechRate(1, TargetPlatform.iOS), 0.5);
      expect(platformSpeechRate(1, TargetPlatform.windows), 0.5);
      expect(platformSpeechRate(1, TargetPlatform.android, web: true), 1);
    });

    test('double speed and half speed map to each engine\'s scale', () {
      expect(platformSpeechRate(2, TargetPlatform.android), 1.0);
      expect(platformSpeechRate(0.5, TargetPlatform.android), 0.25);
      expect(platformSpeechRate(2, TargetPlatform.windows), 1.5);
      expect(platformSpeechRate(2, TargetPlatform.iOS), closeTo(0.7, 1e-9));
      expect(platformSpeechRate(0.5, TargetPlatform.macOS), 0.25);
    });

    test('out-of-range multipliers are clamped', () {
      expect(platformSpeechRate(9, TargetPlatform.android), 1.0);
      expect(platformSpeechRate(0.1, TargetPlatform.android), 0.25);
    });
  });
}
