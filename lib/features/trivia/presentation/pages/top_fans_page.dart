import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/actor_fan_stat_entity.dart';
import 'package:soplay/features/trivia/domain/entities/top_fan_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_state.dart';
import 'package:soplay/features/trivia/presentation/widgets/top_fans_strip.dart' show kMedalColors;

/// Full ranked Top Fans board for one actor/character: medals for the top 3,
/// fandom % + best score per fan, and the current user's row pinned + highlighted.
class TopFansPage extends StatelessWidget {
  const TopFansPage({super.key, required this.actorId, this.kind = 'person'});

  final int actorId;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TopFansBloc>(
      create: (_) => getIt<TopFansBloc>()
        ..add(TopFansRequested(actorId: actorId, kind: kind)),
      child: _TopFansView(actorId: actorId, kind: kind),
    );
  }
}

class _TopFansView extends StatelessWidget {
  const _TopFansView({required this.actorId, required this.kind});

  final int actorId;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final myId = _currentUserId();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'trivia.top_fans'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: BlocBuilder<TopFansBloc, TopFansState>(
        builder: (context, state) {
          switch (state.status) {
            case TopFansStatus.initial:
            case TopFansStatus.loading:
              return const _FansSkeleton();
            case TopFansStatus.error:
              return _ErrorView(
                message: state.message,
                onRetry: () => context.read<TopFansBloc>().add(
                      TopFansRequested(actorId: actorId, kind: kind),
                    ),
              );
            case TopFansStatus.loaded:
              return _LoadedView(fanStat: state.fanStat, myId: myId);
          }
        },
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.fanStat, required this.myId});

  final ActorFanStatEntity? fanStat;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final fans = fanStat?.topFans ?? const <TopFanEntity>[];
    if (fans.isEmpty) {
      return _ErrorView(
        message: 'trivia.no_fans_yet'.tr(),
        icon: CupertinoIcons.star,
      );
    }

    TopFanEntity? mine;
    if (myId != null) {
      for (final f in fans) {
        if (f.userId == myId) {
          mine = f;
          break;
        }
      }
    }

    return Column(
      children: [
        if (fanStat != null) _ActorMiniHeader(fanStat: fanStat!),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: fans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _FanRow(
              fan: fans[i],
              isMe: fans[i].userId == myId,
            ),
          ),
        ),
        if (mine != null) _PinnedMyRow(fan: mine),
      ],
    );
  }
}

class _ActorMiniHeader extends StatelessWidget {
  const _ActorMiniHeader({required this.fanStat});
  final ActorFanStatEntity fanStat;

  @override
  Widget build(BuildContext context) {
    // Older fan-stat documents carry no name/profile, so the identity block is
    // dropped entirely rather than rendered as blank space; the meta line still
    // stands on its own.
    final hasName = fanStat.name.trim().isNotEmpty;
    final hasPhoto = fanStat.profileUrl.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (hasPhoto || hasName) ...[
            _Avatar(url: fanStat.profileUrl, name: fanStat.name, size: 52),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasName) ...[
                  Text(
                    fanStat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  'trivia.fans_meta'.tr(namedArgs: {
                    'rounds': '${fanStat.roundsPlayed}',
                    'fandom': fanStat.avgFandom.toStringAsFixed(0),
                  }),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
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

class _FanRow extends StatelessWidget {
  const _FanRow({required this.fan, required this.isMe});

  final TopFanEntity fan;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.primary.withValues(alpha: 0.14)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? AppColors.primary : AppColors.border,
          width: isMe ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          RankBadge(rank: fan.rank),
          const SizedBox(width: 12),
          _Avatar(url: fan.avatar, name: fan.username, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? 'trivia.you'.tr() : fan.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'trivia.best_score'.tr(namedArgs: {'score': '${fan.bestScore}'}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _FandomBadge(percent: fan.bestFandom),
        ],
      ),
    );
  }
}

class _PinnedMyRow extends StatelessWidget {
  const _PinnedMyRow({required this.fan});
  final TopFanEntity fan;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomSafe),
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: _FanRow(fan: fan, isMe: true),
    );
  }
}

class _FandomBadge extends StatelessWidget {
  const _FandomBadge({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${percent.toStringAsFixed(0)}%',
          style: TextStyle(
            color: AppColors.primaryLight,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          'trivia.fandom'.tr(),
          style: const TextStyle(color: AppColors.textHint, fontSize: 10),
        ),
      ],
    );
  }
}

/// Rank badge: a medal disc for the top 3, a plain number otherwise. Shared
/// visual language with the leaderboard board.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final isMedal = rank >= 1 && rank <= 3;
    final color = isMedal ? kMedalColors[rank - 1] : AppColors.surfaceVariant;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMedal ? color.withValues(alpha: 0.2) : Colors.transparent,
        border: Border.all(
          color: isMedal ? color : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: isMedal ? color : AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, required this.size});
  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: AppColors.surfaceVariant,
          child: url.trim().isEmpty
              ? _fallback()
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      const ShimmerWrapper(child: ColoredBox(color: Colors.white)),
                  errorWidget: (_, _, _) => _fallback(),
                ),
        ),
      ),
    );
  }

  Widget _fallback() {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

class _FansSkeleton extends StatelessWidget {
  const _FansSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 8,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const ShimmerWrapper(
        child: HomeSkeletonBox(width: double.infinity, height: 64, radius: 14),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    this.message,
    this.onRetry,
    this.icon = CupertinoIcons.exclamationmark_triangle,
  });

  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textHint, size: 44),
            const SizedBox(height: 14),
            Text(
              message?.isNotEmpty == true
                  ? message!
                  : 'trivia.something_wrong'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onRetry,
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
                child: Text('general.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _currentUserId() {
  final state = getIt<AuthBloc>().state;
  return state is AuthLoaded ? state.token.user.id : null;
}
