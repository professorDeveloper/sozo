import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/airing_reminders.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/notifications/data/notification_prefs.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/notifications/presentation/widgets/animated_bell.dart';
import 'package:soplay/features/notifications/presentation/widgets/notification_priming.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/library_update_scheduler.dart';
import 'package:soplay/features/tracker/data/release_watch.dart';

/// Settings → Notifications: what Sozo may tell you about, and when.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  final NotificationService _service = getIt<NotificationService>();
  late NotificationPrefs _prefs = _service.prefs;
  bool? _granted;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from system settings, the switch there may have moved.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readPermission());
  }

  Future<void> _readPermission() async {
    final granted = await _service.permissionGranted;
    final blocked = granted ? false : await _service.permanentlyDenied;
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _blocked = blocked;
    });
  }

  Future<void> _fixPermission() async {
    if (_blocked) {
      await _service.openSystemSettings();
      return;
    }
    final ok = await _service.requestPermission();
    if (!ok && mounted) {
      final blocked = await _service.permanentlyDenied;
      if (blocked) await _service.openSystemSettings();
    }
    await _readPermission();
  }

  Future<void> _save(NotificationPrefs next) async {
    HapticFeedback.selectionClick();
    setState(() => _prefs = next);
    await _service.prefsStore.write(next);
  }

  Future<void> _setMaster(bool on) async {
    await _save(_prefs.copyWith(master: on));
    if (on && _granted == false && mounted) {
      await showNotificationPriming(context);
      await _readPermission();
    }
  }

  Future<void> _setAiring(bool on) async {
    HapticFeedback.selectionClick();
    final reminders = getIt<AiringReminders>();
    final anilist = getIt<AnilistService>();
    await reminders.setEnabled(on);
    if (on && !_prefs.isOn(NotificationCategory.airing)) {
      await _save(_prefs.withCategory(NotificationCategory.airing, true));
    }
    if (on && anilist.isConnected) {
      unawaited(anilist.library().then(reminders.sync).catchError((Object _) {}));
    }
    if (!mounted) return;
    setState(() {});
    if (on && !anilist.isConnected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('release_notify.airing_needs_anilist'.tr()),
          ),
        );
    }
  }

  Future<void> _pickQuiet({required bool from}) async {
    final minutes = from ? _prefs.quiet.from : _prefs.quiet.to;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    final value = picked.hour * 60 + picked.minute;
    await _save(
      _prefs.copyWith(
        quiet: from
            ? _prefs.quiet.copyWith(from: value)
            : _prefs.quiet.copyWith(to: value),
      ),
    );
    _resyncReminders();
  }

  /// Airing reminders are laid down ahead of time with their quiet-hours
  /// treatment baked in, so a change to the window lays them down again.
  void _resyncReminders() {
    final reminders = getIt<AiringReminders>();
    final anilist = getIt<AnilistService>();
    if (!reminders.enabled || !anilist.isConnected) return;
    unawaited(anilist.library().then(reminders.sync).catchError((Object _) {}));
  }

  String _time(int minutes) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));

  static String _intervalLabel(int hours) => switch (hours) {
    0 => 'general.off'.tr(),
    24 => 'profile.library_update_daily'.tr(),
    _ => 'profile.library_update_every'.tr(args: ['$hours']),
  };

  Future<void> _pickInterval() async {
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
                  RadioListTile<int>(value: h, title: Text(_intervalLabel(h))),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await scheduler.setIntervalHours(picked);
    unawaited(getIt<ReleaseWatch>().scheduleBackground());
    if (mounted) setState(() {});
  }

  Future<void> _sendTest() async {
    HapticFeedback.lightImpact();
    if (_granted != true) {
      final ok = await showNotificationPriming(context);
      await _readPermission();
      if (!ok) return;
    }
    final latest = getIt<FollowService>().list().firstOrNull;
    await _service.showTest(
      sample: latest == null
          ? null
          : ReleaseAlert(
              provider: latest.provider,
              contentUrl: latest.contentUrl,
              title: latest.title,
              thumbnail: latest.thumbnail,
              mode: latest.mode,
              episodeNumber: latest.lastEpisodeCount > 0
                  ? latest.lastEpisodeCount
                  : 1,
            ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('release_notify.test_sent'.tr()),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final master = _prefs.master;
    final airingOn = getIt<AiringReminders>().enabled;
    final quiet = _prefs.quiet;

    Widget type(
      NotificationCategory c,
      IconData icon,
      String key,
    ) => SettingsSwitchTile(
      icon: icon,
      title: 'release_notify.type_$key'.tr(),
      subtitle: 'release_notify.type_${key}_desc'.tr(),
      value: _prefs.isOn(c),
      enabled: master,
      onChanged: (on) => _save(_prefs.withCategory(c, on)),
    );

    return SettingsPageScaffold(
      title: 'release_notify.settings_title'.tr(),
      children: [
        _PermissionBanner(
          granted: _granted,
          blocked: _blocked,
          master: master,
          onFix: _fixPermission,
        ),
        const SizedBox(height: 16),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.notifications_rounded,
              title: 'release_notify.master'.tr(),
              subtitle: 'release_notify.master_desc'.tr(),
              value: master,
              onChanged: _setMaster,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('release_notify.section_types'.tr()),
        SettingsCard(
          children: [
            type(
              NotificationCategory.releases,
              Icons.new_releases_rounded,
              'releases',
            ),
            const SettingsDivider(),
            SettingsSwitchTile(
              icon: Icons.event_available_rounded,
              title: 'release_notify.type_airing'.tr(),
              subtitle: 'release_notify.type_airing_desc'.tr(),
              value: airingOn && _prefs.isOn(NotificationCategory.airing),
              enabled: master,
              onChanged: _setAiring,
            ),
            const SettingsDivider(),
            type(NotificationCategory.friends, Icons.people_alt_rounded, 'friends'),
            const SettingsDivider(),
            type(
              NotificationCategory.streak,
              Icons.local_fire_department_rounded,
              'streak',
            ),
            const SettingsDivider(),
            type(
              NotificationCategory.announcements,
              Icons.campaign_rounded,
              'announcements',
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('release_notify.section_quiet'.tr()),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.bedtime_rounded,
              title: 'release_notify.quiet'.tr(),
              subtitle: 'release_notify.quiet_desc'.tr(),
              value: quiet.enabled,
              enabled: master,
              onChanged: (on) async {
                await _save(_prefs.copyWith(quiet: quiet.copyWith(enabled: on)));
                _resyncReminders();
              },
            ),
            if (quiet.enabled) ...[
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.nights_stay_outlined,
                title: 'release_notify.quiet_from'.tr(),
                value: _time(quiet.from),
                enabled: master,
                onTap: () => _pickQuiet(from: true),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.wb_sunny_outlined,
                title: 'release_notify.quiet_to'.tr(),
                value: _time(quiet.to),
                enabled: master,
                onTap: () => _pickQuiet(from: false),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('release_notify.section_checks'.tr()),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.update_rounded,
              title: 'profile.library_update'.tr(),
              subtitle: 'profile.library_update_desc'.tr(),
              value: _intervalLabel(getIt<LibraryUpdateScheduler>().intervalHours),
              onTap: _pickInterval,
            ),
          ],
        ),
        SettingsFootnote('release_notify.check_background_note'.tr()),
        const SizedBox(height: 20),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.send_rounded,
              title: 'release_notify.test'.tr(),
              subtitle: 'release_notify.test_desc'.tr(),
              onTap: _sendTest,
            ),
          ],
        ),
      ],
    );
  }
}

/// The OS permission, stated first: every switch below is moot while it is
/// off, so it gets a banner with the fix rather than a row among them.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.granted,
    required this.blocked,
    required this.master,
    required this.onFix,
  });

  final bool? granted;
  final bool blocked;
  final bool master;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final known = granted;
    if (known == null) return const SizedBox(height: 76);
    final ok = known;
    final accent = ok ? AppColors.success : AppColors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: AnimatedBell(
              state: ok && master ? BellState.on : BellState.muted,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'release_notify.permission'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? 'release_notify.permission_on'.tr()
                      : blocked
                      ? 'release_notify.permission_blocked'.tr()
                      : 'release_notify.permission_off'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (!ok)
            FilledButton(
              onPressed: onFix,
              child: Text(
                blocked
                    ? 'release_notify.priming_open_settings'.tr()
                    : 'release_notify.permission_fix'.tr(),
              ),
            ),
        ],
      ),
    );
  }
}
