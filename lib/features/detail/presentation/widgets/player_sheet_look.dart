import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/glass/glass_sense.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Whether the player's sheets under it wear iOS 26's look: the native
/// controls' path on an iPhone. Everywhere else they stay as they were.
class PlayerSheetLook extends InheritedWidget {
  const PlayerSheetLook({super.key, required this.ios, required super.child});

  final bool ios;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerSheetLook>()?.ios ??
      false;

  @override
  bool updateShouldNotify(PlayerSheetLook old) => old.ios != ios;
}

/// iOS 26's numbers for a sheet and its grouped list, dark.
abstract final class IosSheet {
  static const double radius = 38;
  static const double groupRadius = 26;
  static const double gutter = 16;
  static const double rowHeight = 52;

  /// The sheet's material over the blurred video, and with nothing through
  /// it for Reduce Transparency.
  static const Color tint = Color(0xC71C1C1E);
  static const Color opaque = Color(0xFF1C1C1E);
  static const double blur = 30;

  /// A group's cell, a step up from the sheet.
  static const Color cell = Color(0x1FFFFFFF);
  static const Color separator = Color(0x2EFFFFFF);
  static const Color grabber = Color(0x5CFFFFFF);
  static const Color secondary = Color(0x99EBEBF5);
  static const Color tertiary = Color(0x4DEBEBF5);
  static const Color pressed = Color(0x1AFFFFFF);

  static const TextStyle title = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
  );
  static const TextStyle body = TextStyle(
    color: Colors.white,
    fontSize: 17,
    letterSpacing: -0.43,
  );
  static const TextStyle footnote = TextStyle(
    color: secondary,
    fontSize: 13,
    letterSpacing: -0.08,
  );
}

/// Opens one of the player's sheets: on the iOS path ([ios]) the phone's own
/// shape — a grabber, deep continuous corners, a frosted material over the
/// video — and otherwise exactly as [showAdaptiveModal] always drew it.
Future<T?> showPlayerSheet<T>({
  required BuildContext context,
  required bool ios,
  required WidgetBuilder builder,
  double desktopMaxWidth = 460,
}) {
  if (!ios) {
    return showAdaptiveModal<T>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      desktopMaxWidth: desktopMaxWidth,
      builder: builder,
    );
  }
  // An iPad keeps its centred dialog, with the rows dressed the same way.
  if (MediaQuery.sizeOf(context).shortestSide >= 600) {
    return showAdaptiveModal<T>(
      context: context,
      backgroundColor: IosSheet.opaque,
      isScrollControlled: true,
      desktopMaxWidth: desktopMaxWidth,
      builder: (ctx) => PlayerSheetLook(ios: true, child: builder(ctx)),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      reverseDuration: const Duration(milliseconds: 220),
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (ctx) =>
        PlayerSheetLook(ios: true, child: IosSheetFrame(child: builder(ctx))),
  );
}

/// The sheet itself: the grabber over [child], on the frosted material, its
/// top corners the phone's own.
class IosSheetFrame extends StatelessWidget {
  const IosSheetFrame({super.key, required this.child});

  final Widget child;

  static const ShapeBorder shape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(IosSheet.radius)),
  );

  @override
  Widget build(BuildContext context) {
    final opaque = GlassSense.reduceTransparencyOf(context);
    final body = Material(
      type: MaterialType.transparency,
      child: ListTileTheme(
        data: const ListTileThemeData(
          iconColor: Colors.white,
          textColor: Colors.white,
          minVerticalPadding: 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IosSheetGrabber(),
            Flexible(child: child),
          ],
        ),
      ),
    );
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: shape),
      child: opaque
          ? ColoredBox(color: IosSheet.opaque, child: body)
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: IosSheet.blur,
                sigmaY: IosSheet.blur,
              ),
              child: ColoredBox(color: IosSheet.tint, child: body),
            ),
    );
  }
}

class IosSheetGrabber extends StatelessWidget {
  const IosSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 36,
      height: 5,
      margin: const EdgeInsets.only(top: 5, bottom: 3),
      decoration: const ShapeDecoration(
        color: IosSheet.grabber,
        shape: StadiumBorder(),
      ),
    ),
  );
}

/// The sheet's title, centred, with the close button at the trailing edge.
class IosSheetHeader extends StatelessWidget {
  const IosSheetHeader({super.key, required this.title, this.onClose});

  final String title;

  /// Null pops the sheet's route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final close = MaterialLocalizations.of(context).closeButtonLabel;
    void dismiss() =>
        onClose != null ? onClose!() : Navigator.of(context).maybePop();
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 60),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IosSheet.title,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Center(
              child: Semantics(
                button: true,
                label: close,
                excludeSemantics: true,
                onTap: dismiss,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: dismiss,
                  child: const SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: IosSheet.cell,
                          shape: CircleBorder(),
                        ),
                        child: SizedBox.square(
                          dimension: 30,
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 14,
                            color: IosSheet.secondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An inset group: [children] on one rounded cell, a hairline between each
/// two, starting [separatorInset] in from the leading edge.
class IosSheetGroup extends StatelessWidget {
  const IosSheetGroup({
    super.key,
    required this.children,
    this.separatorInset = IosSheet.gutter,
    this.footer,
  });

  final List<Widget> children;
  final double separatorInset;

  /// A note under the group, in the footnote style.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final hair = 1 / MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosSheet.gutter,
        6,
        IosSheet.gutter,
        10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: IosSheet.cell,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(IosSheet.groupRadius),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: separatorInset,
                      ),
                      child: SizedBox(
                        height: hair,
                        child: const ColoredBox(color: IosSheet.separator),
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosSheet.gutter,
                6,
                IosSheet.gutter,
                0,
              ),
              child: Text(footer!, style: IosSheet.footnote),
            ),
        ],
      ),
    );
  }
}

/// What a row shows at its trailing edge.
enum IosRowAccessory { none, check, chevron }

/// One row of an inset group: a leading glyph, the title and a line under
/// it, a value, and a check or a chevron — the press a grey wash, not a
/// ripple.
class IosSheetRow extends StatelessWidget {
  const IosSheetRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.value,
    this.accessory = IosRowAccessory.none,
    this.selected = false,
    this.choice = false,
    this.titleColor,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Color? subtitleColor;
  final String? value;
  final IosRowAccessory accessory;

  /// Drawn with the check, and read out as selected.
  final bool selected;

  /// One of a set of which one is on: VoiceOver says so.
  final bool choice;
  final Color? titleColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final dim = enabled ? 1.0 : 0.38;
    final sub = subtitle;
    final shown = value;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: IosSheet.rowHeight),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          IosSheet.gutter,
          10,
          IosSheet.gutter - 2,
          10,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(
                  color: Colors.white.withValues(alpha: dim),
                  size: 22,
                ),
                child: SizedBox(width: 28, child: Center(child: leading)),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IosSheet.body.copyWith(
                      color: (titleColor ?? Colors.white).withValues(
                        alpha: dim,
                      ),
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: IosSheet.footnote.copyWith(
                        color: subtitleColor ?? IosSheet.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (shown != null && shown.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: IosSheet.body.copyWith(
                    color: enabled ? IosSheet.secondary : IosSheet.tertiary,
                  ),
                ),
              ),
            ],
            if (accessory == IosRowAccessory.check)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: SizedBox(
                  width: 22,
                  child: selected
                      ? Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 22,
                          color: AppColors.primary,
                        )
                      : null,
                ),
              ),
            if (accessory == IosRowAccessory.chevron && enabled)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: IosSheet.tertiary,
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      selected: choice ? selected : null,
      inMutuallyExclusiveGroup: choice ? true : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        autofocus: autofocus,
        splashFactory: NoSplash.splashFactory,
        highlightColor: IosSheet.pressed,
        child: row,
      ),
    );
  }
}

/// The Cupertino glyph for a Material one the player's sheets use, so a row
/// on the iOS path draws the phone's own icon; one not listed keeps its own.
IconData cupertinoIconFor(IconData icon) => _cupertino[icon] ?? icon;

final Map<IconData, IconData> _cupertino = {
  Icons.swap_horiz_rounded: CupertinoIcons.arrow_right_arrow_left,
  Icons.download_rounded: CupertinoIcons.arrow_down_circle,
  Icons.aspect_ratio_rounded: CupertinoIcons.crop,
  Icons.play_circle_outline: CupertinoIcons.play_circle,
  Icons.tune_rounded: CupertinoIcons.slider_horizontal_3,
  Icons.photo_camera_outlined: CupertinoIcons.camera,
  Icons.save_alt_rounded: CupertinoIcons.square_arrow_down,
  Icons.auto_awesome_rounded: CupertinoIcons.sparkles,
  Icons.visibility_off_outlined: CupertinoIcons.eye_slash,
  Icons.cast_rounded: CupertinoIcons.tv,
  Icons.cast_connected_rounded: CupertinoIcons.tv_fill,
  Icons.bedtime_outlined: CupertinoIcons.moon_zzz,
  Icons.translate_rounded: CupertinoIcons.globe,
  Icons.text_fields_rounded: CupertinoIcons.textformat_size,
  Icons.audiotrack_outlined: CupertinoIcons.speaker_2,
  Icons.open_in_new_rounded: CupertinoIcons.arrow_up_right_square,
  Icons.info_outline_rounded: CupertinoIcons.info_circle,
  Icons.dashboard_customize_outlined: CupertinoIcons.square_grid_2x2,
  Icons.bug_report_outlined: CupertinoIcons.ant,
  Icons.travel_explore_rounded: CupertinoIcons.search,
  Icons.folder_open_rounded: CupertinoIcons.folder,
  Icons.av_timer_rounded: CupertinoIcons.timer,
};
