import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/whats_new.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/theme_controller.dart';

/// The tile vocabulary shared by Profile and every settings screen it opens,
/// so a sub-page reads as a continuation of the list that opened it.

/// A count for a row's trailing slot, or null when there is nothing to say.
///
/// Zero is not shown: "0" next to Downloads reads as a broken counter, while
/// an empty slot reads as an empty list, which is what it is.
String? countLabel(int n) => n > 0 ? '$n' : null;

/// Scaffold every settings screen uses: flat app bar, one scrolling column of
/// labelled cards, clearance for the floating nav at the bottom.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: actions,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: children,
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// Section heading with the accent tick Home puts in front of its row titles.
///
/// [featureIds] lifts a NEW mark up to the heading: a badge only on the row is
/// invisible until the reader has already scrolled to it.
class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.label, {super.key, this.featureIds = const []});

  final String label;
  final List<String> featureIds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 2.5,
            height: 11,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          if (featureIds.isNotEmpty) SettingsNewDot(ids: featureIds),
        ],
      ),
    );
  }
}

/// Footnote under a card, for the one line of "why does this exist" that
/// would bloat a row subtitle.
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(color: AppColors.divider, height: 1, indent: 64);
}

class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.chevron_right_rounded,
    color: AppColors.textHint,
    size: 20,
  );
}

/// Chevron with the current accent in front of it, for the Appearance row:
/// the row's whole subject is a colour, so the answer belongs on the row.
class SettingsAccentChevron extends StatelessWidget {
  const SettingsAccentChevron({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = getIt<ThemeController>().accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: accent.base,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const SettingsChevron(),
      ],
    );
  }
}

/// The 34px leading box of a row: an icon chip, or any [child] in the same
/// box so the column of leading marks never shifts between rows.
class SettingsLeadingChip extends StatelessWidget {
  const SettingsLeadingChip({
    super.key,
    this.icon,
    this.child,
    this.destructive = false,
  });

  final IconData? icon;
  final Widget? child;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final custom = child;
    if (custom != null) {
      return SizedBox(width: 34, height: 34, child: custom);
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: destructive
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: icon == null
          ? null
          : Icon(
              icon,
              color: destructive ? AppColors.error : AppColors.textSecondary,
              size: 18,
            ),
    );
  }
}

/// Remote logo in the leading slot; the plain icon chip stands in while it
/// loads and if it fails, so the row never has a hole where its mark should be.
class SettingsTileLogo extends StatelessWidget {
  const SettingsTileLogo({super.key, required this.url, required this.fallback});

  final String url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final cache = (34 * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        memCacheWidth: cache,
        memCacheHeight: cache,
        placeholder: (_, _) => SettingsLeadingChip(icon: fallback),
        errorWidget: (_, _, _) => SettingsLeadingChip(icon: fallback),
      ),
    );
  }
}

/// The NEW mark on a row for a feature the viewer has not opened yet.
class SettingsNewBadge extends StatelessWidget {
  const SettingsNewBadge({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WhatsNew.revision,
      builder: (context, _, _) {
        if (!WhatsNew.isNew(id)) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsetsDirectional.only(start: 7),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            'general.new_badge'.tr(),
            style: TextStyle(
              color: AppColors.onPrimary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        );
      },
    );
  }
}

/// A small accent dot, shown while anything in [ids] is unseen.
class SettingsNewDot extends StatelessWidget {
  const SettingsNewDot({super.key, required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WhatsNew.revision,
      builder: (context, _, _) {
        if (!WhatsNew.anyNew(ids)) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsetsDirectional.only(start: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// A row that opens something.
///
/// The trailing area is, by default, [valueLeading] + [value] + a chevron when
/// there is an [onTap]. Passing [trailing] replaces all of that.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.value,
    this.valueColor,
    this.valueLeading,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.featureId,
    this.enabled = true,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final Widget? valueLeading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  /// Registered [WhatsNew] id: shows a NEW badge until the row is opened.
  final String? featureId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final trail =
        trailing ??
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (valueLeading != null) ...[
              valueLeading!,
              const SizedBox(width: 8),
            ],
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const SettingsChevron(),
            ],
          ],
        );
    final tap = onTap;
    return _SettingsRow(
      icon: icon,
      leading: leading,
      title: title,
      subtitle: subtitle,
      destructive: destructive,
      featureId: featureId,
      enabled: enabled,
      trailing: trail,
      onTap: tap == null
          ? null
          : () {
              // Opening the row is what clears its badge, not scrolling past.
              final id = featureId;
              if (id != null) WhatsNew.markSeen(id);
              tap();
            },
    );
  }
}

/// A row that opens a menu of mutually exclusive values, with the current one
/// shown on the right.
class SettingsDropdownTile<T> extends StatelessWidget {
  const SettingsDropdownTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      // PopupMenuButton needs to own the gesture to position its menu against
      // the anchor, so the row itself is inert and the button fills the slot.
      trailing: PopupMenuButton<T>(
        enabled: enabled,
        color: AppColors.surface,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final option in options)
            PopupMenuItem<T>(
              value: option,
              height: 42,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      labelOf(option),
                      style: TextStyle(
                        color: option == value
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: option == value
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (option == value)
                    Icon(
                      Icons.check_rounded,
                      color: AppColors.primary,
                      size: 17,
                    ),
                ],
              ),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                labelOf(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? AppColors.primary : AppColors.textHint,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: enabled ? AppColors.primary : AppColors.textHint,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      // Thumb explicitly white: at its default it resolves to the same primary
      // as the track, and an all-accent capsule has no visible on/off state.
      trailing: Switch.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primary,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Shared row chrome: leading chip, title, optional subtitle, trailing slot.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.trailing,
    required this.enabled,
    this.icon,
    this.leading,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.featureId,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool enabled;
  final VoidCallback? onTap;
  final bool destructive;
  final String? featureId;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 11, 12, 11),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  SettingsLeadingChip(
                    icon: icon,
                    destructive: destructive,
                    child: leading,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: destructive
                                      ? AppColors.error
                                      : AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: destructive
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (featureId != null)
                              SettingsNewBadge(id: featureId!),
                          ],
                        ),
                        if (sub != null && sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Half the row at most, so a long value cannot push the
                  // title into a wrapped column.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.5,
                    ),
                    child: trailing,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
