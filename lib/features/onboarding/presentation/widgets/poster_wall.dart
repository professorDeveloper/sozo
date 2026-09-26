import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/onboarding/data/onboarding_posters.dart';

/// Columns of posters drifting downwards behind the onboarding and auth copy.
///
/// Each column carries the same strip twice and is translated by less than one
/// strip height, so the loop closes on itself and never shows a seam. The
/// columns run at different speeds — identical speeds read as one sliding
/// image rather than a wall of titles.
class PosterWall extends StatefulWidget {
  const PosterWall({
    super.key,
    this.posters = kMoviePosters,
    this.columns = 5,
    this.tilesPerColumn = 11,
    this.fadeTop = false,
    this.fadeBottom = true,
  });

  final List<String> posters;
  final int columns;
  final int tilesPerColumn;

  /// Fades the top edge instead of only the bottom — what the auth headers
  /// want, where the wall sits under a top bar.
  final bool fadeTop;

  /// Off where the page already fades the wall into its background: the mask
  /// is a full-screen offscreen pass on every frame of the drift.
  final bool fadeBottom;

  @override
  State<PosterWall> createState() => _PosterWallState();
}

class _PosterWallState extends State<PosterWall>
    with SingleTickerProviderStateMixin {
  static const _cycle = Duration(seconds: 54);
  static const _speeds = [1.0, 0.72, 1.28, 0.86];
  static const _gap = 6.0;
  static const _posterRatio = 2 / 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _postersFor(int column) {
    final out = <String>[];
    for (var i = 0; i < widget.tilesPerColumn; i++) {
      out.add(
        widget.posters[(column + i * widget.columns) % widget.posters.length],
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth =
              (constraints.maxWidth - _gap * (widget.columns - 1)) /
              widget.columns;
          final tileHeight = tileWidth / _posterRatio;
          final strip = (tileHeight + _gap) * widget.tilesPerColumn;

          final wall = SizedBox(
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < widget.columns; c++) ...[
                  if (c > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: _PosterColumn(
                      controller: _controller,
                      posters: _postersFor(c),
                      speed: _speeds[c % _speeds.length],
                      strip: strip,
                      tileHeight: tileHeight,
                      tileWidth: tileWidth,
                      // Staggering the start stops every column from
                      // beginning on the same row of the wall.
                      phase: c / widget.columns,
                    ),
                  ),
                ],
              ],
            ),
          );
          if (!widget.fadeTop && !widget.fadeBottom) return wall;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                widget.fadeTop ? Colors.transparent : Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: const [0, 0.35, 1],
            ).createShader(rect),
            child: wall,
          );
        },
      ),
    );
  }
}

class _PosterColumn extends StatelessWidget {
  const _PosterColumn({
    required this.controller,
    required this.posters,
    required this.speed,
    required this.strip,
    required this.tileHeight,
    required this.tileWidth,
    required this.phase,
  });

  final AnimationController controller;
  final List<String> posters;
  final double speed;
  final double strip;
  final double tileHeight;
  final double tileWidth;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return ClipRect(
      // The strip is taller than the column on purpose, so it has to be laid
      // out unbounded — inside the parent's constraints it would report an
      // overflow on every frame instead of scrolling.
      child: OverflowBox(
        maxHeight: double.infinity,
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final t = (controller.value * speed + phase) % 1.0;
            return Transform.translate(
              offset: Offset(0, t * strip - strip),
              child: child,
            );
          },
          // Its own layer: each frame moves the recorded strip instead of
          // re-recording two dozen clipped posters.
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var pass = 0; pass < 2; pass++)
                  for (final poster in posters)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: _PosterWallState._gap,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          poster,
                          width: tileWidth,
                          height: tileHeight,
                          fit: BoxFit.cover,
                          cacheWidth: (tileWidth * devicePixelRatio).round(),
                          // The wall is decoration; a missing file must not take
                          // the sign-in screen down with it.
                          errorBuilder: (_, _, _) => Container(
                            width: tileWidth,
                            height: tileHeight,
                            color: AppColors.surface,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
