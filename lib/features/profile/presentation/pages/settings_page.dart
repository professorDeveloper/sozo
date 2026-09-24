import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/tracker/data/library_update_scheduler.dart';
import 'package:soplay/core/localization/app_language.dart';
import 'package:soplay/core/localization/language_picker.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Everything the user can configure about the app itself.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final HiveService _hive = getIt<HiveService>();

  /// The one 18+ switch. Turning it on asks once whether the viewer is an
  /// adult; turning it off never asks. Either way every list built from it is
  /// rebuilt at once — the sources the picker offers, and Home, whose
  /// catalogue the backend now answers differently.
  static String _libraryUpdateLabel(int hours) => switch (hours) {
    0 => 'general.off'.tr(),
    24 => 'profile.library_update_daily'.tr(),
    _ => 'profile.library_update_every'.tr(args: ['$hours']),
  };

  /// How often followed titles are checked for new episodes.
  Future<void> _pickLibraryUpdate() async {
    final scheduler = getIt<LibraryUpdateScheduler>();
    final current = scheduler.intervalHours;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: Text('profile.library_update'.tr()),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final h in LibraryUpdateScheduler.choices)
                  RadioListTile<int>(
                    value: h,
                    title: Text(_libraryUpdateLabel(h)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await scheduler.setIntervalHours(picked);
    if (mounted) setState(() {});
  }

  Future<void> _setAdult(bool value) async {
    if (value && !await _confirmAdult()) return;
    await _hive.setShowAdultContent(value);
    if (!mounted) return;
    setState(() {});
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
    try {
      context.read<HomeBloc>().add(HomeLoad(silent: true));
    } catch (_) {}
  }

  Future<bool> _confirmAdult() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('profile.adult_confirm_title'.tr()),
          content: Text('profile.adult_confirm_body'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('general.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('profile.adult_confirm_yes'.tr()),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final lockOn = getIt<AppLockRepository>().isEnabled;
    return SettingsPageScaffold(
      title: 'profile.settings_title'.tr(),
      children: [
        SettingsLabel(
          'profile.section_general'.tr(),
          featureIds: const ['home_rails', 'change_source'],
        ),
        SettingsCard(
          children: [
            // The page, not a dropdown. Eleven languages in a menu that opens
            // over the row is a list nobody can read in their own script — and
            // the page that does it properly already existed for first run.
            SettingsNavTile(
              icon: Icons.translate_rounded,
              title: 'profile.language'.tr(),
              subtitle: 'profile.language_desc'.tr(),
              value: AppLanguage.labelOf(context.locale.languageCode),
              onTap: () => openLanguagePage(context),
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
        SettingsLabel('profile.section_content'.tr()),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.eighteen_up_rating_outlined,
              title: 'profile.adult_content'.tr(),
              subtitle: ProfileScope.isKids
                  ? 'profiles.adult_kids_off'.tr()
                  : 'profile.adult_content_desc'.tr(),
              value: _hive.showAdultContent,
              enabled: !ProfileScope.isKids,
              onChanged: _setAdult,
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.update_rounded,
              title: 'profile.library_update'.tr(),
              subtitle: 'profile.library_update_desc'.tr(),
              value: _libraryUpdateLabel(
                getIt<LibraryUpdateScheduler>().intervalHours,
              ),
              onTap: _pickLibraryUpdate,
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.auto_mode_rounded,
              title: 'automation.title'.tr(),
              subtitle: 'automation.entry_subtitle'.tr(),
              onTap: () async {
                await context.push('/automation');
                if (mounted) setState(() {});
              },
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
        SettingsLabel(
          'profile.section_data'.tr(),
          featureIds: const ['backup'],
        ),
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
