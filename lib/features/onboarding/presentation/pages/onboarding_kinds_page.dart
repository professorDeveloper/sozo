import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/widgets/mode_destination_artwork.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/kind_style.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_tappable.dart';

/// "What do you enjoy?" — four large cards, pick any, at least one.
class OnboardingKindsPage extends StatefulWidget {
  const OnboardingKindsPage({super.key});

  @override
  State<OnboardingKindsPage> createState() => _OnboardingKindsPageState();
}

class _OnboardingKindsPageState extends State<OnboardingKindsPage> {
  final OnboardingController _c = getIt<OnboardingController>();

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final k in TasteKind.values) {
      for (final p in k.posters.take(3)) {
        precacheImage(ResizeImage(AssetImage(p), width: 300), context);
      }
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toggle(TasteKind kind) {
    HapticFeedback.selectionClick();
    _c.toggleKind(kind);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _c.kinds;
    return OnboardingScaffold(
      step: OnboardingStep.kinds,
      glow: kinds.isEmpty ? null : kinds.first.accent,
      onSkip: _c.flow == OnboardingFlow.profile
          ? null
          : () => onboardingNext(context),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 600 || box.maxWidth > box.maxHeight;
          final columns = wide ? 4 : 2;
          const gap = 12.0;
          const pad = 20.0;
          final cardW =
              (box.maxWidth - pad * 2 - gap * (columns - 1)) / columns;
          final rows = TasteKind.values.length ~/ columns;
          final headingRoom = 150 * MediaQuery.textScalerOf(context).scale(1);
          final fitH = (box.maxHeight - headingRoom - gap * (rows - 1)) / rows;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final minH = 150.0 + 40 * (scale - 1).clamp(0.0, 1.5);
          final cardH = math.max(minH, math.min(cardW * 1.28, fitH));
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(pad, 8, pad, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnboardingHeading(
                  title: 'onboarding.kinds_title'.tr(),
                  subtitle: 'onboarding.kinds_subtitle'.tr(),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (i, kind) in TasteKind.values.indexed)
                      SizedBox(
                        width: cardW,
                        height: cardH,
                        child: ItemAppear(
                          index: i,
                          columns: columns,
                          child: KindCard(
                            kind: kind,
                            selected: kinds.contains(kind),
                            primary: kinds.isNotEmpty && kinds.first == kind,
                            dimmed: kinds.isNotEmpty && !kinds.contains(kind),
                            autofocus: isTvPlatform && i == 0,
                            onTap: () => _toggle(kind),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      footer: OnboardingFocusButton(
        child: AppPrimaryButton(
          label: kinds.isEmpty
              ? 'onboarding.kinds_pick_one'.tr()
              : 'onboarding.continue'.tr(),
          onPressed: _c.canLeaveKinds ? () => onboardingNext(context) : null,
        ),
      ),
    );
  }
}

/// One kind, as a card of its own artwork. Selecting it lifts it, lights its
/// edge in the kind's colour and stamps a check in the corner.
class KindCard extends StatefulWidget {
  const KindCard({
    super.key,
    required this.kind,
    required this.selected,
    required this.onTap,
    this.primary = false,
    this.dimmed = false,
    this.autofocus = false,
  });

  final TasteKind kind;
  final bool selected;
  final bool primary;
  final bool dimmed;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<KindCard> createState() => _KindCardState();
}

class _KindCardState extends State<KindCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 260),
    value: widget.selected ? 1 : 0,
  );
  late final Animation<double> _sel = CurvedAnimation(
    parent: _t,
    curve: const Cubic(0.05, 0.7, 0.1, 1.0),
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: _t,
    curve: const Interval(0.15, 1, curve: Curves.easeOutBack),
  );

  @override
  void didUpdateWidget(KindCard old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = widget.selected ? 1 : 0;
    } else {
      widget.selected ? _t.forward() : _t.reverse();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final accent = kind.accent;
    return OnboardingTappable(
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      borderRadius: 22,
      selected: widget.selected,
      ringColor: accent,
      semanticLabel: '${kind.labelKey.tr()}. ${kind.hintKey.tr()}',
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) {
          final s = _sel.value;
          return Transform.scale(
            scale: 0.965 + 0.035 * s,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5 * s),
                    blurRadius: 28 * s,
                    spreadRadius: 1 * s,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    // Unpicked cards step back once something is picked, so
                    // the choice reads at a glance.
                    AnimatedOpacity(
                      opacity: widget.dimmed ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const ColoredBox(color: Color(0x66000000)),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Color.lerp(
                            Colors.white.withValues(alpha: 0.08),
                            accent,
                            s,
                          )!,
                          width: 1 + 1.5 * s,
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 10,
                      end: 10,
                      child: Transform.scale(
                        scale: _pop.value.clamp(0.0, 1.2),
                        child: _Check(color: accent),
                      ),
                    ),
                    if (widget.primary)
                      PositionedDirectional(
                        top: 12,
                        start: 12,
                        child: FadeTransition(
                          opacity: _sel,
                          child: _PrimaryTag(color: accent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        child: RepaintBoundary(child: _CardFace(kind: kind)),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.kind});

  final TasteKind kind;

  @override
  Widget build(BuildContext context) {
    final accent = kind.accent;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(AppColors.surface, accent, 0.28)!,
                AppColors.surface,
              ],
            ),
          ),
        ),
        switch (kind) {
          TasteKind.anime || TasteKind.movies => _PosterFan(
            posters: kind.posters.take(3).toList(),
          ),
          TasteKind.manga => _DrawnArt(
            kind: kind,
            painter: _HalftonePainter(accent),
          ),
          TasteKind.novels => _DrawnArt(
            kind: kind,
            painter: _RuledPainter(accent),
          ),
        },
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x00000000), Color(0xE6000000)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(kind.icon, color: accent, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        kind.labelKey.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: OnbType.label + 2,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  kind.hintKey.tr(),
                  maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3
                      ? 1
                      : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xCCFFFFFF),
                    fontSize: OnbType.small - 1,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three posters fanned out like a hand of cards.
class _PosterFan extends StatelessWidget {
  const _PosterFan({required this.posters});

  final List<String> posters;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth * 0.42;
        final h = w * 1.45;
        const angles = [-0.2, 0.2, 0.0];
        const shifts = [-0.52, 0.52, 0.0];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < posters.length && i < 3; i++)
              Positioned(
                left: box.maxWidth / 2 - w / 2 + shifts[i] * w,
                top: box.maxHeight * 0.1 + (i == 2 ? 0 : h * 0.08),
                width: w,
                height: h,
                child: Transform.rotate(
                  angle: angles[i],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        posters[i],
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DrawnArt extends StatelessWidget {
  const _DrawnArt({required this.kind, required this.painter});

  final TasteKind kind;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: painter),
        Align(
          alignment: const Alignment(0, -0.35),
          child: FractionallySizedBox(
            widthFactor: 0.62,
            child: AspectRatio(
              aspectRatio: 1,
              child: ModeDestinationArtwork(
                mode: kind.mode,
                color: kind.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Screentone dots, the texture a printed manga page is made of.
class _HalftonePainter extends CustomPainter {
  const _HalftonePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.22);
    const step = 11.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (
        var x = (y ~/ step).isEven ? 0.0 : step / 2;
        x < size.width;
        x += step
      ) {
        final r = 1.1 + 2.2 * (1 - (y / size.height)).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) => old.color != color;
}

/// Ruled lines, as on the page of a book.
class _RuledPainter extends CustomPainter {
  const _RuledPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var y = 18.0; y < size.height; y += 16) {
      canvas.drawLine(Offset(14, y), Offset(size.width - 14, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RuledPainter old) => old.color != color;
}

class _Check extends StatelessWidget {
  const _Check({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10),
        ],
      ),
      child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
    );
  }
}

class _PrimaryTag extends StatelessWidget {
  const _PrimaryTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(
        'onboarding.kinds_starts_here'.tr(),
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: OnbType.small - 2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
