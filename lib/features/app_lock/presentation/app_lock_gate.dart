import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';

/// Whether the app lock currently covers the app.
///
/// The lock used to be a route the splash screen sent people to, and nothing
/// else: a deep link or a push tap on a cold start navigated past it, and an
/// app left in the background for a day came back open. This owns the answer
/// instead, and [AppLockOverlay] draws the lock over the router whenever it
/// says so — so every way into the app lands under it.
class AppLockGate extends ChangeNotifier with WidgetsBindingObserver {
  AppLockGate(this._repo, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now,
      // Locked from the start when a PIN is set. DI builds this after the
      // settings box is open, so the flag is already readable here.
      _locked = _repo.isEnabled;

  final AppLockRepository _repo;
  final DateTime Function() _now;

  /// How long the app may sit in the background before it locks again. Short
  /// trips — the share sheet, a permission prompt, a file picker, the camera
  /// for a QR code, picture-in-picture glances — must not each cost a PIN.
  static const Duration grace = Duration(seconds: 30);

  bool _locked;
  bool _observing = false;
  DateTime? _backgroundedAt;

  /// Held down while the splash is on screen.
  ///
  /// The lock exists to cover CONTENT. The splash has none: it is the app's
  /// own mark on a black field, which is the same thing the launcher icon
  /// already shows to anybody holding the phone. Covering it bought no
  /// security and cost the one animation the app gets to introduce itself
  /// with — on a locked device the whole thing played behind the PIN pad and
  /// nobody ever saw it.
  ///
  /// Nothing else may use this. It is not a way to postpone the lock; it is a
  /// statement that what is on screen is not worth locking.
  bool _splashHold = false;
  Timer? _splashDeadline;

  /// True while the lock screen must cover the app. Turning the lock off in
  /// settings clears it at once; turning it on does not lock the session the
  /// user is in — they have just typed the PIN.
  bool get isLocked => _locked && _repo.isEnabled && !_splashHold;

  /// Lets the splash play before the PIN pad covers it.
  ///
  /// Bounded three ways, because an unlocked app is not something to leave to
  /// a callback firing: it expires on its own after [_splashGrace] whatever
  /// happens, it is dropped the moment the app goes to the background, and the
  /// only caller releases it when the splash route is disposed. A crash
  /// mid-animation therefore lands on a locked app, not an open one.
  void holdForSplash() {
    if (_splashHold) return;
    _splashHold = true;
    _splashDeadline?.cancel();
    _splashDeadline = Timer(_splashGrace, releaseSplashHold);
    notifyListeners();
  }

  void releaseSplashHold() {
    _splashDeadline?.cancel();
    _splashDeadline = null;
    if (!_splashHold) return;
    _splashHold = false;
    notifyListeners();
  }

  /// Comfortably past the splash's own length, and nowhere near long enough
  /// to be useful to somebody holding a phone they should not have.
  static const Duration _splashGrace = Duration(seconds: 4);

  /// Starts watching the app's lifecycle. Idempotent. Called before the first
  /// frame so this observer is registered ahead of the router's back-button
  /// handler and can swallow Back while locked (see [didPopRoute]).
  void start() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  void lock() {
    if (_locked || !_repo.isEnabled) return;
    _locked = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Whatever the splash was doing, it is not on screen now.
        releaseSplashHold();
        _backgroundedAt ??= _now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && _now().difference(since) >= grace) lock();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Back while locked would otherwise pop the pages hidden under the lock.
  @override
  Future<bool> didPopRoute() async => isLocked;

  @override
  void dispose() {
    _splashDeadline?.cancel();
    super.dispose();
  }
}
