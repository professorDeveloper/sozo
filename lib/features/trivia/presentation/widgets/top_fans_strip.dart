import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/top_fan_entity.dart';

/// Medal accent colors for ranks 1..3. Semantic, not decorative — they come
/// from the shared medal tokens so the board and this strip cannot drift apart.
const List<Color> kMedalColors = [
  AppColors.medalGold,
  AppColors.medalSilver,
  AppColors.medalBronze,
];

/// Compact "Top Fans" preview strip for the Actor Hero: top-3 avatars with
/// medal rings + a "You: #rank" chip, the whole row tappable to open the full
/// Top Fans board.
class TopFansStrip extends StatelessWidget {
  const TopFansStrip({
    super.key,
    required this.topFans,
    required this.onTap,
    this.myRank,
    this.loading = false,
  });

  final List<TopFanEntity> topFans;
  final VoidCallback onTap;
  final int? myRank;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final top3 = topFans.take(3).toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              Icons.emoji_events_rounded,
              color: kMedalColors[0].withValues(alpha: 0.95),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'trivia.top_fans'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (loading)
                    const _StripSkeleton()
                  else if (top3.isEmpty)
                    Text(
                      'trivia.be_first_fan'.tr(),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    )
                  else
                    _AvatarRow(fans: top3),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (myRank != null) _MyRankChip(rank: myRank!),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.fans});
  final List<TopFanEntity> fans;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    const overlap = 26.0;
    return SizedBox(
      height: size + 6,
      width: overlap * (fans.length - 1) + size + 6,
      child: Stack(
        children: [
          for (int i = fans.length - 1; i >= 0; i--)
            Positioned(
              left: i * overlap,
              child: _MedalAvatar(fan: fans[i], size: size, rank: i + 1),
            ),
        ],
      ),
    );
  }
}

class _MedalAvatar extends StatelessWidget {
  const _MedalAvatar({
    required this.fan,
    required this.size,
    required this.rank,
  });

  final TopFanEntity fan;
  final double size;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final medal = kMedalColors[(rank - 1).clamp(0, 2)];
    return Container(
      width: size + 5,
      height: size + 5,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: medal, width: 2),
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: ColoredBox(
            color: AppColors.surfaceVariant,
            child: fan.avatar.trim().isEmpty
                ? _initial(fan.username)
                : CachedNetworkImage(
                    imageUrl: fan.avatar,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const ShimmerWrapper(
                      child: ColoredBox(color: Colors.white),
                    ),
                    errorWidget: (_, _, _) => _initial(fan.username),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _initial(String name) {
    return Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _MyRankChip extends StatelessWidget {
  const _MyRankChip({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(end: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'trivia.you_rank'.tr(namedArgs: {'rank': '$rank'}),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StripSkeleton extends StatelessWidget {
  const _StripSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ShimmerWrapper(
      child: Row(
        children: [
          _Dot(),
          SizedBox(width: 6),
          _Dot(),
          SizedBox(width: 6),
          _Dot(),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: SizedBox(width: 40, height: 40),
    );
  }
}
