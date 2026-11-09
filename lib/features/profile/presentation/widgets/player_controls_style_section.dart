import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/player_controls_style.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Settings → Player → Controls style: iPhone and iPad only.
class PlayerControlsStyleSection extends StatelessWidget {
  const PlayerControlsStyleSection({
    super.key,
    required this.chosen,
    required this.capability,
    required this.onChanged,
  });

  final PlayerControlsStyle chosen;

  /// What the phone said it can draw; the styles it cannot are disabled.
  final NativeGlassCapability capability;

  final ValueChanged<PlayerControlsStyle> onChanged;

  static bool get shown =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static IconData _icon(PlayerControlsStyle s) => switch (s) {
    PlayerControlsStyle.native => Icons.phone_iphone_rounded,
    PlayerControlsStyle.systemGlass => Icons.blur_on_rounded,
    PlayerControlsStyle.classicGlass => Icons.blur_circular_rounded,
  };

  static String _title(PlayerControlsStyle s) => switch (s) {
    PlayerControlsStyle.native => 'profile.controls_style_native'.tr(),
    PlayerControlsStyle.systemGlass => 'profile.controls_style_system'.tr(),
    PlayerControlsStyle.classicGlass => 'profile.controls_style_classic'.tr(),
  };

  static String _desc(PlayerControlsStyle s) => switch (s) {
    PlayerControlsStyle.native => 'profile.controls_style_native_desc'.tr(),
    PlayerControlsStyle.systemGlass =>
      'profile.controls_style_system_desc'.tr(),
    PlayerControlsStyle.classicGlass =>
      'profile.controls_style_classic_desc'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    if (!shown) return const SizedBox.shrink();
    // What the player will draw: a choice this phone cannot have shows as
    // the classic glass it falls back to.
    final current = playerControlsStyleAvailable(chosen, capability)
        ? chosen
        : PlayerControlsStyle.classicGlass;
    final styles = PlayerControlsStyle.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsLabel('profile.controls_style'.tr()),
        SettingsCard(
          children: [
            for (var i = 0; i < styles.length; i++) ...[
              if (i > 0) const SettingsDivider(),
              _row(styles[i], current),
            ],
          ],
        ),
        SettingsFootnote('profile.controls_style_desc'.tr()),
      ],
    );
  }

  Widget _row(PlayerControlsStyle style, PlayerControlsStyle current) {
    final available = playerControlsStyleAvailable(style, capability);
    final selected = style == current;
    return SettingsNavTile(
      key: ValueKey('controls-style-${style.name}'),
      icon: _icon(style),
      title: _title(style),
      subtitle: available
          ? _desc(style)
          : 'profile.controls_style_needs_ios26'.tr(),
      enabled: available,
      trailing: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: selected ? AppColors.primary : AppColors.textHint,
      ),
      onTap: available && !selected ? () => onChanged(style) : null,
    );
  }
}
