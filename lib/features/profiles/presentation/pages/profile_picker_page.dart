import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/profile_flows.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';

/// Where a pick lands: [then] when it is exactly a setup step, Home otherwise.
/// A prefix check would let `/onboarding/../anything` through, which the
/// router resolves to `/anything`.
String afterProfilePick(String? then) {
  for (final step in OnboardingStep.values) {
    if (step.path == then) return then!;
  }
  return '/main';
}

/// "Who's watching?" — shown at launch when the account has several profiles,
/// and from Profile whenever someone wants to switch.
class ProfilePickerPage extends StatefulWidget {
  const ProfilePickerPage({super.key, this.session, this.then});

  final ProfileSession? session;

  /// Where to go once a profile is picked, when that is not Home — the setup
  /// continuing after a sign-in. Only setup routes are honoured.
  final String? then;

  @override
  State<ProfilePickerPage> createState() => _ProfilePickerPageState();
}

class _ProfilePickerPageState extends State<ProfilePickerPage> {
  late final ProfileSession _session =
      widget.session ?? getIt<ProfileSession>();
  bool _loading = false;
  bool _failed = false;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    if (!_session.loaded) _load();
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
  }

  Future<void> _open(HouseholdProfile profile) async {
    if (_opening != null) return;
    if (profile.hasPin) {
      final pin = await askProfilePin(context, _session, profile);
      if (pin == null || !mounted) return;
    }
    setState(() => _opening = profile.id);
    final switching = _session.active?.id != profile.id;
    await _session.activate(profile);
    if (!mounted) return;
    if (switching) {
      try {
        context.read<HomeBloc>().add(HomeLoad(silent: true));
      } catch (_) {}
      try {
        context.read<ProviderBloc>().add(const ProviderLoad());
      } catch (_) {}
    }
    context.go(afterProfilePick(widget.then));
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _session.profiles;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final avatar = wide ? 132.0 : 100.0;
    final Widget body;
    if (profiles.isEmpty && _loading) {
      body = Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (profiles.isEmpty) {
      body = _Failure(onRetry: _load, failed: _failed);
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          children: [
            Text(
              'profiles.who_watching'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: wide ? 34 : 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: wide ? 40 : 32),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: wide ? 28 : 18,
              runSpacing: 24,
              children: [
                for (var i = 0; i < profiles.length; i++)
                  _ProfileTile(
                    profile: profiles[i],
                    size: avatar,
                    autofocus: isTvPlatform && i == 0,
                    current: profiles[i].id == _session.active?.id,
                    busy: _opening == profiles[i].id,
                    onTap: () => _open(profiles[i]),
                  ),
                if (_session.canAdd && _session.canManage)
                  _AddTile(
                    size: avatar,
                    onTap: () => context.push('/profiles/edit'),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            if (_session.canManage)
              AppSecondaryButton(
                label: 'profiles.manage'.tr(),
                icon: Icons.edit_rounded,
                expand: false,
                onPressed: () => context.push('/profiles/manage'),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: context.canPop()
          ? AppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      body: SafeArea(child: Center(child: body)),
    );
  }
}

class _ProfileTile extends StatefulWidget {
  const _ProfileTile({
    required this.profile,
    required this.size,
    required this.onTap,
    this.autofocus = false,
    this.current = false,
    this.busy = false,
  });

  final HouseholdProfile profile;
  final double size;
  final VoidCallback onTap;
  final bool autofocus;
  final bool current;
  final bool busy;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return SizedBox(
      width: widget.size + 12,
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(widget.size * 0.24),
        onTap: widget.onTap,
        onFocusChange: (v) => setState(
          () => _focused =
              v &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional,
        ),
        onHover: (v) => setState(() => _focused = v),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: _focused ? 1.06 : 1,
                    duration: const Duration(milliseconds: 140),
                    child: ProfileAvatar.of(
                      p,
                      size: widget.size,
                      selected: _focused,
                    ),
                  ),
                  if (widget.busy)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.6,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _focused || widget.current
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: widget.current
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 12,
      child: InkWell(
        borderRadius: BorderRadius.circular(size * 0.24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(size * 0.22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: AppColors.textSecondary,
                  size: size * 0.42,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'profiles.add'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry, required this.failed});

  final VoidCallback onRetry;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_outline_rounded,
            color: AppColors.textSecondary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'profiles.load_failed'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: 6),
            Text(
              'profiles.offline'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
          AppPrimaryButton(
            label: 'general.retry'.tr(),
            expand: false,
            onPressed: onRetry,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/main'),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
