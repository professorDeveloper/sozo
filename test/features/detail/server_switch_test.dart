import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/retry_policy.dart';
import 'package:soplay/features/detail/presentation/pages/player_page.dart';

void main() {
  group('an automatic server switch', () {
    test('counts against the lifetime retry budget', () {
      final step = ServerSwitch.automatic(
        from: 'Server 1',
        to: 'Server 2',
        attempt: 2,
      );
      expect(step.automatic, isTrue);
      expect(step.attempt, 2);
      expect(step.maxAttempts, RetryPolicy.maxLifetimeRetries);
    });

    test('never reads "0 of 4" or "5 of 4"', () {
      // The sniff fallback walks without spending the budget, and the codec
      // path can spend past it.
      expect(
        ServerSwitch.automatic(from: null, to: 'B', attempt: 0).attempt,
        1,
      );
      final over = ServerSwitch.automatic(
        from: 'A',
        to: 'B',
        attempt: RetryPolicy.maxLifetimeRetries + 1,
      );
      expect(over.attempt, over.maxAttempts);
    });

    test('a manual pick has no counter and no Stop', () {
      expect(const ServerSwitch(from: 'A', to: 'B').automatic, isFalse);
    });
  });

  test('the ladder shows the switch screen instead of a snackbar', () {
    final media = File(
      'lib/features/detail/presentation/pages/player_page.media.dart',
    ).readAsStringSync();
    final start = media.indexOf('Future<void> _autoRetry()');
    final end = media.indexOf('\n  }\n', start);
    final body = media.substring(start, end);
    expect(body, contains('ServerSwitch.automatic'));
    expect(body, isNot(contains('showSnackBar')));
  });
}
