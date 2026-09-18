import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gates on the player's save cadence and on retries keeping their place.
///
/// These read source rather than driving the widget, and that is a deliberate
/// trade. `_PlayerPageState` needs a platform video controller, a Hive box, six
/// registered services and a route to live on; the behaviour under test is a
/// five-second timer over a twenty-minute session. A widget test of it would be
/// slow, flaky and — because the defects here are *missing* calls — would pass
/// for the wrong reason more often than it caught anything.
///
/// The defects these gates exist for, all shipped at once:
///
///   * `_scheduleHistorySave` armed a ONE-SHOT five-second `Timer`, and its
///     callback hit the ten-second floor in `_saveHistory` and wrote nothing.
///     Nothing re-armed it. So a viewer who pressed play and watched straight
///     through had their position saved exactly once, in `dispose` — which
///     Android does not run when it kills an app for memory, and which a crash
///     or a force-quit never reaches. Lose the network mid-episode, close the
///     app, and the episode was simply never watched.
///   * both retries tore the controller down and rebuilt it with no `resumeAt`,
///     so recovering from a dropped connection restarted the episode at zero.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// The body of `name`, from its signature to the closing brace at the same
  /// indent. Enough to tell "this call is inside that function" apart from
  /// "this call is somewhere in a four-thousand-line file", which is the whole
  /// question for a missing-call gate.
  ///
  /// Throws rather than `expect`s, so it is safe to call while groups are being
  /// declared as well as inside a test. A rename failing loudly is the point:
  /// silently matching nothing would turn every gate below green.
  String bodyOf(String source, String signature) {
    final start = source.indexOf(signature);
    if (start == -1) {
      throw StateError(
        'cannot gate `$signature` — it was renamed or removed, so this test is '
        'no longer testing anything. Update the gate with the refactor.',
      );
    }
    final indent = ' ' * (start - source.lastIndexOf('\n', start) - 1);
    final end = source.indexOf('\n$indent}', start);
    if (end == -1) {
      throw StateError('no closing brace found for `$signature`');
    }
    return source.substring(start, end);
  }

  group('the resume point is written while the episode plays', () {
    final history = read(
      'lib/features/detail/presentation/pages/player_page.history.dart',
    );

    test('the save tick repeats', () {
      final body = bodyOf(history, 'void _scheduleHistorySave()');
      expect(
        body,
        contains('Timer.periodic'),
        reason:
            'a one-shot timer fires once, at five seconds, below the '
            'ten-second floor in _saveHistory — so it writes nothing and '
            'nothing arms it again. The position then only reaches storage if '
            'the player is closed politely.',
      );
    });

    test('the floor is the shared rule, not a number spelled out here', () {
      final body = bodyOf(history, 'void _saveHistory()');
      expect(body, contains('WatchProgress.countsAsAViewing'));
      expect(
        body,
        isNot(contains('inSeconds < 10')),
        reason:
            'the ten-second floor is a domain rule with its own tests; a '
            'second copy here is the one that drifts.',
      );
    });

    test('stopping playback saves before it cancels the tick', () {
      final body = bodyOf(history, 'void _stopHistorySaves()');
      final save = body.indexOf('_saveHistory()');
      expect(save, isNot(-1), reason: 'a pause must still write the position');
      // Cancel-then-save, not save-then-forget: the ordering is what makes a
      // pause the same as a tick rather than a lost five seconds.
      expect(body, contains('_historyTimer?.cancel()'));
    });
  });

  group('backgrounding is treated as the last chance it is', () {
    final page = read(
      'lib/features/detail/presentation/pages/player_page.dart',
    );
    final lifecycle = bodyOf(
      page,
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );

    test('a detached engine flushes', () {
      // dispose() is not guaranteed here, so nothing else would.
      final detached = lifecycle.substring(
        lifecycle.indexOf('AppLifecycleState.detached'),
      );
      expect(detached, contains('_saveHistory()'));
    });

    test('so does going to the background', () {
      // On Android `paused` is the last callback before the process may be
      // killed. It is also the only flush that covers PiP and the desktop,
      // where playback is deliberately NOT paused and so the pause-driven save
      // never runs.
      final backgrounded = lifecycle.substring(
        lifecycle.indexOf('AppLifecycleState.inactive'),
        lifecycle.indexOf('AppLifecycleState.resumed'),
      );
      expect(backgrounded, contains('_saveHistory()'));
    });
  });

  group('a retry comes back to where the viewer was', () {
    final media = read(
      'lib/features/detail/presentation/pages/player_page.media.dart',
    );

    /// Both retries dispose the controller and rebuild it. The position has to
    /// be read BEFORE the teardown — afterwards `_controller` is null and the
    /// reload starts from zero, which is the defect.
    /// Every argument list in `body` belonging to a call to `name`.
    ///
    /// Counts brackets rather than looking for the next `);`, so a call spread
    /// over six lines with a `?? const []` in it is still one argument list.
    List<String> argsOf(String body, String name) {
      final calls = <String>[];
      var from = 0;
      while (true) {
        final at = body.indexOf('$name(', from);
        if (at == -1) return calls;
        var depth = 0;
        var i = at + name.length;
        for (; i < body.length; i++) {
          if (body[i] == '(') depth++;
          if (body[i] == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        calls.add(body.substring(at, i + 1));
        from = i + 1;
      }
    }

    void gate(String signature) {
      final body = bodyOf(media, signature);
      final capture = body.indexOf('_controller?.value.position');
      final teardown = body.indexOf('_disposeController');
      expect(
        capture,
        isNot(-1),
        reason: '$signature never reads the position it is meant to keep',
      );
      if (teardown != -1) {
        expect(
          capture,
          lessThan(teardown),
          reason:
              '$signature reads the position after disposing the controller, '
              'where it is always zero',
        );
      }

      // Each reload separately, not the body as a whole. Both retries have
      // more than one branch — a series, a film, a fallback — and checking
      // that `resumeAt` appears *somewhere* lets one branch lose it while the
      // others keep the test green. Which is exactly what happened when this
      // gate was first written against the whole body.
      final reloads = [
        ...argsOf(body, '_loadEpisode'),
        ...argsOf(body, '_initializeWith'),
      ];
      expect(
        reloads,
        isNotEmpty,
        reason: '$signature no longer reloads anything',
      );
      for (final call in reloads) {
        expect(
          call,
          contains('resumeAt'),
          reason:
              'this reload inside $signature restarts from zero:\n$call',
        );
      }

      // A live channel has no position worth returning to, and resuming one an
      // hour behind the edge would stall on a window the CDN has dropped.
      expect(body, contains('_isLive'));
    }

    test('the automatic retry after a network drop', () {
      gate('Future<void> _autoRetry()');
    });

    test('and the retry the viewer presses', () {
      gate('Future<void> _retry()');
    });
  });
}
