import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// The tile vocabulary shared by every standalone settings screen reached from
/// Profile (Player, Navigation bar, …).
///
/// Profile itself still uses its own private copies of the card/label/tile
/// widgets. These are deliberately identical in metrics and colour so a
/// sub-page reads as a continuation of the list that opened it — if you change
/// padding or radius here, change it there too.
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

class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Footnote under a card. For the one-line "why does this exist" text that
/// would bloat a [SettingsDropdownTile] subtitle.
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

/// A row that opens a menu of mutually exclusive values, with the current one
/// shown on the right. Used instead of a nested sub-page for settings whose
/// options fit on one screen.
///
/// [T] is the value type; [labelOf] renders both the menu entries and the
/// trailing summary, so they can never drift apart.
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
      // The whole row is the tap target, but PopupMenuButton needs to own the
      // gesture to position its menu against the anchor. So the row itself is
      // inert and the button fills the trailing slot.
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
      // Thumb must be explicitly white: left at its default it resolves to the
      // same primary as the track, and an all-red capsule reads as a solid
      // blob with no visible on/off state.
      trailing: Switch.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primary,
        // The row is the tap target, so the switch's own 48px material one only
        // ever made switch rows taller than the dropdown rows beside them.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Shared row chrome: icon chip, title, optional subtitle, trailing slot.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.enabled,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool enabled;
  final VoidCallback? onTap;

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
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: AppColors.textSecondary, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
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
                  // Half the row at most: past that the value wins the tug of
                  // war with the title and pushes it into a wrapped column.
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
