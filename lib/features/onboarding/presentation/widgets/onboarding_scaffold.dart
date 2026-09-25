import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';

/// Type sizes for the setup, a notch larger on a television across the room.
class OnbType {
  OnbType._();

  static double get _k => isTvPlatform ? 1.2 : 1.0;
  static double get title => 28 * _k;
  static double get body => 15 * _k;
  static double get label => 16 * _k;
  static double get small => 13 * _k;
}

/// The frame every setup step sits in: back, progress and skip along the top,
/// the step's own content, and its actions pinned underneath.
class OnboardingScaffold extends StatefulWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.body,
    this.footer,
    this.onSkip,
    this.skipLabel,
    this.background,
    this.glow,
    this.maxBodyWidth = 720,
    this.showTopBar = true,
  });

  final OnboardingStep step;
  final Widget body;
  final Widget? footer;
  final VoidCallback? onSkip;
  final String? skipLabel;

  /// Painted full-bleed behind everything.
  final Widget? background;

  /// A soft wash of colour from the top edge.
  final Color? glow;
  final double maxBodyWidth;
  final bool showTopBar;

  @override
  State<OnboardingScaffold> createState() => _OnboardingScaffoldState();
}

class _OnboardingScaffoldState extends State<OnboardingScaffold> {
  final OnboardingController _c = getIt<OnboardingController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.arrive(widget.step));
  }

  void _back() => onboardingBack(context);

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow ?? AppColors.primary;
    final firstOfFirstRun =
        _c.flow == OnboardingFlow.firstRun && _c.isFirstStep;
    final media = MediaQuery.of(context);
    final content = Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ?widget.background,
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.2),
                  radius: 1.1,
                  colors: [
                    glow.withValues(alpha: 0.22),
                    glow.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (widget.showTopBar)
                  OnboardingTopBar(
                    progress: _c.active ? _c.progress : 1,
                    onBack: firstOfFirstRun ? null : _back,
                    onSkip: widget.onSkip,
                    skipLabel: widget.skipLabel,
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.maxBodyWidth,
                      ),
                      child: widget.body,
                    ),
                  ),
                ),
                if (widget.footer case final footer?)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      media.viewInsets.bottom > 0 ? 8 : 16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: footer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: firstOfFirstRun,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {
          if (!firstOfFirstRun)
            const SingleActivator(LogicalKeyboardKey.escape): _back,
        },
        child: FocusTraversalGroup(child: content),
      ),
    );
  }
}

class OnboardingTopBar extends StatelessWidget {
  const OnboardingTopBar({
    super.key,
    required this.progress,
    required this.onBack,
    this.onSkip,
    this.skipLabel,
  });

  final double progress;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final String? skipLabel;

  static double _shown = 0;

  @override
  Widget build(BuildContext context) {
    final from = _shown;
    _shown = progress;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 8, 4),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: onBack == null
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: AppColors.textPrimary,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Semantics(
                      label: 'onboarding.progress_label'.tr(
                        args: ['${(progress * 100).round()}'],
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: from, end: progress),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 600),
                        curve: const Cubic(0.05, 0.7, 0.1, 1.0),
                        builder: (context, value, _) =>
                            _ProgressTrack(value: value),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, maxWidth: 150),
                child: onSkip == null
                    ? null
                    : TextButton(
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          minimumSize: const Size(48, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text(
                          skipLabel ?? 'onboarding.skip'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: OnbType.small,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: (c.maxWidth * value.clamp(0.04, 1.0)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A step's heading block.
class OnboardingHeading extends StatelessWidget {
  const OnboardingHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.center = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: align,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: OnbType.title,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: align,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: OnbType.body,
              height: 1.45,
            ),
          ),
        ],
        if (trailing != null) ...[const SizedBox(height: 14), trailing!],
      ],
    );
  }
}
