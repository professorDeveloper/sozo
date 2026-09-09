import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/retry_policy.dart';

RetryAction decide({
  String message = 'timed out',
  bool isLive = false,
  int attempts = 0,
  int lifetime = 0,
  bool hasUntriedSource = true,
}) =>
    RetryPolicy.decide(
      message: message,
      isLive: isLive,
      attempts: attempts,
      lifetime: lifetime,
      hasUntriedSource: hasUntriedSource,
    );

void main() {
  group('classification', () {
    test('decoder failures are named across all three engines', () {
      for (final raw in const [
        'Cannot Decode',
        'error -12906',
        'CoreMediaErrorDomain',
        'format_supported=NO_EXCEEDS_CAPABILITIES',
        'MediaCodecVideoDecoderException',
        'DecoderInitializationException',
        'Decoder failed',
      ]) {
        expect(RetryPolicy.isDecoderError(raw), isTrue, reason: raw);
      }
    });

    test('a decoder error is never also recoverable', () {
      // The call site routes decoder errors first, but relying on branch order
      // makes that order load-bearing with nothing to say so.
      for (final raw in const [
        'Decoder failed',
        'MediaCodecVideoDecoderException',
        'DecoderInitializationException',
      ]) {
        expect(RetryPolicy.isDecoderError(raw), isTrue, reason: raw);
        expect(RetryPolicy.isRecoverableError(raw), isFalse, reason: raw);
      }
    });

    test('bare "mediacodec" is recoverable — the codec-specific ones are not',
        () {
      // A deliberate and easily-lost distinction. ExoPlayer says "MediaCodec"
      // for transient trouble worth re-opening, and names the exception class
      // when the device genuinely cannot decode the profile. Collapsing the
      // two would either retry undecodable files forever or abandon streams
      // that a second attempt would have played.
      expect(RetryPolicy.isDecoderError('MediaCodec error 0x8'), isFalse);
      expect(RetryPolicy.isRecoverableError('MediaCodec error 0x8'), isTrue);

      expect(
        RetryPolicy.isDecoderError('MediaCodecVideoDecoderException: 0x8'),
        isTrue,
      );
    });

    test('timeouts are recoverable, refusals are not', () {
      expect(RetryPolicy.isRecoverableError('Connection timed out'), isTrue);
      expect(RetryPolicy.isRecoverableError('HTTP 403 Forbidden'), isFalse);
      expect(RetryPolicy.isRecoverableError('404 not found'), isFalse);
    });

    test('matching ignores case', () {
      expect(RetryPolicy.isDecoderError('DECODER FAILED'), isTrue);
      expect(RetryPolicy.isRecoverableError('TIMED OUT'), isTrue);
    });
  });

  group('live is a different problem', () {
    test('a channel reconnects where a film would give up', () {
      // A film either plays or is broken. A channel drops constantly and the
      // only correct answer is to reconnect.
      expect(decide(isLive: true, lifetime: 50, message: 'HTTP 403'),
          RetryAction.reconnect);
      expect(decide(isLive: false, lifetime: 50, message: 'HTTP 403'),
          RetryAction.giveUp);
    });

    test('even a live budget ends eventually', () {
      expect(
        decide(isLive: true, lifetime: RetryPolicy.maxLiveRetries),
        RetryAction.giveUp,
      );
    });

    test('the backoff climbs and then holds', () {
      expect(RetryPolicy.liveBackoff(0), const Duration(seconds: 1));
      expect(RetryPolicy.liveBackoff(2), const Duration(seconds: 4));
      expect(RetryPolicy.liveBackoff(4), const Duration(seconds: 15));
      expect(RetryPolicy.liveBackoff(99), const Duration(seconds: 15),
          reason: 'a channel off air all evening must not be hammered');
      expect(RetryPolicy.liveBackoff(-1), const Duration(seconds: 1));
    });
  });

  group('a file', () {
    test('a decode failure moves to another encode, never retries this one', () {
      expect(
        decide(message: 'Decoder failed', hasUntriedSource: true),
        RetryAction.nextSource,
      );
    });

    test('and gives up once no other encode is left', () {
      expect(
        decide(message: 'Decoder failed', hasUntriedSource: false),
        RetryAction.giveUp,
      );
    });

    test('a timeout is retried, up to the per-source ceiling', () {
      expect(decide(message: 'timed out', attempts: 0), RetryAction.nextSource);
      expect(decide(message: 'timed out', attempts: 1), RetryAction.nextSource);
    });

    test('the episode budget ends the walk however healthy the error looks', () {
      // The ceiling that stops a broken title spinning all evening.
      expect(
        decide(message: 'timed out', lifetime: RetryPolicy.maxLifetimeRetries),
        RetryAction.giveUp,
      );
    });

    test('an unrecognised error still walks the ladder while it has one', () {
      // Unknown does not mean fatal: another mirror may simply work.
      expect(
        decide(message: 'something nobody has seen', hasUntriedSource: true),
        RetryAction.nextSource,
      );
      expect(
        decide(message: 'something nobody has seen', hasUntriedSource: false),
        RetryAction.giveUp,
      );
    });

    test('an empty message is treated as unknown, not as a crash', () {
      expect(decide(message: '', hasUntriedSource: true),
          RetryAction.nextSource);
    });
  });

  test('the budgets are the ones the player shipped with', () {
    // Pinned rather than described: these numbers were tuned against real
    // failures and a silent change to them is a behaviour change.
    expect(RetryPolicy.maxLifetimeRetries, 4);
    expect(RetryPolicy.maxLiveRetries, 1000);
    expect(RetryPolicy.maxAttemptsPerSource, 2);
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/playback/retry_policy.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
