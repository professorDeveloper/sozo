import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';
import 'package:soplay/features/auth/data/services/google_auth_service.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:soplay/features/onboarding/presentation/widgets/tv_pairing_panel.dart';

/// Sign in, sign up, or go on as a guest. Whichever way, the setup continues
/// from here rather than dropping the person on Home.
class OnboardingAccountPage extends StatefulWidget {
  const OnboardingAccountPage({super.key});

  @override
  State<OnboardingAccountPage> createState() => _OnboardingAccountPageState();
}

class _OnboardingAccountPageState extends State<OnboardingAccountPage> {
  bool _googlePending = false;
  bool _handled = false;

  bool get _isCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _google() {
    setState(() => _googlePending = true);
    context.read<AuthBloc>().add(const AuthGoogleRequested());
  }

  void _guest() => onboardingNext(context);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // The sign-in pages pushed over this one handle their own success.
        if (!_isCurrent) return;
        if (state is AuthLoaded && !_handled) {
          _handled = true;
          goAfterAuth(context);
        } else if (state is AuthError && _googlePending) {
          setState(() => _googlePending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
            ),
          );
        } else if (state is AuthInitial) {
          setState(() => _googlePending = false);
        }
      },
      child: OnboardingScaffold(
        step: OnboardingStep.account,
        maxBodyWidth: isTvPlatform ? 900 : 560,
        body: isTvPlatform
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: TvPairingPanel(onGuest: _guest),
              )
            : _PhoneBody(
                googlePending: _googlePending,
                onGoogle: _google,
                onGuest: _guest,
              ),
      ),
    );
  }
}

class _PhoneBody extends StatelessWidget {
  const _PhoneBody({
    required this.googlePending,
    required this.onGoogle,
    required this.onGuest,
  });

  final bool googlePending;
  final VoidCallback onGoogle;
  final VoidCallback onGuest;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final loading = state is AuthLoading;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 180, child: SyncOrbit()),
              const SizedBox(height: 12),
              OnboardingHeading(
                center: true,
                title: 'onboarding.account_title'.tr(),
                subtitle: 'onboarding.account_subtitle'.tr(),
              ),
              const SizedBox(height: 18),
              for (final (icon, key) in const [
                (Icons.sync_rounded, 'onboarding.account_perk_sync'),
                (Icons.download_rounded, 'onboarding.account_perk_import'),
                (Icons.group_rounded, 'onboarding.account_perk_profiles'),
              ])
                _Perk(icon: icon, text: key.tr()),
              const SizedBox(height: 20),
              if (GoogleAuthService.isSupported) ...[
                OnboardingFocusButton(
                  child: GoogleAuthButton(
                    loading: loading && googlePending,
                    onPressed: loading ? null : onGoogle,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              OnboardingFocusButton(
                autofocus: isDesktopPlatform,
                child: AppPrimaryButton(
                  label: 'onboarding.account_email'.tr(),
                  icon: Icons.mail_outline_rounded,
                  onPressed: loading ? null : () => context.push('/register'),
                ),
              ),
              const SizedBox(height: 6),
              OnboardingFocusButton(
                child: AppSecondaryButton(
                  label: 'onboarding.account_sign_in'.tr(),
                  onPressed: loading ? null : () => context.push('/login'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: OnboardingFocusButton(
                  child: TextButton(
                    onPressed: loading ? null : onGuest,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(
                      'onboarding.account_guest'.tr(),
                      style: TextStyle(
                        fontSize: OnbType.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: OnbType.body - 0.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Sozo mark with a phone, a television and a laptop circling it, joined
/// by threads of light — one account, every screen.
class SyncOrbit extends StatefulWidget {
  const SyncOrbit({super.key});

  @override
  State<SyncOrbit> createState() => _SyncOrbitState();
}

class _SyncOrbitState extends State<SyncOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  static const _devices = [
    Icons.smartphone_rounded,
    Icons.tv_rounded,
    Icons.laptop_mac_rounded,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.stop();
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final center = Offset(box.maxWidth / 2, box.maxHeight / 2);
          final rx = math.min(box.maxWidth * 0.36, 150.0);
          final ry = box.maxHeight * 0.36;
          return AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final positions = [
                for (var i = 0; i < _devices.length; i++)
                  () {
                    final a = _t.value * 2 * math.pi + i * 2 * math.pi / 3;
                    return center + Offset(math.cos(a) * rx, math.sin(a) * ry);
                  }(),
              ];
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OrbitPainter(
                        center: center,
                        rx: rx,
                        ry: ry,
                        points: positions,
                        phase: _t.value,
                        color: accent,
                      ),
                    ),
                  ),
                  Positioned(
                    left: center.dx - 36,
                    top: center.dy - 36,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: Center(child: SozoMark(size: 34, color: accent)),
                    ),
                  ),
                  for (var i = 0; i < positions.length; i++)
                    Positioned(
                      left: positions[i].dx - 22,
                      top: positions[i].dy - 22,
                      child: Transform.scale(
                        // Nearer the viewer at the bottom of the ellipse.
                        scale:
                            0.85 +
                            0.25 * ((positions[i].dy - center.dy) / ry + 1) / 2,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceVariant,
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: Icon(
                            _devices[i],
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({
    required this.center,
    required this.rx,
    required this.ry,
    required this.points,
    required this.phase,
    required this.color,
  });

  final Offset center;
  final double rx;
  final double ry;
  final List<Offset> points;
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.25);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      orbit,
    );
    final line = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final p in points) {
      final shader = LinearGradient(
        colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.05)],
      ).createShader(Rect.fromPoints(center, p));
      line.shader = shader;
      canvas.drawLine(center, p, line);
      // A pulse of light travelling out along each thread.
      final t = (phase * 6) % 1;
      final dot = Offset.lerp(center, p, t)!;
      canvas.drawCircle(
        dot,
        2.6,
        Paint()..color = color.withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.phase != phase;
}
