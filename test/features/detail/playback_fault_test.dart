import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/playback_fault.dart';

void main() {
  group('classification', () {
    test('ExoPlayer decoder failures are decoder faults', () {
      for (final raw in const [
        'MediaCodecVideoRenderer error',
        'Decoder init failed',
        'RendererException',
      ]) {
        expect(PlaybackFault.classify(raw).kind, PlaybackFaultKind.decoder,
            reason: raw);
      }
    });

    test('AVFoundation codes mean unsupported, not "try another quality"', () {
      // These are checked BEFORE the decoder match on purpose: retrying the
      // same file at another quality cannot help, so the advice differs.
      for (final raw in const [
        'Cannot Decode',
        'error -12906',
        'error -12939',
        'CoreMediaErrorDomain',
      ]) {
        expect(
          PlaybackFault.classify(raw).kind,
          PlaybackFaultKind.unsupportedFormat,
          reason: raw,
        );
      }
    });

    test('a blocked or unreadable source is its own kind', () {
      for (final raw in const [
        'Source error',
        'UnrecognizedInputFormatException',
        'NoDeclaredBrand',
      ]) {
        expect(
          PlaybackFault.classify(raw).kind,
          PlaybackFaultKind.sourceBlocked,
          reason: raw,
        );
      }
    });

    test('an http data source failure is a network fault', () {
      expect(
        PlaybackFault.classify('HTTP data source: 403').kind,
        PlaybackFaultKind.network,
      );
    });

    test('anything unrecognised falls through to unknown', () {
      expect(
        PlaybackFault.classify('something nobody has seen yet').kind,
        PlaybackFaultKind.unknown,
      );
    });

    test('an empty message is unknown, not a crash', () {
      expect(PlaybackFault.classify('').kind, PlaybackFaultKind.unknown);
      expect(PlaybackFault.classify('   ').kind, PlaybackFaultKind.unknown);
    });

    test('matching ignores case', () {
      expect(
        PlaybackFault.classify('MEDIACODEC FAILURE').kind,
        PlaybackFaultKind.decoder,
      );
    });

    test('the engine\'s own words are kept for a bug report', () {
      const raw = 'MediaCodecRenderer: 0x80000000';
      expect(PlaybackFault.classify(raw).raw, raw);
    });
  });

  group('advice', () {
    test('decoder and unsupported are the two that suggest the browser', () {
      expect(
        const PlaybackFault(PlaybackFaultKind.decoder).isCodecFault,
        isTrue,
      );
      expect(
        const PlaybackFault(PlaybackFaultKind.unsupportedFormat).isCodecFault,
        isTrue,
      );
      expect(
        const PlaybackFault(PlaybackFaultKind.network).isCodecFault,
        isFalse,
      );
      expect(
        const PlaybackFault(PlaybackFaultKind.sourceBlocked).isCodecFault,
        isFalse,
      );
    });
  });

  group('localisation contract', () {
    test('every kind carries a distinct player.fault.* key', () {
      final keys = PlaybackFaultKind.values.map((k) => k.messageKey).toList();
      expect(keys.toSet().length, keys.length, reason: 'keys must be unique');
      for (final k in keys) {
        expect(k, startsWith('player.fault.'));
      }
    });

    test('all four locales define every one of them', () {
      // The point of the whole file: a failure must not fall back to English
      // for the three audiences who did not choose it.
      for (final locale in const ['en', 'uz', 'ru', 'ar']) {
        final text = File('assets/translations/$locale.json').readAsStringSync();
        for (final kind in PlaybackFaultKind.values) {
          final leaf = kind.messageKey.split('.').last;
          expect(
            text.contains('"$leaf"'),
            isTrue,
            reason: '$locale.json is missing ${kind.messageKey}',
          );
        }
      }
    });
  });

  test('the domain layer stays free of Flutter', () {
    // If this file ever imports material.dart the fault can no longer be
    // classified in a plain Dart test, which is most of why it exists.
    final source = File(
      'lib/features/detail/domain/playback/playback_fault.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('easy_localization'), isFalse);
  });
}
