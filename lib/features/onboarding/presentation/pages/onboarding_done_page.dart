import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/localization/app_language.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/onboarding/data/genre_catalog.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/confetti.dart';
import 'package:soplay/features/onboarding/presentation/widgets/kind_style.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// The finish: confetti, a check drawing itself, and what was set up.
class OnboardingDonePage extends StatefulWidget {
  const OnboardingDonePage({super.key});

  @override
  State<OnboardingDonePage> createState() => _OnboardingDonePageState();
}

class _OnboardingDonePageState extends State<OnboardingDonePage> {
  final OnboardingController _c = getIt<OnboardingController>();
  late final Future<void> _saved;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _saved = _commit();
  }

  Future<void> _commit() async {
    await Future<void>.delayed(Duration.zero);
    if (mounted) await commitOnboardingTaste(context);
  }

  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    await _saved;
    if (mounted) await finishOnboarding(context);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _c.kinds;
    final firstRun = _c.flow == OnboardingFlow.firstRun;
    final colors = [
      AppColors.primary,
      AppColors.primaryLight,
      for (final k in kinds) k.accent,
      const Color(0xFFFFD166),
      Colors.white,
    ];
    final name = getIt<HiveService>().getUser()?.displayName;
    return Stack(
      children: [
        OnboardingScaffold(
          step: OnboardingStep.done,
          maxBodyWidth: 520,
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _DrawnCheck(color: AppColors.primary),
                const SizedBox(height: 24),
                OnboardingHeading(
                  center: true,
                  title: name == null || name.isEmpty
                      ? 'onboarding.done_title'.tr()
                      : 'onboarding.done_title_name'.tr(args: [name]),
                  subtitle: _c.flow == OnboardingFlow.profile
                      ? 'onboarding.done_subtitle_profile'.tr()
                      : 'onboarding.done_subtitle'.tr(),
                ),
                const SizedBox(height: 24),
                _Summary(controller: _c),
              ],
            ),
          ),
          footer: OnboardingFocusButton(
            autofocus: true,
            child: AppPrimaryButton(
              label: firstRun
                  ? 'onboarding.done_start'.tr()
                  : 'onboarding.done'.tr(),
              icon: firstRun ? Icons.play_arrow_rounded : null,
              onPressed: _finish,
            ),
          ),
        ),
        Positioned.fill(child: ConfettiBurst(colors: colors)),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final rows = <Widget>[
      if (c.kinds.isNotEmpty)
        _Row(
          icon: Icons.favorite_rounded,
          label: 'onboarding.summary_kinds'.tr(),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in c.kinds)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: k.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: k.accent.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(k.icon, size: 14, color: k.accent),
                      const SizedBox(width: 4),
                      Text(
                        k.labelKey.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (c.genres.isNotEmpty)
        _Row(
          icon: Icons.local_offer_rounded,
          label: 'onboarding.summary_genres'.tr(),
          text: _genresText(c),
        ),
      if (c.importedFollowed + c.importedListed > 0)
        _Row(
          icon: Icons.download_done_rounded,
          label: 'onboarding.summary_import'.tr(),
          text: 'onboarding.import_result'.tr(
            args: ['${c.importedFollowed}', '${c.importedListed}'],
          ),
        ),
      if (c.notificationsOn != null)
        _Row(
          icon: c.notificationsOn!
              ? Icons.notifications_active_rounded
              : Icons.notifications_off_rounded,
          label: 'onboarding.summary_notifications'.tr(),
          text: c.notificationsOn!
              ? 'onboarding.summary_on'.tr()
              : 'onboarding.summary_off'.tr(),
        ),
      if (c.flow == OnboardingFlow.firstRun)
        _Row(
          icon: Icons.translate_rounded,
          label: 'onboarding.summary_language'.tr(),
          text: AppLanguage.labelOf(context.locale.languageCode),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0x14FFFFFF)),
            rows[i],
          ],
        ],
      ),
    );
  }

  String _genresText(OnboardingController c) {
    final names = [for (final g in c.genres) genreDisplayName(g)];
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} +${names.length - 3}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.text, this.child});

  final IconData icon;
  final String label;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: OnbType.small - 1,
                  ),
                ),
                const SizedBox(height: 4),
                if (child != null)
                  child!
                else
                  Text(
                    text ?? '',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: OnbType.body - 0.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A ring closing and a check being written inside it.
class _DrawnCheck extends StatelessWidget {
  const _DrawnCheck({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: const Cubic(0.05, 0.7, 0.1, 1.0),
        builder: (context, t, _) => Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45 * t),
                blurRadius: 50,
              ),
            ],
          ),
          child: CustomPaint(painter: _CheckPainter(t, color)),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: 0.14 * t));
    final ring = (t / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5708,
      6.2832 * ring,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    final tick = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (tick <= 0) return;
    final path = Path()
      ..moveTo(c.dx - r * 0.38, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.1, c.dy + r * 0.3)
      ..lineTo(c.dx + r * 0.42, c.dy - r * 0.28);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * tick),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}
