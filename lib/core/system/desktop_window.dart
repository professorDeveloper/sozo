import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';

/// Desktop window helpers: a custom (frameless) title bar and a shared
/// fullscreen state so the title bar can get out of the way for the player.
///
/// The native Windows caption is hidden in `main()` via
/// `TitleBarStyle.hidden`; [WindowTitleBar] draws the app-styled replacement.
class DesktopWindow {
  DesktopWindow._();

  /// True while the app is in OS fullscreen. The custom title bar hides itself
  /// so content fills the whole window (e.g. the video player).
  static final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);

  /// True while an immersive full-bleed screen (video player / manga reader) is
  /// active. The custom title bar hides so the content isn't pushed down by a
  /// strip; those screens surface the window buttons in their own top overlay.
  static final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);

  /// User preference: use the OS-native Windows title bar instead of the custom
  /// strip. When true the custom strip hides and the native caption is shown
  /// (so window controls are still available). Persisted via HiveService.
  static final ValueNotifier<bool> nativeTitleBar = ValueNotifier<bool>(false);

  /// Apply the native-vs-custom title-bar preference (also updates the notifier
  /// so the custom strip shows/hides).
  static Future<void> setNativeTitleBar(bool value) async {
    nativeTitleBar.value = value;
    try {
      await windowManager.setTitleBarStyle(
        value ? TitleBarStyle.normal : TitleBarStyle.hidden,
        windowButtonVisibility: value,
      );
    } catch (_) {}
  }

  static Future<void> setFullscreen(bool value) async {
    // Flip the notifier first so the custom title bar hides in the same frame,
    // then do the single native call. We deliberately avoid a second native
    // window-style change (setTitleBarStyle) here — that extra call was the
    // main source of the fullscreen jank; the caption stays hidden from the
    // startup TitleBarStyle.hidden.
    fullscreen.value = value;
    try {
      await windowManager.setFullScreen(value);
    } catch (_) {}
  }

  static Future<void> toggleFullscreen() async {
    bool current;
    try {
      current = await windowManager.isFullScreen();
    } catch (_) {
      current = fullscreen.value;
    }
    await setFullscreen(!current);
  }
}

/// Slim, app-styled replacement for the native Windows title bar. Draggable,
/// with minimise / maximise / close. Hides itself while in fullscreen.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        DesktopWindow.fullscreen,
        DesktopWindow.immersive,
        DesktopWindow.nativeTitleBar,
      ]),
      builder: (context, _) {
        if (DesktopWindow.fullscreen.value ||
            DesktopWindow.immersive.value ||
            DesktopWindow.nativeTitleBar.value) {
          return const SizedBox.shrink();
        }
        // Minimal, blended chrome: no logo/title (so it reads as "window
        // buttons in the corner", not a second title bar). Just a draggable
        // strip + the window controls, matching the app background.
        return Material(
          color: AppColors.background,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: GestureDetector(
                      // Double-click to maximise / restore (standard).
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const WindowButtons(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The minimise / maximise / close cluster. Reused by [WindowTitleBar] and by
/// the immersive player/reader overlays (which hide the title bar).
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    // macOS draws its own. The window is created with
    // `windowButtonVisibility: true` there, deliberately, because the traffic
    // lights are where a Mac user reaches — so adding a Windows-style cluster
    // in the opposite corner gave the window two sets of controls at once.
    if (Platform.isMacOS) return const SizedBox.shrink();
    return Row(
      children: [
        _WinButton(
          icon: Icons.remove,
          onTap: () => windowManager.minimize(),
        ),
        _WinButton(
          icon: Icons.crop_square_rounded,
          iconSize: 13,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WinButton(
          icon: Icons.close_rounded,
          hoverColor: const Color(0xFFE81123),
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.onTap,
    this.hoverColor,
    this.iconSize = 16,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? hoverColor;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final onClose = widget.hoverColor != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // Soft, animated hover fade (no hard colour flip) for a smoother feel.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          width: 46,
          height: WindowTitleBar.height,
          alignment: Alignment.center,
          color: _hover
              ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.06))
              : Colors.transparent,
          child: AnimatedScale(
            scale: _hover ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hover
                  ? (onClose ? Colors.white : AppColors.textPrimary)
                  : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }
}
