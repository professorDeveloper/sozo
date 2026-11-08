import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/retry_policy.dart';
import 'package:soplay/features/detail/presentation/pages/player_page.dart';

void main() {
  group('retrying the same source', () {
    test('is automatic, so Stop is offered', () {
      final step = ServerSwitch.retrySame(to: 'Server 1', attempt: 3);
      expect(step.automatic, isTrue);
      expect(step.sameServer, isTrue);
      expect(step.attempt, 3);
      expect(step.maxAttempts, RetryPolicy.maxLifetimeRetries);
    });

    test('shows one server, not a journey to itself', () {
      final step = ServerSwitch.retrySame(to: 'Server 1', attempt: 1);
      expect(step.from, isNull);
      expect(step.to, 'Server 1');
    });

    test('never reads attempt 0', () {
      expect(ServerSwitch.retrySame(to: 'A', attempt: 0).attempt, 1);
    });

    test('a switch to another server is not a retry', () {
      expect(
        ServerSwitch.automatic(from: 'A', to: 'B', attempt: 1).sameServer,
        isFalse,
      );
    });

    test('the last fallback of the ladder uses it inside try/finally', () {
      final media = File(
        'lib/features/detail/presentation/pages/player_page.media.dart',
      ).readAsStringSync();
      final start = media.indexOf('Future<void> _autoRetry()');
      final end = media.indexOf('\n  }\n', start);
      final body = media.substring(start, end);
      expect(body, contains('ServerSwitch.retrySame'));
      expect(body, contains('identical(_serverSwitch, again)'));
    });
  });

  group('system gesture edges', () {
    const size = Size(800, 400);
    const insets = EdgeInsets.fromLTRB(24, 0, 24, 20);

    test('a drag from an edge strip belongs to the system', () {
      expect(
        startsInSystemGestureArea(const Offset(10, 200), size, insets),
        isTrue,
      );
      expect(
        startsInSystemGestureArea(const Offset(790, 200), size, insets),
        isTrue,
      );
      expect(
        startsInSystemGestureArea(const Offset(400, 390), size, insets),
        isTrue,
      );
    });

    test('anywhere else is the player\'s', () {
      expect(
        startsInSystemGestureArea(const Offset(400, 200), size, insets),
        isFalse,
      );
      expect(
        startsInSystemGestureArea(const Offset(10, 200), size, EdgeInsets.zero),
        isFalse,
      );
    });
  });
}
