import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/search/presentation/widgets/voice_search_session.dart';

void main() {
  group('matchSpeechLocale', () {
    const android = ['de_DE', 'en_GB', 'en_US', 'ru_RU', 'uz_UZ', 'pt_PT', 'pt_BR'];

    test('the app language picks its recogniser locale', () {
      expect(matchSpeechLocale(const Locale('ru'), android), 'ru_RU');
      expect(matchSpeechLocale(const Locale('uz'), android), 'uz_UZ');
    });

    test('the system locale wins among the same language', () {
      expect(
        matchSpeechLocale(
          const Locale('en'),
          android,
          systemLocaleId: 'en_GB',
        ),
        'en_GB',
      );
    });

    test('without a system match, the region the copy is written for', () {
      expect(
        matchSpeechLocale(const Locale('en'), android, systemLocaleId: 'de_DE'),
        'en_US',
      );
      expect(matchSpeechLocale(const Locale('pt'), android), 'pt_BR');
    });

    test('an explicit country beats the system locale', () {
      expect(
        matchSpeechLocale(
          const Locale('pt', 'PT'),
          android,
          systemLocaleId: 'pt_BR',
        ),
        'pt_PT',
      );
    });

    test('iOS hyphenated ids match too, and come back as given', () {
      expect(
        matchSpeechLocale(const Locale('de'), ['en-US', 'de-AT', 'de-DE']),
        'de-DE',
      );
    });

    test('a language the recogniser lacks falls back to the system', () {
      expect(matchSpeechLocale(const Locale('ckb'), android), isNull);
      expect(matchSpeechLocale(const Locale('en'), const []), isNull);
    });

    test('Indonesian matches the legacy "in" code', () {
      expect(matchSpeechLocale(const Locale('id'), ['en_US', 'in_ID']), 'in_ID');
    });

    test('Cantonese matches yue and Hong Kong Chinese, not Mandarin', () {
      expect(
        matchSpeechLocale(const Locale('yue'), ['zh_CN', 'yue-Hant-HK']),
        'yue-Hant-HK',
      );
      expect(matchSpeechLocale(const Locale('yue'), ['zh_CN', 'zh_HK']), 'zh_HK');
      expect(matchSpeechLocale(const Locale('yue'), ['zh_CN', 'zh_TW']), isNull);
    });
  });

  group('VoiceSearchMachine', () {
    const start = VoiceSearchState.initial;
    final listening = VoiceSearchMachine.listeningStarted(start);

    test('starts, then listens', () {
      expect(start.phase, VoicePhase.starting);
      expect(listening.phase, VoicePhase.listening);
    });

    test('partial words keep listening, a final result finishes', () {
      final partial = VoiceSearchMachine.heard(listening, 'the dark');
      expect(partial, const VoiceSearchState(VoicePhase.listening, words: 'the dark'));
      final done = VoiceSearchMachine.heard(partial, 'the dark knight', isFinal: true);
      expect(done, const VoiceSearchState(VoicePhase.done, words: 'the dark knight'));
    });

    test('an empty final result keeps what was already heard', () {
      final partial = VoiceSearchMachine.heard(listening, 'dune');
      expect(
        VoiceSearchMachine.heard(partial, '', isFinal: true),
        const VoiceSearchState(VoicePhase.done, words: 'dune'),
      );
    });

    test('ending in silence says it did not catch anything', () {
      expect(VoiceSearchMachine.ended(listening).phase, VoicePhase.noSpeech);
      expect(
        VoiceSearchMachine.heard(listening, '', isFinal: true).phase,
        VoicePhase.noSpeech,
      );
    });

    test('ending with words finishes with them', () {
      final partial = VoiceSearchMachine.heard(listening, 'alien');
      expect(
        VoiceSearchMachine.ended(partial),
        const VoiceSearchState(VoicePhase.done, words: 'alien'),
      );
    });

    test('permanent errors map to what the user can do about them', () {
      VoicePhase after(String code) =>
          VoiceSearchMachine.error(listening, code, permanent: true).phase;
      expect(after('error_no_match'), VoicePhase.noSpeech);
      expect(after('error_speech_timeout'), VoicePhase.noSpeech);
      expect(after('error_permission'), VoicePhase.permissionDenied);
      expect(after('error_network'), VoicePhase.network);
      expect(after('error_network_timeout'), VoicePhase.network);
      expect(after('error_server'), VoicePhase.network);
      expect(after('error_busy'), VoicePhase.recognizer);
      expect(after('error_audio_error'), VoicePhase.recognizer);
      expect(after('error_speech_recognizer_disabled'), VoicePhase.unavailable);
    });

    test('an error after words were heard still returns the words', () {
      final partial = VoiceSearchMachine.heard(listening, 'heat');
      expect(
        VoiceSearchMachine.error(partial, 'error_no_match', permanent: true),
        const VoiceSearchState(VoicePhase.done, words: 'heat'),
      );
    });

    test('a passing error explains an empty end without stopping early', () {
      final s = VoiceSearchMachine.error(listening, 'error_network', permanent: false);
      expect(s.phase, VoicePhase.listening);
      expect(VoiceSearchMachine.ended(s).phase, VoicePhase.network);
    });

    test('init failure distinguishes a refused permission from no recogniser', () {
      expect(
        VoiceSearchMachine.initFailed(hasPermission: false).phase,
        VoicePhase.permissionDenied,
      );
      expect(
        VoiceSearchMachine.initFailed(hasPermission: true).phase,
        VoicePhase.unavailable,
      );
      expect(
        VoiceSearchMachine.listenFailed(hasPermission: true).phase,
        VoicePhase.recognizer,
      );
    });

    test('a microphone that never opens is an error, but only before it opens', () {
      expect(VoiceSearchMachine.startTimedOut(start).phase, VoicePhase.recognizer);
      expect(VoiceSearchMachine.startTimedOut(listening), listening);
    });

    test('failures are terminal until retried', () {
      final failed = VoiceSearchMachine.ended(listening);
      expect(failed.isFailure, isTrue);
      expect(failed.canRetry, isTrue);
      expect(VoiceSearchMachine.heard(failed, 'late'), failed);
      expect(VoiceSearchMachine.listeningStarted(failed), failed);
      expect(
        VoiceSearchMachine.error(failed, 'error_network', permanent: true),
        failed,
      );
      expect(VoiceSearchMachine.retry(), start);
    });

    test('a device with no recogniser offers no retry', () {
      final s = VoiceSearchMachine.initFailed(hasPermission: true);
      expect(s.isFailure, isTrue);
      expect(s.canRetry, isFalse);
    });

    test('language errors are recognised for the system-locale fallback', () {
      expect(VoiceSearchMachine.isLanguageError('error_language_not_supported'), isTrue);
      expect(VoiceSearchMachine.isLanguageError('error_language_unavailable'), isTrue);
      expect(VoiceSearchMachine.isLanguageError('error_network'), isFalse);
    });
  });
}
