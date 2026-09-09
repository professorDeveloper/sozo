import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';

class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  late final AppLockRepository _repo = getIt<AppLockRepository>();
  late final HiveService _hive = getIt<HiveService>();
  bool _biometricAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricSupport();
  }

  Future<void> _loadBiometricSupport() async {
    final available = await _repo.isBiometricAvailable();
    if (mounted) setState(() => _biometricAvailable = available);
  }

  Future<void> _toggleLock(bool value) async {
    if (_busy) return;
    if (value) {
      final ok = await context.push<bool>('/pin-setup');
      if (ok == true && mounted) setState(() {});
    } else {
      final confirmed = await _confirmDisable();
      // `mounted` as well as the answer: the confirmation is a sheet, and
      // dismissing it is a moment when the page behind can go with it.
      if (!confirmed || !mounted) return;
      setState(() => _busy = true);
      await _repo.disable();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDisable() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'app_lock.disable_title'.tr(),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'app_lock.disable_subtitle'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('general.delete'.tr()),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _changePin() async {
    final ok = await context.push<bool>('/pin-setup', extra: true);
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final available = await _repo.isBiometricAvailable();
      if (!available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('app_lock.biometric_unavailable'.tr())),
        );
        return;
      }
      final authed = await _repo.authenticateWithBiometrics(
        'app_lock.biometric_enable_reason'.tr(),
      );
      if (!authed) return;
    }
    await _repo.setBiometricPreferred(value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleAlwaysAsk(bool value) async {
    await _hive.setPrivateAlwaysAsk(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _repo.isEnabled;
    final biometricOn = _repo.isBiometricPreferred;
    final pinLen = _repo.pinLength;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('app_lock.settings_title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              children: [
                _Row(
                  icon: Icons.lock_rounded,
                  title: 'app_lock.enable'.tr(),
                  trailing: Switch.adaptive(
                    value: enabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: _toggleLock,
                  ),
                ),
                if (enabled) ...[
                  Divider(color: AppColors.divider, height: 1),
                  _Row(
                    icon: Icons.pin_rounded,
                    title: 'app_lock.change_pin'.tr(),
                    subtitle: 'app_lock.length_n_digits'.tr(args: ['$pinLen']),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                    ),
                    onTap: _changePin,
                  ),
                  if (_biometricAvailable) ...[
                    Divider(color: AppColors.divider, height: 1),
                    _Row(
                      icon: Icons.fingerprint_rounded,
                      title: 'app_lock.biometric'.tr(),
                      trailing: Switch.adaptive(
                        value: biometricOn,
                        activeThumbColor: AppColors.primary,
                        onChanged: _toggleBiometric,
                      ),
                    ),
                  ],
                ],
                Divider(color: AppColors.divider, height: 1),
                Opacity(
                  opacity: enabled ? 1.0 : 0.5,
                  child: _Row(
                    icon: Icons.lock_person_rounded,
                    title: 'app_lock.private_always_ask'.tr(),
                    subtitle: 'app_lock.private_always_ask_hint'.tr(),
                    trailing: Switch.adaptive(
                      value: _hive.isPrivateAlwaysAsk,
                      activeThumbColor: AppColors.primary,
                      onChanged: enabled ? _toggleAlwaysAsk : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              enabled
                  ? 'app_lock.enabled_hint'.tr()
                  : 'app_lock.disabled_hint'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

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
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
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
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
