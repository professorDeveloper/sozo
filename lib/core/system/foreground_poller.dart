import 'dart:async';

import 'package:flutter/widgets.dart';

/// A periodic task that runs only while the app is in the foreground.
///
/// Feed it lifecycle changes: it stops on `paused`/`hidden`/`detached`, and on
/// `resumed` ticks once and restarts the period.
class ForegroundPoller {
  ForegroundPoller({required this.period, required this.onTick});

  final Duration period;
  final VoidCallback onTick;
  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(period, (_) => onTick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (isRunning) return;
        onTick();
        start();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        stop();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() => stop();
}
