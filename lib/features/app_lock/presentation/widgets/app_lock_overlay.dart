import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/app_lock/presentation/app_lock_gate.dart';
import 'package:soplay/features/app_lock/presentation/pages/pin_verify_page.dart';

/// Draws the PIN screen over the whole app while [AppLockGate] is locked.
///
/// The app underneath keeps its state and its navigation stack, but cannot be
/// focused (a TV remote or a keyboard would otherwise drive the hidden pages)
/// and is left out of the accessibility tree (a screen reader would otherwise
/// read them out). The lock screen has a navigator of its own so its dialogs
/// work while the app's one is hidden.
class AppLockOverlay extends StatelessWidget {
  const AppLockOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gate = getIt<AppLockGate>();
    final router = AppRouter.router.routerDelegate;
    // Decided by which route is on screen, and not by a flag the splash raises
    // and lowers. That version raised it from `initState`, which runs during a
    // build, so the notification that should have uncovered the splash threw
    // "setState() called during build" instead and the PIN pad stayed up. It
    // could not lower it safely either: `dispose` runs while the tree is
    // locked. Reading the route has neither problem, and it cannot leak — the
    // frame the app leaves the splash, for whatever reason including a deep
    // link, is the frame this covers it again, with no timer to wait out.
    return ListenableBuilder(
      listenable: Listenable.merge([gate, router]),
      builder: (context, _) {
        final locked = lockCovers(
          locked: gate.isLocked,
          path: router.currentConfiguration.uri.path,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: locked,
              child: ExcludeSemantics(excluding: locked, child: child),
            ),
            if (locked)
              Positioned.fill(
                child: FocusScope(
                  autofocus: true,
                  child: Navigator(
                    onGenerateRoute: (_) => PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) =>
                          PinVerifyPage(onUnlocked: gate.unlock),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Whether the PIN pad is drawn over the route at [path].
///
/// Everywhere, while locked — except the splash. The lock exists to cover
/// CONTENT, and the splash has none: it is the app's own mark on a black
/// field, which is what the launcher icon already shows to anybody holding the
/// phone. Covered, the one animation the app gets to introduce itself with
/// played behind the PIN pad on every locked device, and nobody who uses the
/// lock ever saw it.
///
/// Exempting a route does not unlock anything. [AppLockGate] stays locked the
/// whole time, so the next route — whatever it is and however it was reached —
/// is covered on its first frame.
bool lockCovers({required bool locked, required String path}) =>
    locked && path != '/splash';
