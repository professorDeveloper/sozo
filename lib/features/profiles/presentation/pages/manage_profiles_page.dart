import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/profile_flows.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';

class ManageProfilesPage extends StatefulWidget {
  const ManageProfilesPage({super.key, this.session});

  final ProfileSession? session;

  @override
  State<ManageProfilesPage> createState() => _ManageProfilesPageState();
}

class _ManageProfilesPageState extends State<ManageProfilesPage> {
  late final ProfileSession _session =
      widget.session ?? getIt<ProfileSession>();
  bool _loading = false;
  bool _failed = false;

  /// Profiles whose PIN this device knows, and whether each opens with
  /// biometrics. Empty where biometrics aren't available.
  Map<String, bool> _biometric = const {};

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final ok = await _session.refresh();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = !ok;
    });
    await _loadBiometric();
  }

  Future<void> _loadBiometric() async {
    final out = <String, bool>{};
    if (await _session.biometricsAvailable()) {
      for (final p in _session.profiles) {
        if (p.hasPin && await _session.hasLocalPin(p.id)) {
          out[p.id] = await _session.biometricEnabled(p.id);
        }
      }
    }
    if (mounted) setState(() => _biometric = out);
  }

  Future<void> _toggleBiometric(HouseholdProfile p, bool on) async {
    if (on) {
      final pin = await askProfilePin(
        context,
        _session,
        p,
        allowBiometric: false,
      );
      if (pin == null || !mounted) return;
    }
    await _session.setBiometric(
      p.id,
      on,
      reason: 'app_lock.biometric_enable_reason'.tr(),
    );
    await _loadBiometric();
  }

  String? _tags(HouseholdProfile p) {
    final tags = [
      if (p.isDefault) 'profiles.main_badge'.tr(),
      if (p.isKids) 'profiles.kids'.tr(),
      if (p.hasPin) 'profiles.pin_protected'.tr(),
      if (p.id == _session.active?.id) 'profiles.current'.tr(),
    ];
    return tags.isEmpty ? null : tags.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _session.profiles;
    return SettingsPageScaffold(
      title: 'profiles.manage'.tr(),
      children: [
        if (!_session.canManage)
          const _KidsLocked()
        else if (profiles.isEmpty && _loading)
          Padding(
            padding: const EdgeInsets.only(top: 64),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (profiles.isEmpty)
          _LoadFailed(onRetry: _load, offline: _failed)
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              'profiles.manage_subtitle'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
          SettingsCard(
            children: [
              for (var i = 0; i < profiles.length; i++) ...[
                if (i > 0) const SettingsDivider(),
                SettingsNavTile(
                  leading: ProfileAvatar.of(
                    profiles[i],
                    size: 34,
                    showLock: false,
                  ),
                  title: profiles[i].name,
                  subtitle: _tags(profiles[i]),
                  onTap: () =>
                      context.push('/profiles/edit', extra: profiles[i]),
                ),
              ],
              if (_session.canAdd) ...[
                const SettingsDivider(),
                SettingsNavTile(
                  icon: Icons.add_rounded,
                  title: 'profiles.add'.tr(),
                  onTap: () => context.push('/profiles/edit'),
                ),
              ],
            ],
          ),
          SettingsFootnote('profiles.limit'.tr(args: ['${_session.max}'])),
          const SizedBox(height: 20),
          SettingsLabel('profiles.on_this_device'.tr()),
          SettingsCard(
            children: [
              SettingsSwitchTile(
                icon: Icons.switch_account_rounded,
                title: 'profiles.ask_on_launch'.tr(),
                subtitle: 'profiles.ask_on_launch_desc'.tr(),
                value: _session.askOnLaunch,
                onChanged: _session.setAskOnLaunch,
              ),
              for (final p in profiles)
                if (_biometric.containsKey(p.id)) ...[
                  const SettingsDivider(),
                  SettingsSwitchTile(
                    icon: Icons.fingerprint_rounded,
                    title: 'profiles.biometric_toggle'.tr(args: [p.name]),
                    value: _biometric[p.id]!,
                    onChanged: (on) => _toggleBiometric(p, on),
                  ),
                ],
            ],
          ),
        ],
      ],
    );
  }
}

class _KidsLocked extends StatelessWidget {
  const _KidsLocked();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_person_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'profiles.kids_locked_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'profiles.kids_locked_body'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          AppPrimaryButton(
            label: 'profiles.switch'.tr(),
            icon: Icons.switch_account_rounded,
            expand: false,
            onPressed: () => context.push('/profiles'),
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry, required this.offline});

  final VoidCallback onRetry;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.textSecondary,
            size: 44,
          ),
          const SizedBox(height: 14),
          Text(
            'profiles.load_failed'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (offline) ...[
            const SizedBox(height: 6),
            Text(
              'profiles.offline'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
          AppPrimaryButton(
            label: 'general.retry'.tr(),
            expand: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
