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
    // The route information provider, and not the router delegate.
    //
    // Both say where the app is, but the delegate learns it during the
    // Router's own first build — `setInitialRoutePath` runs from inside
    // `didChangeDependencies` — and this overlay is the Router's ANCESTOR, so
    // being told then is "setState() called during build" on the first frame
    // of every launch. The provider is built with the initial location before
    // anything is drawn, so its answer is right on frame one, and it only
    // changes when something navigates, which never happens inside a build.
    //
    // Deciding by route rather than by a flag the splash raises and lowers is
    // deliberate too. That version raised it from `initState` — also inside a
    // build — and lowered it from `dispose`, which runs while the tree is
    // locked; neither end worked. A route cannot leak: the frame the app
    // leaves the splash, however it leaves, is the frame this covers it again.
    final location = AppRouter.router.routeInformationProvider;
    return ListenableBuilder(
      listenable: Listenable.merge([gate, location]),
      builder: (context, _) {
        final locked = lockCovers(
          locked: gate.isLocked,
          path: location.value.uri.path,
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
