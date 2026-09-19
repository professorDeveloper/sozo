import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
// Where the displays actually SIT. `dart:ui` enumerates displays but reports
// only their sizes, and a saved window position can only be judged against
// origins. window_manager already ships this package and uses it for its own
// `center()`, so the plugin is registered on every desktop platform the app
// builds for.
//
// Named import: the package's `Display` and `dart:ui`'s are different types
// with the same name, and only the retriever itself is wanted here.
// ignore: depend_on_referenced_packages
import 'package:screen_retriever/screen_retriever.dart' show screenRetriever;
import 'package:window_manager/window_manager.dart';

import '../constants/app_constants.dart';
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

  /// Where the window was when the app last closed, as a JSON blob in the
  /// settings box — the same box and the same direct-`Hive.box` access the
  /// title-bar preference above already uses.
  ///
  /// One key rather than four so a half-written geometry is impossible: either
  /// the whole rect is there and parses, or the window opens at its default.
  static const String _geometryKey = 'desktop_window_geometry';

  /// Minimum the window may be restored to. Kept in step with the
  /// `setMinimumSize` call in `main()` — restoring smaller than the OS will
  /// allow leaves the saved rect and the real window permanently out of sync.
  static const Size minimumSize = Size(800, 560);

  static _DesktopWindowListener? _listener;

  /// Put the window back where the user left it. Call it before the first
  /// frame: on Windows the runner shows the window from the first frame's
  /// callback, so a rect applied here is the size it is first painted at.
  /// macOS and Linux show their window before Dart `main()` runs, so there the
  /// restore is visible as a single jump rather than being free.
  ///
  /// Anything unreadable — a key from an older build, a truncated write — is
  /// treated as "no preference" and leaves the default geometry alone.
  static Future<void> restoreGeometry() async {
    final raw = Hive.box(AppConstants.settingsBox).get(_geometryKey);
    if (raw is! String || raw.isEmpty) return;
    Map<String, dynamic> saved;
    try {
      saved = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final displays = await _displayRects();
    final size = _clampToDisplays(
      Size(
        (saved['w'] as num?)?.toDouble() ?? 0,
        (saved['h'] as num?)?.toDouble() ?? 0,
      ),
      displays,
    );
    if (size == null) return;
    try {
      // A rect saved against a monitor arrangement that no longer exists is how
      // a window ends up somewhere the user cannot reach it — the laptop is
      // undocked and the position it remembers is 2000px to the right of the
      // only screen there is.
      //
      // Two guards, because neither is enough alone. The fingerprint is the
      // cheap one: when the arrangement is not the one the rect was written
      // under, the exact position is not worth arguing about and the window is
      // centred instead. It is only a hint, though, and it has to be readable
      // at both ends to be even that — an empty fingerprint means no display
      // was reported, which is a question mark rather than a change, and on a
      // question mark the saved position is restored as it always was.
      //
      // [_clampToVisible] is the guard that actually holds. Whatever position
      // survives the hint — including every case the hint cannot see, such as
      // a monitor that kept its resolution but moved — the rect is still
      // dragged back until a grabbable strip of its top edge is on a display
      // that exists right now.
      final here = _fingerprint(displays);
      final there = saved['displays'];
      final moved =
          here.isNotEmpty &&
          there is String &&
          there.isNotEmpty &&
          there != here;
      if (moved) {
        await windowManager.setSize(size);
        await windowManager.center();
      } else {
        await windowManager.setBounds(
          _clampToVisible(
            Rect.fromLTWH(
              (saved['x'] as num?)?.toDouble() ?? 0,
              (saved['y'] as num?)?.toDouble() ?? 0,
              size.width,
              size.height,
            ),
            displays,
          ),
        );
      }
      // Applied after the rect, not instead of it: unmaximising then has the
      // pre-maximise size to fall back to, which is what `_saveGeometry` is
      // careful to keep hold of.
      if (saved['maximized'] == true) await windowManager.maximize();
    } catch (_) {}
  }

  /// Start watching the window so its geometry survives the next launch, and so
  /// [fullscreen] stays true to the OS.
  ///
  /// Idempotent — a second call is ignored rather than adding a second
  /// listener that would double every save.
  static void trackWindow() {
    if (_listener != null) return;
    final listener = _DesktopWindowListener();
    _listener = listener;
    windowManager.addListener(listener);
    // Takes ownership of the close. Without this the native side emits "close"
    // and destroys the window in the same breath, so the listener's final
    // geometry write — an async Hive put — never gets to finish and the last
    // resize before quitting is simply lost. With it the native handler returns
    // "not yet" instead, and [_DesktopWindowListener.onWindowClose] is then
    // responsible for calling `destroy()` once the write is done.
    unawaited(_preventClose());
    // A baseline, so the very first thing the user does can be to maximise.
    // Maximising saves the flag and keeps whatever rect was already on record
    // as the size to unmaximise back to — and on a first run there would not be
    // one, so the flag would have been dropped and the window would have
    // reopened in a box the user never asked for.
    unawaited(_saveGeometry());
  }

  /// Swallowed rather than surfaced: a plugin that will not intercept the close
  /// leaves the window closing the way it always did, which costs one geometry
  /// write. Refusing to start would cost the user their app.
  static Future<void> _preventClose() async {
    try {
      await windowManager.setPreventClose(true);
    } catch (_) {}
  }

  /// Read the live window back and write it down.
  ///
  /// Deliberately does nothing to the rect while the window is maximised or
  /// fullscreen: `getBounds` then reports the whole screen, and saving that is
  /// what makes an app reopen maximised-sized-but-not-maximised, with no way
  /// back to the size the user actually chose. The flag still gets saved, so
  /// the window reopens maximised and unmaximises to the older, real rect.
  ///
  /// An unchanged geometry is read and then dropped rather than written again.
  /// That is what lets the listener call this from cheap, frequent events —
  /// focus loss most of all — without turning every alt-tab into a disk write.
  static Future<void> _saveGeometry() async {
    try {
      final maximized =
          await windowManager.isMaximized() ||
          await windowManager.isFullScreen();
      final box = Hive.box(AppConstants.settingsBox);
      Map<String, dynamic> entry;
      if (maximized) {
        final previous = box.get(_geometryKey);
        if (previous is! String || previous.isEmpty) return;
        entry = jsonDecode(previous) as Map<String, dynamic>;
      } else {
        final bounds = await windowManager.getBounds();
        if (bounds.width <= 0 || bounds.height <= 0) return;
        entry = <String, dynamic>{
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
          'displays': _fingerprint(await _displayRects()),
        };
      }
      entry['maximized'] = maximized;
      final encoded = jsonEncode(entry);
      if (box.get(_geometryKey) == encoded) return;
      await box.put(_geometryKey, encoded);
    } catch (_) {}
  }

  /// A cheap description of the monitor arrangement, sorted so the order the OS
  /// happens to enumerate the displays in does not count as a change.
  ///
  /// Origins are in it, not just sizes. Two identical monitors swapped
  /// left-to-right in system settings are the same set of sizes but not the
  /// same arrangement, and the rect saved on the right-hand one now names the
  /// left-hand one.
  ///
  /// Adding origins changed the string, so the one fingerprint already on disk
  /// from an older build never matches and the first launch after updating
  /// opens centred at the saved size. That is the same thing the app does for
  /// any unrecognised arrangement, it happens once, and it is cheaper than
  /// carrying a second format forward to avoid it.
  static String _fingerprint(List<Rect> displays) {
    final parts = <String>[
      for (final display in displays)
        '${display.left.round()},${display.top.round()}'
            ':${display.width.round()}x${display.height.round()}',
    ]..sort();
    return parts.join('|');
  }

  /// Every attached display as a rect in the coordinate space `setBounds`
  /// speaks, so a saved rect and a display can be compared without a conversion
  /// at the call site. window_manager positions its own `center()` off exactly
  /// these numbers, which is what makes the two spaces the same one.
  ///
  /// The *visible* rect — the work area — rather than the whole panel, because
  /// the Windows taskbar and the macOS menu bar are not places a title bar can
  /// be grabbed: a strip of window "on screen" underneath one is not on screen
  /// in any useful sense.
  ///
  /// Empty when the platform will not say, which every caller reads as "do not
  /// second-guess the saved rect".
  ///
  /// Bounded, because `restoreGeometry` runs before `runApp`: a plugin that
  /// never answers would otherwise hold the first frame rather than cost the
  /// app a clamp it can live without.
  static Future<List<Rect>> _displayRects() async {
    try {
      final displays = await screenRetriever.getAllDisplays().timeout(
        const Duration(seconds: 2),
      );
      final rects = <Rect>[];
      for (final display in displays) {
        final size = display.visibleSize ?? display.size;
        if (size.width <= 0 || size.height <= 0) continue;
        rects.add((display.visiblePosition ?? Offset.zero) & size);
      }
      return rects;
    } catch (_) {
      return const <Rect>[];
    }
  }

  /// The least of a window that still counts as reachable: enough title bar to
  /// get a cursor onto it and drag the rest back. The height covers the app's
  /// own strip ([WindowTitleBar.height]) and the taller native caption the
  /// `use_native_title_bar` setting can put there instead.
  static const Size _grabStrip = Size(120, 40);

  /// A saved rect dragged back until it is reachable on a display that exists
  /// now — or returned untouched when the platform would not say which displays
  /// those are.
  ///
  /// "Reachable" is deliberately weak: only a [_grabStrip] of the window's top
  /// edge has to land inside one display's work area. A window is allowed to
  /// hang off an edge, because the user is allowed to put it there. What it may
  /// not do is come back with its title bar above the top of the screen or out
  /// on a monitor that has since been unplugged, because then there is nothing
  /// left to drag.
  ///
  /// It is judged against whichever display it already overlaps most, so a
  /// window straddling two monitors stays where the user left it; one that
  /// overlaps nothing at all falls back to the first display, which is as good
  /// a guess as any once its own monitor is gone.
  static Rect _clampToVisible(Rect rect, List<Rect> displays) {
    if (displays.isEmpty) return rect;
    var host = displays.first;
    var best = -1.0;
    for (final display in displays) {
      final overlap = display.intersect(rect);
      final area = overlap.width <= 0 || overlap.height <= 0
          ? 0.0
          : overlap.width * overlap.height;
      if (area > best) {
        best = area;
        host = display;
      }
    }
    final grabWidth = math.min(_grabStrip.width, rect.width);
    final grabHeight = math.min(_grabStrip.height, rect.height);
    return Rect.fromLTWH(
      _within(
        rect.left,
        host.left - rect.width + grabWidth,
        host.right - grabWidth,
      ),
      // The top is clamped to the display's own top rather than being allowed
      // to hang over it like the sides are: a title bar pushed above the screen
      // is the one overhang a mouse cannot undo.
      _within(rect.top, host.top, host.bottom - grabHeight),
      rect.width,
      rect.height,
    );
  }

  /// `clamp` that tolerates its bounds arriving the wrong way round — a display
  /// smaller than the window inverts them, and that must not throw on somebody
  /// else's monitor.
  static double _within(double value, double low, double high) =>
      low <= high ? value.clamp(low, high) : low;

  /// A saved size brought back inside what the OS will actually honour, or null
  /// if there is nothing usable to restore.
  ///
  /// The upper bound is the largest display rather than the current one: a
  /// window legitimately restored onto a 4K monitor must not be shrunk to the
  /// laptop panel it happens to be enumerated after.
  static Size? _clampToDisplays(Size size, List<Rect> displays) {
    if (size.width <= 0 || size.height <= 0) return null;
    var maxWidth = double.infinity;
    var maxHeight = double.infinity;
    if (displays.isNotEmpty) {
      maxWidth = displays.map((d) => d.width).reduce(math.max);
      maxHeight = displays.map((d) => d.height).reduce(math.max);
    }
    return Size(
      size.width.clamp(minimumSize.width, math.max(minimumSize.width, maxWidth)),
      size.height.clamp(
        minimumSize.height,
        math.max(minimumSize.height, maxHeight),
      ),
    );
  }
}

/// Keeps the app's idea of the window in step with the OS's.
///
/// Two jobs, both of which only the window manager can report.
///
/// On macOS and Linux, fullscreen can be entered from outside the app entirely
/// — the green button, a window-manager keybinding — and the plugin hears about
/// it natively (`windowDidEnterFullScreen`, the GDK window-state event), so
/// [DesktopWindow.fullscreen] follows the OS and the custom title bar stops
/// holding a strip across the top of an otherwise borderless video.
///
/// Windows does NOT work that way, and it is worth saying plainly because the
/// custom title bar is a Windows feature first. There, window_manager's
/// `IsFullScreen()` reports a flag its own `SetFullScreen()` writes, and it
/// emits enter/leave-full-screen only while that flag is already set — so on
/// Windows these two callbacks only ever echo a fullscreen this app asked for
/// through [DesktopWindow.setFullscreen]. In practice nothing is missing,
/// because Windows has no OS gesture that puts an arbitrary window into real
/// fullscreen; maximising is not it, and the player's own F key goes through
/// `setFullscreen`. It is deliberately not papered over by treating "the window
/// happens to cover a display" as fullscreen: a maximised window on a monitor
/// with an auto-hidden taskbar measures the same, and hiding the strip there
/// would take the only close button a frameless window has with it.
///
/// Geometry, meanwhile, has no "the user is finished" event other than these,
/// so this is the only place that knows what to write down — and on Windows
/// they do not cover everything. `resized` and `moved` are emitted from
/// WM_EXITSIZEMOVE, and only when WM_SIZING / WM_MOVING set the flag that gates
/// them, so they mean "a mouse drag of the frame ended". Aero snap and the
/// Win+Arrow keys resize the window without either message and are therefore
/// silent; so is a snap back out of a snapped position. ([onWindowMaximize] is
/// not a substitute — a snapped window is SIZE_RESTORED, not SIZE_MAXIMIZED.)
///
/// Two cheaper events close most of that hole rather than polling for it.
/// [onWindowBlur] fires from WM_NCACTIVATE whenever the window stops being the
/// active one, which is what happens the moment the user goes to whatever they
/// snapped Sozo beside; and [onWindowClose] reads the live bounds anyway, so a
/// snap followed by quitting normally is recorded correctly regardless. What is
/// genuinely lost is a snapped window in a process that dies without a
/// WM_CLOSE — a crash, a kill, a shutdown that does not wait — and that is a
/// stale saved rect, not a wrong one.
class _DesktopWindowListener with WindowListener {
  /// `onWindowResized` is the end of a drag on Windows and macOS, but Linux
  /// window managers deliver it throughout one. The wait is long enough to
  /// collapse that into a single write and short enough that quitting straight
  /// after a resize still records it.
  static const Duration _debounce = Duration(milliseconds: 400);

  Timer? _pending;

  void _scheduleSave() {
    _pending?.cancel();
    _pending = Timer(_debounce, () {
      _pending = null;
      unawaited(DesktopWindow._saveGeometry());
    });
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  /// Not "the user is finished" so much as "the user has gone elsewhere", which
  /// is the closest thing Windows offers for the geometry changes it reports no
  /// other way (see the class doc). It costs a debounced read of bounds the app
  /// already knows how to read, and [DesktopWindow._saveGeometry] drops the
  /// write when nothing actually changed, so alt-tabbing is free.
  @override
  void onWindowBlur() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();

  /// How long the geometry write may hold the app open.
  ///
  /// It is a Hive put and a couple of method-channel round trips, so it is
  /// milliseconds in practice. The bound is here for the day it is not: a
  /// window that will not close is a far worse bug than a window whose last
  /// position was not saved.
  static const Duration _closeFlush = Duration(seconds: 2);

  @override
  void onWindowClose() {
    // The debounce is exactly the window in which a save can be lost, so a
    // close collapses it and writes immediately instead of waiting it out.
    //
    // That write can only finish because `setPreventClose(true)` ran at
    // startup: the native handlers (WM_CLOSE, `windowShouldClose`, GTK's
    // delete-event) emit this event and then go on to destroy the window unless
    // that flag is set, which is exactly long enough for a synchronous
    // callback and not nearly long enough for an async one. Holding the close
    // means this method now owns it, so every path below ends in `destroy()` —
    // which bypasses the same handler rather than re-entering it.
    _pending?.cancel();
    _pending = null;
    unawaited(_flushAndClose());
  }

  Future<void> _flushAndClose() async {
    try {
      await DesktopWindow._saveGeometry().timeout(_closeFlush);
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {}
  }

  @override
  void onWindowEnterFullScreen() {
    DesktopWindow.fullscreen.value = true;
    _scheduleSave();
  }

  @override
  void onWindowLeaveFullScreen() {
    DesktopWindow.fullscreen.value = false;
    _scheduleSave();
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
        _WinButton(icon: Icons.remove, onTap: () => windowManager.minimize()),
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
