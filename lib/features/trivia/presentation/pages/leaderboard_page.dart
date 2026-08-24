import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/leaderboard/leaderboard_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/leaderboard/leaderboard_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/leaderboard/leaderboard_state.dart';
import 'package:soplay/features/trivia/presentation/pages/top_fans_page.dart' show RankBadge;

/// Global leaderboard with daily / weekly / all-time / friends scope tabs. The
/// current user's row is highlighted inline and pinned to the bottom.
class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({
    super.key,
    this.initialScope = 'daily',
    this.mode,
    this.actorId,
  });

  final String initialScope;
  final String? mode;
  final int? actorId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LeaderboardBloc>(
      create: (_) => getIt<LeaderboardBloc>()
        ..add(LeaderboardStarted(
          scope: initialScope,
          mode: mode,
          actorId: actorId,
        )),
      child: const _LeaderboardView(),
    );
  }
}

/// (value, i18n key) pairs for the scope selector.
const List<(String, String)> _scopes = [
  ('daily', 'trivia.scope_daily'),
  ('weekly', 'trivia.scope_weekly'),
  ('all', 'trivia.scope_all_time'),
  ('friends', 'trivia.scope_friends'),
];

class _LeaderboardView extends StatelessWidget {
  const _LeaderboardView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'trivia.leaderboard'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          const _ScopeTabs(),
          Expanded(
            child: BlocBuilder<LeaderboardBloc, LeaderboardState>(
              builder: (context, state) {
                switch (state.status) {
                  case LeaderboardStatus.initial:
                  case LeaderboardStatus.loading:
                    return const _BoardSkeleton();
                  case LeaderboardStatus.error:
                    return _ErrorView(
                      message: state.message,
                      onRetry: () => context
                          .read<LeaderboardBloc>()
                          .add(const LeaderboardRefreshed()),
                    );
                  case LeaderboardStatus.loaded:
                    return _Board(state: state);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LeaderboardBloc, LeaderboardState>(
      buildWhen: (a, b) => a.scope != b.scope,
      builder: (context, state) {
        // clamp() guards indexWhere returning -1 for an unknown scope.
        return AppTabBar(
          labels: _scopes.map((s) => s.$2.tr()).toList(),
          selectedIndex: _scopes
              .indexWhere((s) => s.$1 == state.scope)
              .clamp(0, _scopes.length - 1),
          onChanged: (i) => context
              .read<LeaderboardBloc>()
              .add(LeaderboardScopeChanged(_scopes[i].$1)),
        );
      },
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.state});
  final LeaderboardState state;

  @override
  Widget build(BuildContext context) {
    if (state.entries.isEmpty) {
      return _ErrorView(
        message: state.scope == 'friends'
            ? 'trivia.no_friends_board'.tr()
            : 'trivia.no_scores_yet'.tr(),
        icon: CupertinoIcons.chart_bar,
      );
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: () async => context
                .read<LeaderboardBloc>()
                .add(const LeaderboardRefreshed()),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _EntryRow(entry: state.entries[i]),
            ),
          ),
        ),
        if (state.myRank != null) _PinnedMyRow(entry: state.myRank!),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final LeaderboardEntryEntity entry;

  @override
  Widget build(BuildContext context) {
    final isMe = entry.isMe;
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
          RankBadge(rank: entry.rank),
          const SizedBox(width: 12),
          _Avatar(url: entry.avatar, name: entry.username, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? 'trivia.you'.tr() : entry.username,
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
                  'trivia.correct_of'.tr(
                    namedArgs: {'count': '${entry.correctCount}'},
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${entry.score}',
            style: const TextStyle(
              color: AppColors.rating,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedMyRow extends StatelessWidget {
  const _PinnedMyRow({required this.entry});
  final LeaderboardEntryEntity entry;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomSafe),
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: _EntryRow(entry: entry),
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
                  placeholder: (_, _) => const ShimmerWrapper(
                    child: ColoredBox(color: Colors.white),
                  ),
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

class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 9,
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
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                ),
                child: Text('general.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
