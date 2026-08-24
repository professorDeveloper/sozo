import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';

/// The off-screen, fixed-size card that gets rasterized (RepaintBoundary →
/// toImage) and shared. It is deliberately self-contained and `const`-friendly
/// so it renders identically regardless of the surrounding layout.
///
/// [actorImage] is passed pre-resolved (an already-loaded [ImageProvider]) so
/// the boundary can be captured synchronously without waiting on the network.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.result,
    this.actor,
    this.actorImage,
  });

  final TriviaResultEntity result;
  final ActorRefEntity? actor;
  final ImageProvider? actorImage;

  static const double width = 380;
  static const double height = 520;

  @override
  Widget build(BuildContext context) {
    // Every Buff round is a fan test, so the card always leads with fandom %.
    final headline = '${result.fandomPercent.round()}%';
    final headlineLabel = 'trivia.fandom'.tr();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              AppColors.primaryDark.withValues(alpha: 0.25),
              AppColors.background,
            ),
            AppColors.background,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.movie_filter_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'BUFF',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _Avatar(actor: actor, image: actorImage),
            const SizedBox(height: 20),
            Text(
              headline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              headlineLabel.toUpperCase(),
              style: TextStyle(
                color: AppColors.primaryLight,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MiniStat(
                  // Rounds are not always 10 clips long — the denominator is
                  // the round's own length, or hidden when the server omits it.
                  value: result.hasTotal
                      ? '${result.correctCount}/${result.totalClips}'
                      : '${result.correctCount}',
                  label: 'trivia.correct'.tr(),
                ),
                Container(
                  width: 1,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                _MiniStat(
                  value: '#${result.rank}',
                  label: 'trivia.rank'.tr(),
                ),
              ],
            ),
            const Spacer(),
            if (actor != null)
              Text(
                actor!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'trivia.share_tagline'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.actor, this.image});

  final ActorRefEntity? actor;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary, width: 3),
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      child: image == null
          ? const Icon(Icons.person_rounded, color: Colors.white38, size: 52)
          : null,
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
