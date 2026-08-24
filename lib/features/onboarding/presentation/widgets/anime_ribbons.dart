import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/onboarding/data/onboarding_posters.dart';

const double _gap = 6;
const double _coverRatio = 2 / 3;
const List<double> _speeds = [1.0, 0.74, 1.22, 0.9, 1.1];

/// Anime covers sliding sideways in alternating rows.
///
/// Deliberately not the poster wall with different pictures: the anime slide
/// has to look like a different part of the app, and a wall that only swaps its
/// artwork reads as the same slide again. Rows moving against each other also
/// echo the shelves the catalogue itself is laid out in.
class AnimeRibbons extends StatefulWidget {
  const AnimeRibbons({super.key, this.rows = 6, this.tilesPerRow = 11});

  final int rows;
  final int tilesPerRow;

  @override
  State<AnimeRibbons> createState() => _AnimeRibbonsState();
}

class _AnimeRibbonsState extends State<AnimeRibbons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 48),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _coversFor(int row) => [
    for (var i = 0; i < widget.tilesPerRow; i++)
      kAnimePosters[(row + i * widget.rows) % kAnimePosters.length],
  ];

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rowHeight =
              (constraints.maxHeight - _gap * (widget.rows - 1)) / widget.rows;
          final tileWidth = rowHeight * _coverRatio;
          final strip = (tileWidth + _gap) * widget.tilesPerRow;

          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.4, 1],
            ).createShader(rect),
            child: Column(
              children: [
                for (var r = 0; r < widget.rows; r++) ...[
                  if (r > 0) const SizedBox(height: _gap),
                  SizedBox(
                    height: rowHeight,
                    child: _Ribbon(
                      controller: _controller,
                      covers: _coversFor(r),
                      // Odd rows travel the other way. Everything drifting the
                      // same direction looks like one sheet being dragged.
                      reverse: r.isOdd,
                      speed: _speeds[r % _speeds.length],
                      strip: strip,
                      tileWidth: tileWidth,
                      tileHeight: rowHeight,
                      phase: r / widget.rows,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({
    required this.controller,
    required this.covers,
    required this.reverse,
    required this.speed,
    required this.strip,
    required this.tileWidth,
    required this.tileHeight,
    required this.phase,
  });

  final AnimationController controller;
  final List<String> covers;
  final bool reverse;
  final double speed;
  final double strip;
  final double tileWidth;
  final double tileHeight;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return ClipRect(
      // The strip is wider than the row by design, so it has to be measured
      // unbounded — inside the row's constraints it would overflow every frame.
      child: OverflowBox(
        maxWidth: double.infinity,
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final t = (controller.value * speed + phase) % 1.0;
            final dx = reverse ? -t * strip : t * strip - strip;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var pass = 0; pass < 2; pass++)
                for (final cover in covers)
                  Padding(
                    padding: const EdgeInsets.only(right: _gap),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        cover,
                        width: tileWidth,
                        height: tileHeight,
                        fit: BoxFit.cover,
                        cacheWidth: (tileWidth * devicePixelRatio).round(),
                        errorBuilder: (_, _, _) => SizedBox(
                          width: tileWidth,
                          height: tileHeight,
                          child: ColoredBox(color: AppColors.surface),
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
