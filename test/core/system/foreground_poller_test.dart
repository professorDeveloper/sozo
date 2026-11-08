import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/system/foreground_poller.dart';

void main() {
  test('ticks every period while in the foreground', () {
    fakeAsync((async) {
      var ticks = 0;
      final poller = ForegroundPoller(
        period: const Duration(seconds: 60),
        onTick: () => ticks++,
      )..start();
      async.elapse(const Duration(seconds: 185));
      expect(ticks, 3);
      poller.dispose();
    });
  });

  test('stops in the background and resumes with one tick', () {
    fakeAsync((async) {
      var ticks = 0;
      final poller = ForegroundPoller(
        period: const Duration(seconds: 60),
        onTick: () => ticks++,
      )..start();

      poller.handleLifecycle(AppLifecycleState.inactive);
      expect(poller.isRunning, isTrue, reason: 'a shade pull is not leaving');

      poller.handleLifecycle(AppLifecycleState.hidden);
      poller.handleLifecycle(AppLifecycleState.paused);
      expect(poller.isRunning, isFalse);
      async.elapse(const Duration(minutes: 10));
      expect(ticks, 0);

      poller.handleLifecycle(AppLifecycleState.resumed);
      expect(ticks, 1, reason: 'catches up at once on return');
      expect(poller.isRunning, isTrue);
      async.elapse(const Duration(seconds: 60));
      expect(ticks, 2);

      poller.handleLifecycle(AppLifecycleState.resumed);
      expect(ticks, 2, reason: 'a resume while running does not double up');
      poller.dispose();
      expect(poller.isRunning, isFalse);
    });
  });
}
