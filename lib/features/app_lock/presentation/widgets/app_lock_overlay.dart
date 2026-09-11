import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
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
    return ListenableBuilder(
      listenable: gate,
      builder: (context, _) {
        final locked = gate.isLocked;
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
