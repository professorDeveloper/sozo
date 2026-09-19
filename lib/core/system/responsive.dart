import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv_focusable.dart';

import 'platform_utils.dart';

export 'platform_utils.dart';

/// How much horizontal room the *window* has, which is a different question
/// from [isDesktopPlatform].
///
/// [isDesktopPlatform] answers "is this Windows/Linux/macOS". That is the right
/// predicate for input (hover, right-click, keyboard), for window and plugin
/// concerns, and for anything that depends on the host OS. It is the wrong one
/// for layout, and the app has been using it for layout everywhere: a Sozo
/// window dragged to half a laptop screen still renders a 300px nav rail beside
/// a 900px detail column and overflows, while an iPad — which has more width
/// than most desktop windows ever get — is handed the phone layout because iOS
/// is not a desktop OS.
///
/// So: ask [SozoWidth] how wide the window is; ask [isDesktopPlatform] what the
/// machine can do. Reach for this one whenever the answer would change if the
/// user resized the window, because that is exactly the case the platform
/// boolean cannot see.
///
/// The bands are the usual three, and the numbers are the ones the app's own
/// layouts already imply: below [mediumMin] only one column of content fits
/// (every phone, and a narrow window), [expandedMin] is where a list and a
/// detail pane stop fighting each other, and [twoPaneMin] is the app's real
/// two-pane floor — a 300px rail plus the 900px detail column it sits next to.
enum SozoWidth {
  compact,
  medium,
  expanded;

  static const double mediumMin = 600;
  static const double expandedMin = 900;

  /// The nav rail (300) plus the detail column (900) it has to sit beside.
  /// Below this a two-pane layout is not tight, it is broken.
  static const double twoPaneMin = 1200;

  /// Depends on the size aspect of the [MediaQuery] only, so a rebuild costs
  /// nothing until the window actually changes width.
  static SozoWidth of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static SozoWidth fromWidth(double width) {
    if (width >= expandedMin) return SozoWidth.expanded;
    if (width >= mediumMin) return SozoWidth.medium;
    return SozoWidth.compact;
  }

  bool get isCompact => this == SozoWidth.compact;

  /// True from tablet portrait upwards. The common gate: "is there room for
  /// more than one column of content".
  bool get isAtLeastMedium => index >= SozoWidth.medium.index;

  bool get isExpanded => this == SozoWidth.expanded;

  static bool fitsTwoPane(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= twoPaneMin;
}

/// Pass [context] and the choice follows the window; omit it and it falls back
/// to the OS, which is what every existing call site does. The width is the
/// honest axis here — a max-extent grid is right because there is room for more
/// tiles, not because the host happens to run macOS — so new callers should
/// pass it.
SliverGridDelegate responsiveGridDelegate({
  required int mobileCrossAxisCount,
  required double childAspectRatio,
  double crossAxisSpacing = 8,
  double mainAxisSpacing = 8,
  double desktopMaxCrossAxisExtent = 160,
  BuildContext? context,
}) {
  final wide = context != null
      ? SozoWidth.of(context).isAtLeastMedium
      : isDesktopPlatform;
  if (wide) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: desktopMaxCrossAxisExtent,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: mobileCrossAxisCount,
    childAspectRatio: childAspectRatio,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
  );
}

/// Stops a column of text from running the full width of a wide window.
///
/// The clamp is the [ConstrainedBox] alone, with no platform gate in front of
/// it: it is a no-op whenever the window is narrower than [maxWidth] anyway, so
/// the only thing the old [isDesktopPlatform] check ever did was withhold it
/// from the one device that most needs it — a tablet in landscape.
///
/// Nothing short-circuits on the measured width either, because [Align] does a
/// second thing besides centring: it passes *loose* constraints down. Returning
/// the bare child below the threshold would therefore hand a content-sized
/// child tight constraints on a narrow window and loose ones on a wide one, so
/// the child would change shape as the window crossed [maxWidth]. One
/// RenderPositionedBox costs less than that discontinuity.
class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 1040});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Test-only override for [HoverTap]'s desktop/phone split.
///
/// `flutter test` runs on the host, so [isDesktopPlatform] is true inside every
/// widget test on a developer machine and the phone branch — the one almost all
/// 39 call sites actually ship — is unreachable otherwise. Production code must
/// leave this null.
@visibleForTesting
bool? debugHoverTapIsDesktopOverride;

/// The app's universal tappable: posters, history rows, genre tiles, banners.
///
/// One widget, three input models, and the point of it is that a caller writes
/// `onTap` once and gets whichever affordance the device actually has — a
/// pointer that hovers, a remote that focuses, or a finger that presses.
class HoverTap extends StatefulWidget {
  const HoverTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.behavior = HitTestBehavior.opaque,
    this.scale = 1.04,
    this.cursor = SystemMouseCursors.click,
    this.borderRadius = 10,
    this.ringColor,
    this.ringWidth = 2,
    this.pressedScale = 0.97,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final VoidCallback? onSecondaryTap;
  final HitTestBehavior behavior;
  final double scale;
  final MouseCursor cursor;

  /// Radius of the keyboard focus ring; match it to whatever is being wrapped —
  /// 10 for artwork, 12 for surface cards — so the ring traces the content
  /// instead of boxing it. Same contract as [TvFocusable.borderRadius].
  final double borderRadius;

  /// Defaults to [AppColors.textPrimary], as on TV: the strongest contrast
  /// available against the app background without inventing a colour.
  final Color? ringColor;
  final double ringWidth;

  /// How far the card dips while a finger is down. Deliberately small — a
  /// poster is a large surface and anything stronger reads as a layout jump.
  final double pressedScale;

  /// Opt-in, because 39 files use this widget and a poster rail that ticks on
  /// every tap is worse than one that stays quiet. Turn it on where the tap
  /// commits to something.
  final bool haptic;

  @override
  State<HoverTap> createState() => _HoverTapState();
}

class _HoverTapState extends State<HoverTap> {
  bool _hovering = false;
  bool _focused = false;
  bool _pressed = false;

  static const Duration _hoverDuration = Duration(milliseconds: 140);

  /// Shorter than the hover animation: a press has to land under the finger,
  /// not glide after it.
  static const Duration _pressDuration = Duration(milliseconds: 110);

  /// Enter only, deliberately — Space is NOT an activation key here.
  ///
  /// Key events bubble up from the focused node, so anything this widget
  /// reports as handled never reaches the ancestor shortcut handlers. Space is
  /// play/pause in the player (player_page.dart) and page-forward in the manga
  /// reader (reader_page.dart), and both of those live above posters wrapped in
  /// a [HoverTap]: the moment Tab landed on one, the most important key in a
  /// media app went dead. Enter is the unambiguous "activate the focused thing"
  /// key and collides with nothing.
  static bool _isActivationKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  void _handleTap() {
    if (widget.haptic && isMobilePlatform) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onTap == null) return KeyEventResult.ignored;
    if (!_isActivationKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _handleTap();
      return KeyEventResult.handled;
    }
    // Swallow auto-repeat so holding Enter cannot fire a burst of activations,
    // and so it never falls through to the scrollable underneath.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Android TV. Off desktop this widget resolves to a bare GestureDetector,
    // which CANNOT take focus — so on a television every card wrapped in a
    // HoverTap (posters, history rows, genre tiles, ...) was unreachable by the
    // D-pad: the remote could move around the nav rail but never into the
    // content. TvFocusable is the same tap handling plus a focus node, a ring
    // and scroll-into-view.
    //
    // Placed BEFORE the desktop branch and gated on isTvPlatform, which is
    // false on every phone, tablet and desktop — those keep the exact two paths
    // below.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: widget.onTap,
        onLongPressed: widget.onLongPress,
        behavior: widget.behavior,
        scale: widget.scale,
        borderRadius: widget.borderRadius,
        child: widget.child,
      );
    }

    final desktop = debugHoverTapIsDesktopOverride ?? isDesktopPlatform;
    final tappable = widget.onTap != null;

    // Reduce-motion kills the press animation outright rather than shortening
    // it: with no animation to drive there is no reason to hold press state or
    // to setState on every touch-down in a scrolling rail.
    final pressFeedback =
        !desktop && tappable && !MediaQuery.disableAnimationsOf(context);

    Widget content = widget.child;
    if (pressFeedback) {
      // Transform and opacity only — neither re-lays-out the subtree, which
      // matters because this runs per poster in a scrolling list. At rest both
      // are identity and RenderOpacity/RenderTransform skip their layers.
      content = AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: _pressDuration,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.7 : 1.0,
          duration: _pressDuration,
          curve: Curves.easeOut,
          child: content,
        ),
      );
    }

    Widget result = GestureDetector(
      onTap: tappable ? _handleTap : null,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onSecondaryTap,
      onTapDown: pressFeedback ? (_) => _setPressed(true) : null,
      onTapUp: pressFeedback ? (_) => _setPressed(false) : null,
      onTapCancel: pressFeedback ? () => _setPressed(false) : null,
      behavior: widget.behavior,
      // The button role and the tap action are declared once, above, instead of
      // letting the detector publish an unlabelled node of its own: a poster
      // that TalkBack reads as plain artwork gives no hint that it opens
      // anything.
      excludeFromSemantics: true,
      child: content,
    );

    if (tappable || widget.onLongPress != null) {
      result = Semantics(
        button: tappable,
        onTap: tappable ? _handleTap : null,
        onLongPress: widget.onLongPress,
        child: result,
      );
    }

    if (!desktop) return result;

    // Desktop keyboard reachability. Without this Focus the whole desktop UI is
    // a dead end for Tab — the same hole TvFocusable was written to close for
    // the D-pad — and the ring is that widget's, so a focused card looks the
    // same whichever input moved focus onto it.
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        canRequestFocus: tappable,
        skipTraversal: !tappable,
        onKeyEvent: _onKey,
        onFocusChange: (value) {
          if (mounted) setState(() => _focused = value);
        },
        child: AnimatedScale(
          scale: _hovering || _focused ? widget.scale : 1.0,
          duration: _hoverDuration,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: _hoverDuration,
            curve: Curves.easeOut,
            // foregroundDecoration paints the ring OVER the content, so an
            // unfocused card has no permanent inset gap and the grid does not
            // reflow as focus moves.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _focused
                    ? (widget.ringColor ?? AppColors.textPrimary)
                    : Colors.transparent,
                width: widget.ringWidth,
              ),
            ),
            child: result,
          ),
        ),
      ),
    );
  }
}

class PointerRegion extends StatelessWidget {
  const PointerRegion({
    super.key,
    required this.child,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return MouseRegion(cursor: cursor, child: child);
  }
}

class DesktopRefreshButton extends StatefulWidget {
  const DesktopRefreshButton({
    super.key,
    required this.onRefresh,
    this.color,
    this.tooltip,
    this.spinning = false,
  });

  final VoidCallback onRefresh;
  final Color? color;
  final String? tooltip;
  final bool spinning;

  @override
  State<DesktopRefreshButton> createState() => _DesktopRefreshButtonState();
}

class _DesktopRefreshButtonState extends State<DesktopRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant DesktopRefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.spinning && old.spinning) {
      _c.animateTo(1, duration: const Duration(milliseconds: 300)).then((_) {
        if (mounted) _c.reset();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    if (!widget.spinning) {
      _c.forward(from: 0);
    }
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return const SizedBox.shrink();
    return IconButton(
      tooltip: widget.tooltip ?? 'desktop.refresh'.tr(),
      onPressed: _tap,
      icon: RotationTransition(
        turns: _c.drive(CurveTween(curve: Curves.easeInOut)),
        child: Icon(Icons.refresh_rounded, color: widget.color),
      ),
    );
  }
}

/// Puts D-pad focus inside the sheet it wraps.
///
/// A modal route does not move focus into itself. On a phone that is invisible —
/// the next interaction is a tap. On a television it is the whole bug: the sheet
/// appears, focus is still on the control *behind* it, and the first few remote
/// presses either do nothing or drive the player underneath. Every "the settings
/// menu opens but the remote is dead" report traces back to this.
///
/// Runs after the first frame because the route's subtree — and therefore its
/// focusable descendants — does not exist yet during build. If a descendant
/// declared `autofocus` (the selected row, typically) it has already claimed
/// focus by then and this is a no-op, which is exactly the desired precedence:
/// land on the current value, not the first item.
class _TvFocusEntry extends StatefulWidget {
  const _TvFocusEntry({required this.child});

  final Widget child;

  @override
  State<_TvFocusEntry> createState() => _TvFocusEntryState();
}

class _TvFocusEntryState extends State<_TvFocusEntry> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'tvModal');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scope.focusedChild != null) return; // an autofocus already won
      // nextFocus() from the scope lands on its first focusable descendant.
      _scope.nextFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The traversal group keeps arrow keys inside the sheet, so the D-pad
    // cannot wander back onto the player controls behind the barrier.
    return FocusScope(
      node: _scope,
      child: FocusTraversalGroup(child: widget.child),
    );
  }
}

/// Is this a pointer-driven window with room to spare — a tablet or a desktop
/// window — rather than a phone that merely happens to be turned sideways?
///
/// The shortest side is the standard way of asking "is this a tablet", and it
/// is the only cheap question that a rotated phone fails: a phone is narrow in
/// one direction whichever way it is held (844x390 in landscape has a shortest
/// side of 390), while a tablet clears [SozoWidth.mediumMin] in both directions
/// in both orientations. Note that a shortest side at or above 600 already
/// implies a width at or above 600, so no separate width test is needed.
///
/// Desktop gets a second chance at the widest tier, for the window shape the
/// shortest side alone would misread — dragged wide but short, where a bottom
/// sheet would stretch into the same unusable strip a television gets. It is
/// gated on [SozoWidth.isExpanded] rather than being unconditional so that a
/// desktop window squeezed narrow still gets the sheet.
bool _prefersCentredDialog(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.shortestSide >= SozoWidth.mediumMin ||
      (isDesktopPlatform && SozoWidth.fromWidth(size.width).isExpanded);
}

/// A centred dialog where there is room for one, a bottom sheet where there is
/// not.
///
/// [desktopMaxWidth] keeps its name because every caller passes it, but the
/// choice itself is now the window's, not the OS's: a bottom sheet is a thumb
/// affordance pinned to the bottom edge, and on a 1400px-wide window that edge
/// is nowhere near the content. Conversely a Sozo window squeezed to 500px gets
/// the sheet, which is the right answer there and was previously unreachable on
/// a desktop OS.
///
/// The axis is deliberately NOT the window's width. Every modern phone is over
/// 600dp wide the instant it is rotated (iPhone SE 667, Pixel ~851), so a width
/// test flips all ~37 call sites — the audio-track, subtitle and quality
/// pickers and the sleep timer among them, which are used in landscape almost
/// exclusively — from a sheet the thumb can reach to a dialog in the middle of
/// the screen, on a rotation. See [_prefersCentredDialog] for what it asks
/// instead.
Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  bool showDragHandle = false,
  double desktopMaxWidth = 460,
  double tvMaxWidth = 620,
}) {
  // Television: a centred dialog, not a bottom sheet.
  //
  // A bottom sheet is a thumb affordance — it hugs the edge furthest from the
  // eye line on a 10-foot screen, and its width is set by the screen, so on a
  // TV it renders as a short, very wide strip. The same content as a centred
  // panel reads correctly and, more importantly, gives the remote one obvious
  // place to be.
  //
  // Stays on isTvPlatform rather than on width: a television is 1920 wide and
  // would pass any width test, but what makes the dialog right there is the
  // viewing distance and the remote, not the pixels.
  if (isTvPlatform) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => _TvFocusEntry(
        child: Dialog(
          backgroundColor: backgroundColor,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 48,
            vertical: 32,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tvMaxWidth,
              // Overscan-safe: TVs crop the outer few percent of the panel.
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
            ),
            child: SingleChildScrollView(child: builder(ctx)),
          ),
        ),
      ),
    );
  }
  if (_prefersCentredDialog(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: backgroundColor,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktopMaxWidth,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: SingleChildScrollView(child: builder(ctx)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    shape: shape,
    showDragHandle: showDragHandle,
    // Faster in, and with a curve that settles rather than slides.
    //
    // Material's default is 250ms in and 200ms out on a plain accelerate /
    // decelerate pair. On a player, where a sheet is opened to change one
    // thing and dismissed immediately, a quarter of a second of travel is the
    // difference between a control and a wait — and the app opens these from
    // a bar that is itself on a hide timer. 180ms in on an emphasised
    // decelerate reads as the sheet ARRIVING, which is what makes a short
    // animation feel fast rather than clipped, and 140ms out gets out of the
    // way of whatever the tap was for.
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      reverseDuration: const Duration(milliseconds: 140),
      reverseCurve: Curves.easeInCubic,
    ),
    builder: builder,
  );
}
