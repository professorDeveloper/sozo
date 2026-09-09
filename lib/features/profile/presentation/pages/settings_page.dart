import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Everything the user can configure about the app itself.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Native names on purpose: a person looking for their own language finds it
  /// fastest written the way they write it.
  static const _languageNames = <String, String>{
    'en': 'English',
    'uz': "O'zbekcha",
    'ru': 'Русский',
    'ar': 'العربية',
  };

  Future<void> _setLanguage(String code) async {
    if (code == context.locale.languageCode) return;
    await context.setLocale(Locale(code));
    await getIt<HiveService>().saveLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final lockOn = getIt<AppLockRepository>().isEnabled;
    return SettingsPageScaffold(
      title: 'profile.settings_title'.tr(),
      children: [
        SettingsLabel('profile.section_general'.tr(),
            featureIds: const ['home_rails', 'change_source']),
        SettingsCard(
          children: [
            SettingsDropdownTile<String>(
              icon: Icons.translate_rounded,
              title: 'profile.language'.tr(),
              subtitle: 'profile.language_desc'.tr(),
              value: context.locale.languageCode,
              options: [
                for (final l in context.supportedLocales) l.languageCode,
              ],
              labelOf: (code) => _languageNames[code] ?? code,
              onChanged: _setLanguage,
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.palette_outlined,
              title: 'appearance.title'.tr(),
              subtitle: 'appearance.entry_subtitle'.tr(),
              featureId: 'home_rails',
              trailing: const SettingsAccentChevron(),
              onTap: () => context.push('/appearance'),
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.view_week_rounded,
              title: 'profile.nav_style'.tr(),
              onTap: () => context.push('/navbar'),
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.play_circle_outline_rounded,
              title: 'profile.section_player'.tr(),
              featureId: 'change_source',
              onTap: () => context.push('/player-settings'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('app_lock.section_label'.tr()),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.lock_rounded,
              title: 'app_lock.app_lock'.tr(),
              value: lockOn
                  ? 'app_lock.state_on'.tr()
                  : 'app_lock.state_off'.tr(),
              valueColor: lockOn ? AppColors.primary : null,
              onTap: () async {
                await context.push('/app-lock-settings');
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('profile.section_data'.tr(), featureIds: const ['backup']),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.backup_outlined,
              title: 'backup.title'.tr(),
              featureId: 'backup',
              onTap: () => context.push('/backup'),
            ),
          ],
        ),
      ],
    );
  }
}
