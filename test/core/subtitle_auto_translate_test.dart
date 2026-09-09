import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/subtitles/subtitle_auto_translate.dart';

AutoTranslateAction decide({
  bool enabled = true,
  bool isLive = false,
  bool alreadyRan = false,
  bool hasTargetTrack = false,
  bool hasReadyTranslation = false,
}) =>
    SubtitleAutoTranslate.decide(
      enabled: enabled,
      isLive: isLive,
      alreadyRan: alreadyRan,
      hasTargetTrack: hasTargetTrack,
      hasReadyTranslation: hasReadyTranslation,
    );

void main() {
  group('free before paid', () {
    test('a published translation is used even with the switch off', () {
      // It is a download. A viewer with no subtitles in their language is
      // unambiguously better off with one, and it costs nobody anything.
      expect(
        decide(enabled: false, hasReadyTranslation: true),
        AutoTranslateAction.loadReady,
      );
    });

    test('and it is preferred over spending the allowance', () {
      // The other order burns somebody's daily limit on an episode that was
      // already translated and sitting there.
      expect(
        decide(enabled: true, hasReadyTranslation: true),
        AutoTranslateAction.loadReady,
      );
    });

    test('the switch is what authorises spending it', () {
      expect(decide(enabled: true), AutoTranslateAction.translateNow);
      expect(decide(enabled: false), AutoTranslateAction.none);
    });
  });

  group('when nothing should happen', () {
    test('a track already reads in the target language', () {
      // Translating over the top replaces a human subtitle with a machine one.
      expect(decide(hasTargetTrack: true), AutoTranslateAction.none);
      expect(
        decide(hasTargetTrack: true, hasReadyTranslation: true),
        AutoTranslateAction.none,
      );
    });

    test('a live channel has no subtitle file to translate', () {
      expect(decide(isLive: true), AutoTranslateAction.none);
      expect(
        decide(isLive: true, hasReadyTranslation: true),
        AutoTranslateAction.none,
      );
    });

    test('the episode has already been attempted', () {
      // Per episode, not per session: a failed attempt must not be retried on
      // every subtitle reload, and a successful one must not run twice.
      expect(decide(alreadyRan: true), AutoTranslateAction.none);
      expect(
        decide(alreadyRan: true, hasReadyTranslation: true),
        AutoTranslateAction.none,
      );
    });
  });

  group('does a track already read in this language', () {
    test('by two-letter code, three-letter code, or name', () {
      for (final label in ['en', 'eng', 'English', 'ENGLISH']) {
        expect(
          SubtitleAutoTranslate.labelMatchesLanguage(label, 'en'),
          isTrue,
          reason: label,
        );
      }
    });

    test('a region is a variant of the same language', () {
      expect(SubtitleAutoTranslate.labelMatchesLanguage('en-US', 'en'), isTrue);
      expect(SubtitleAutoTranslate.labelMatchesLanguage('pt_BR', 'pt'), isTrue);
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('Brazilian Portuguese', 'pt'),
        isTrue,
      );
    });

    test('a substring is not a match', () {
      // The trap this anchors against: a plain `contains` makes "Indonesian"
      // match `id` and "Korean" match `ko`, so half the titles carrying either
      // would be judged already readable in a language they do not have.
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('Indonesian', 'id'),
        isTrue,
        reason: 'by name, which is correct',
      );
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('Korean', 'ko'),
        isTrue,
        reason: 'by name, which is correct',
      );
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('Slovenian', 'en'),
        isFalse,
        reason: 'contains "en" but is not English',
      );
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('French', 'fr'),
        isTrue,
      );
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('Afrikaans', 'ar'),
        isFalse,
        reason: 'contains "a", "r"; not Arabic',
      );
    });

    test('the app\'s own language is recognised however it is written', () {
      for (final label in ["O'zbekcha", 'Uzbek', 'uzb', 'uz', 'Узбекский']) {
        expect(
          SubtitleAutoTranslate.labelMatchesLanguage(label, 'uz'),
          isTrue,
          reason: label,
        );
      }
    });

    test('a decorated label still counts', () {
      // Publishers add all of these.
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('English (forced)', 'en'),
        isTrue,
      );
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('AI · UZ', 'uz'),
        isTrue,
      );
      expect(
        SubtitleAutoTranslate.labelMatchesLanguage('Русский [SDH]', 'ru'),
        isTrue,
      );
    });

    test('an empty code matches nothing', () {
      expect(SubtitleAutoTranslate.labelMatchesLanguage('English', ''), isFalse);
    });

    test('anyMatches scans a whole track list', () {
      const labels = ['English', 'Français', 'Русский'];
      expect(SubtitleAutoTranslate.anyMatches(labels, 'fr'), isTrue);
      expect(SubtitleAutoTranslate.anyMatches(labels, 'uz'), isFalse);
      expect(SubtitleAutoTranslate.anyMatches(const [], 'en'), isFalse);
    });
  });

  test('the core layer stays free of Flutter', () {
    final source =
        File('lib/core/subtitles/subtitle_auto_translate.dart').readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
