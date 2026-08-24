import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/onboarding/data/onboarding_posters.dart';

/// The third backdrop: the app on a television, the channels it carries, and a
/// phone driving it.
///
/// The first two slides are walls of artwork that scroll. A third wall would
/// have read as the same slide again, so this one builds a scene: live TV and
/// pairing are the two things people never guess the app can do, and neither
/// of them looks like a poster.
class TvShowcase extends StatefulWidget {
  const TvShowcase({super.key});

  @override
  State<TvShowcase> createState() => _TvShowcaseState();
}

class _TvShowcaseState extends State<TvShowcase> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  // The line-up gets its own clock. On the screen's 9-second loop a strip of
  // forty marks flies past far too fast to read a single one.
  late final AnimationController _strips = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 78),
  )..repeat();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  @override
  void dispose() {
    _loop.dispose();
    _strips.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Animation<double> _step(double start) => CurvedAnimation(
    parent: _entrance,
    curve: Interval(
      start,
      (start + 0.5).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 66, 18, 0),
          child: Column(
            children: [
              // The set assembles itself: screen, then the line-up it carries,
              // then the phone that drives it — the order the sentence reads in.
              _Rise(
                animation: _step(0),
                from: 26,
                child: _Television(controller: _loop),
              ),
              _Rise(animation: _step(0.1), from: 20, child: const _Stand()),
              const SizedBox(height: 30),
              _Rise(
                animation: _step(0.24),
                from: 22,
                child: _ChannelStrip(
                  controller: _strips,
                  reverse: false,
                  speed: 1,
                ),
              ),
              const SizedBox(height: 9),
              _Rise(
                animation: _step(0.34),
                from: 22,
                child: _ChannelStrip(
                  controller: _strips,
                  reverse: true,
                  speed: 0.78,
                  offset: 0.33,
                ),
              ),
              const SizedBox(height: 9),
              _Rise(
                animation: _step(0.44),
                from: 22,
                child: _ChannelStrip(
                  controller: _strips,
                  reverse: false,
                  speed: 0.91,
                  offset: 0.66,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade-and-lift, the one entrance every part of this scene uses.
class _Rise extends StatelessWidget {
  const _Rise({
    required this.animation,
    required this.from,
    required this.child,
  });

  final Animation<double> animation;
  final double from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, (1 - animation.value) * from),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _Television extends StatelessWidget {
  const _Television({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9.4,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1.4),
          boxShadow: const [
            // Two shadows: one grounds the set, the faint wide one is the
            // screen bleeding onto the wall behind it.
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 26,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Color(0x1AFFFFFF),
              blurRadius: 60,
              spreadRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ScreenContent(controller: controller),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
                    stops: [0, 0.55],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: _LiveBadge(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The set changing channels: stills cross-fading, each drifting slightly so
/// no frame is ever a still photograph.
class _ScreenContent extends StatelessWidget {
  const _ScreenContent({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final width = (constraints.maxWidth * devicePixelRatio).round();

        return ColoredBox(
          color: AppColors.background,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final span = controller.value * kScreenStills.length;
              final index = span.floor() % kScreenStills.length;
              final within = span - span.floor();
              // A short dissolve at the end of each hold, so the change is a
              // channel switch and not a slideshow cut.
              final fade = ((within - 0.82) / 0.18).clamp(0.0, 1.0);

              Widget still(int i, double opacity, double progress) => Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: 1.04 + progress * 0.06,
                  child: Image.asset(
                    kScreenStills[i % kScreenStills.length],
                    fit: BoxFit.cover,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    cacheWidth: width,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: AppColors.surface),
                  ),
                ),
              );

              return Stack(
                fit: StackFit.expand,
                children: [
                  still(index, 1, within),
                  if (fade > 0) still(index + 1, fade, 0),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: controller,
              // A steady dot reads as a decal; the pulse is what says the feed
              // is arriving right now.
              builder: (context, _) {
                final pulse = (controller.value * 3) % 1.0;
                return Opacity(
                  opacity: 0.45 + 0.55 * (1 - pulse),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 5),
            const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stand extends StatelessWidget {
  const _Stand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: 14, height: 14, color: AppColors.divider),
        Container(
          width: 86,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
  }
}

/// The line-up, drifting past. Two of these run against each other, which is
/// what a channel list feels like to scroll.
class _ChannelStrip extends StatelessWidget {
  const _ChannelStrip({
    required this.controller,
    required this.reverse,
    required this.speed,
    this.offset = 0,
  });

  static const _tileWidth = 84.0;
  static const _tileHeight = 44.0;
  static const _gap = 8.0;

  final AnimationController controller;
  final bool reverse;
  final double speed;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final ordered = reverse ? kChannelLogos.reversed.toList() : kChannelLogos;
    final pivot = (ordered.length * offset).round() % ordered.length;
    final logos = [...ordered.sublist(pivot), ...ordered.sublist(0, pivot)];
    final strip = (_tileWidth + _gap) * logos.length;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return SizedBox(
      height: _tileHeight,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.12, 0.88, 1],
        ).createShader(rect),
        child: ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                // Wrapped rather than scaled, so a slower row still closes its
                // own loop without a jump.
                final t = (controller.value * speed) % 1.0;
                return Transform.translate(
                  offset: Offset(reverse ? t * strip - strip : -t * strip, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var pass = 0; pass < 2; pass++)
                    for (final logo in logos)
                      Padding(
                        padding: const EdgeInsets.only(right: _gap),
                        child: Container(
                          width: _tileWidth,
                          height: _tileHeight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Image.asset(
                            logo,
                            fit: BoxFit.contain,
                            cacheWidth: (_tileWidth * devicePixelRatio).round(),
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
