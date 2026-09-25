import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/kind_style.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';

/// Why notifications are worth allowing, shown as the notification itself —
/// with a title this person actually follows when there is one — before the
/// system asks.
class OnboardingNotificationsPage extends StatefulWidget {
  const OnboardingNotificationsPage({super.key});

  @override
  State<OnboardingNotificationsPage> createState() =>
      _OnboardingNotificationsPageState();
}

class _OnboardingNotificationsPageState
    extends State<OnboardingNotificationsPage> {
  final OnboardingController _c = getIt<OnboardingController>();
  bool _asking = false;

  ({String title, String? network, String asset}) get _sample {
    final kind = _c.kinds.isEmpty ? TasteKind.anime : _c.kinds.first;
    final asset = kind.posters.first;
    try {
      final followed = getIt<FollowService>().list();
      for (final f in followed) {
        if (f.thumbnail.isNotEmpty && f.title.isNotEmpty) {
          return (title: f.title, network: f.thumbnail, asset: asset);
        }
      }
    } catch (_) {}
    return (title: '', network: null, asset: asset);
  }

  Future<void> _allow() async {
    if (_asking) return;
    setState(() => _asking = true);
    // Setting the plugin up can throw; left unanswered, both buttons stay
    // disabled and the step cannot be left.
    var granted = false;
    try {
      granted = await getIt<NotificationService>().requestPermission();
    } catch (_) {}
    await _c.recordNotifications(granted);
    if (!mounted) return;
    setState(() => _asking = false);
    await onboardingNext(context);
  }

  Future<void> _later() async {
    await _c.recordNotifications(false);
    if (mounted) await onboardingNext(context);
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    return OnboardingScaffold(
      step: OnboardingStep.notifications,
      maxBodyWidth: 520,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            const SizedBox(height: 120, child: _Bell()),
            const SizedBox(height: 12),
            _MockNotification(
              title: sample.title.isEmpty
                  ? 'onboarding.notify_mock_title_generic'.tr()
                  : 'onboarding.notify_mock_title'.tr(args: [sample.title]),
              body: 'onboarding.notify_mock_body'.tr(),
              network: sample.network,
              asset: sample.asset,
            ),
            const SizedBox(height: 28),
            OnboardingHeading(
              center: true,
              title: 'onboarding.notify_title'.tr(),
              subtitle: 'onboarding.notify_body'.tr(),
            ),
          ],
        ),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardingFocusButton(
            autofocus: true,
            child: AppPrimaryButton(
              label: 'onboarding.notify_allow'.tr(),
              icon: Icons.notifications_active_rounded,
              loading: _asking,
              onPressed: _allow,
            ),
          ),
          const SizedBox(height: 4),
          OnboardingFocusButton(
            child: TextButton(
              onPressed: _asking ? null : _later,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                minimumSize: const Size(0, 44),
              ),
              child: Text('onboarding.notify_later'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bell that rings every few seconds, with rings of sound spreading out.
class _Bell extends StatefulWidget {
  const _Bell();

  @override
  State<_Bell> createState() => _BellState();
}

class _BellState extends State<_Bell> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

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
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final v = _t.value;
          // The swing lives in the first half; a damped sine that settles.
          final swing = v < 0.5
              ? math.sin(v * 2 * math.pi * 4) * 0.35 * (1 - v * 2)
              : 0.0;
          return CustomPaint(
            painter: _RingsPainter(progress: v, color: accent),
            child: Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: swing,
                  alignment: const Alignment(0, -0.6),
                  child: Icon(
                    Icons.notifications_rounded,
                    size: 44,
                    color: accent,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final t = ((progress - i * 0.18) / 0.6).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      canvas.drawCircle(
        center,
        42 + t * 40,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - t) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.progress != progress;
}

/// A heads-up notification as the system would draw it, sliding in.
class _MockNotification extends StatelessWidget {
  const _MockNotification({
    required this.title,
    required this.body,
    required this.network,
    required this.asset,
  });

  final String title;
  final String body;
  final String? network;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final fallback = Image.asset(asset, fit: BoxFit.cover, cacheWidth: 120);
    final poster = network == null
        ? fallback
        : CachedNetworkImage(
            imageUrl: network!,
            fit: BoxFit.cover,
            memCacheWidth: 120,
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: const Cubic(0.05, 0.7, 0.1, 1.0),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -40 * (1 - t)),
          child: child,
        ),
      ),
      child: Semantics(
        label: '$title. $body',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x1FFFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Center(
                              child: SozoMark(size: 11, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Sozo · ${'onboarding.notify_now'.tr()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 48, height: 68, child: poster),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
