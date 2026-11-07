import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/progress/domain/progress.dart';

/// How each cosmetic id looks. The server only stores ids; an id this build
/// does not know draws as nothing rather than as a broken frame.
class Cosmetics {
  Cosmetics._();

  static const Map<String, List<Color>> frames = {
    'bronze': [Color(0xFFE0A374), Color(0xFF9C5B2E)],
    'silver': [Color(0xFFF2F2F2), Color(0xFF9DA3AB)],
    'gold': [Color(0xFFFFE58A), Color(0xFFD4A017)],
    'neon': [Color(0xFF3DF5FF), Color(0xFFB44DFF)],
    'sakura': [Color(0xFFFFC6DD), Color(0xFFFF6FA5)],
    'ember': [Color(0xFFFFC078), Color(0xFFEF4A1A)],
    'flame': [Color(0xFFFFE066), Color(0xFFFF7A1A), Color(0xFFE5243B)],
    'moon': [Color(0xFFDDE6FF), Color(0xFF4C5BD4)],
  };

  static const Map<String, Color> nameColors = {
    'sky': Color(0xFF6EC1FF),
    'mint': Color(0xFF5EE6B0),
    'gold': Color(0xFFFFD45E),
    'rose': Color(0xFFFF7FA8),
    'violet': Color(0xFFB98CFF),
    'crimson': Color(0xFFFF5A5F),
    'aurora': Color(0xFF7CF2D8),
    'ember': Color(0xFFFF9F43),
  };

  static const Set<String> titles = {
    'newcomer',
    'regular',
    'veteran',
    'legend',
    'binger',
    'cinephile',
    'otaku',
    'bookworm',
    'night_owl',
    'host',
  };

  static List<Color>? frame(String? id) => id == null ? null : frames[id];

  static Color? nameColor(String? id) => id == null ? null : nameColors[id];

  /// The words for a title, or null for one this build has none for.
  static String? titleText(String? id) =>
      id != null && titles.contains(id) ? 'progress.title_$id'.tr() : null;

  static bool isKnown(CosmeticSlot slot, String id) => switch (slot) {
    CosmeticSlot.frame => frames.containsKey(id),
    CosmeticSlot.title => titles.contains(id),
    CosmeticSlot.nameColor => nameColors.containsKey(id),
  };

  /// The name a locker shows for any cosmetic.
  static String label(CosmeticSlot slot, String id) => switch (slot) {
    CosmeticSlot.frame => 'progress.frame_$id'.tr(),
    CosmeticSlot.title => 'progress.title_$id'.tr(),
    CosmeticSlot.nameColor => 'progress.color_$id'.tr(),
  };
}

/// An avatar inside the frame its owner equipped; the avatar alone without
/// one.
class FramedAvatar extends StatelessWidget {
  const FramedAvatar({
    super.key,
    required this.size,
    required this.child,
    this.frame,
    this.radius,
  });

  /// The avatar's own size; the frame is drawn around it, not into it.
  final double size;
  final Widget child;
  final String? frame;

  /// Corner radius for a square avatar; null for a circle.
  final double? radius;

  static double ringFor(double size) =>
      (size * 0.07).clamp(2.0, 5.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = Cosmetics.frame(frame);
    if (colors == null) return child;
    final ring = ringFor(size);
    final shape = radius == null
        ? const BoxDecoration(shape: BoxShape.circle)
        : BoxDecoration(borderRadius: BorderRadius.circular(radius! + ring));
    return Container(
      width: size + ring * 2,
      height: size + ring * 2,
      padding: EdgeInsets.all(ring),
      decoration: shape.copyWith(
        gradient: SweepGradient(colors: [...colors, colors.first]),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.35),
            blurRadius: ring * 2.5,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// "Lv 12" as a small pill.
class LevelChip extends StatelessWidget {
  const LevelChip({super.key, required this.level, this.fontSize = 10});

  final int level;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.55,
        vertical: fontSize * 0.15,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(fontSize),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 0.6,
        ),
      ),
      child: Text(
        'progress.level_short'.tr(args: ['$level']),
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

/// A name in its owner's colour, their level beside it and, when asked, their
/// title under it. With no [decoration] it is just the name.
class UserBadgeLine extends StatelessWidget {
  const UserBadgeLine({
    super.key,
    required this.name,
    required this.decoration,
    required this.style,
    this.showTitle = false,
    this.center = false,
    this.chipSize,
  });

  final String name;
  final UserDecoration? decoration;
  final TextStyle style;
  final bool showTitle;
  final bool center;
  final double? chipSize;

  @override
  Widget build(BuildContext context) {
    final d = decoration;
    final color = Cosmetics.nameColor(d?.nameColor);
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : null,
            style: color == null ? style : style.copyWith(color: color),
          ),
        ),
        if (d != null && d.level > 0) ...[
          const SizedBox(width: 6),
          LevelChip(
            level: d.level,
            fontSize: chipSize ?? ((style.fontSize ?? 13) * 0.72),
          ),
        ],
      ],
    );
    final title = showTitle ? Cosmetics.titleText(d?.title) : null;
    if (title == null) return line;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        line,
        const SizedBox(height: 2),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: (color ?? AppColors.textSecondary).withValues(alpha: 0.85),
            fontSize: (style.fontSize ?? 13) * 0.78,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
