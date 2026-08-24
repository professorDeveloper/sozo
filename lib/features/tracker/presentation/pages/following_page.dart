import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/pages/anilist_library_page.dart';
import 'package:soplay/features/anilist/presentation/pages/upcoming_page.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

/// Everything the user is keeping track of, in one place.
///
/// Three tabs rather than three destinations because they answer one question
/// at different ranges: what am I following, what airs next, and what does my
/// AniList list say. Splitting them across the nav bar would make the user
/// choose a tab before knowing which one holds the answer.
///
/// The AniList controller is created HERE and lent to both AniList tabs: the
/// library is one request that serves both views, and a "+1" on one tab has to
/// be visible on the other immediately.
class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late final AnilistLibraryController _anilist =
      AnilistLibraryController(service: getIt<AnilistService>());

  @override
  void dispose() {
    _tabs.dispose();
    _anilist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'tracker.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'anilist.connections_title'.tr(),
            onPressed: () => context.push('/connections'),
            icon: const Icon(Icons.link_rounded),
          ),
        ],
        bottom: AppTabBar(
          controller: _tabs,
          labels: [
            'tracker.tab_following'.tr(),
            'tracker.tab_upcoming'.tr(),
            'AniList',
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const FollowedTitlesView(),
          UpcomingPage(showAppBar: false, controller: _anilist),
          AnilistLibraryPage(showAppBar: false, controller: _anilist),
        ],
      ),
    );
  }
}

/// Serials followed on a source, with a check for new episodes.
///
/// A check also runs when the tab first appears; it is bounded and timed inside
/// the service, so a large follow list cannot hang the screen.
class FollowedTitlesView extends StatefulWidget {
  const FollowedTitlesView({super.key});

  @override
  State<FollowedTitlesView> createState() => _FollowedTitlesViewState();
}

class _FollowedTitlesViewState extends State<FollowedTitlesView>
    with AutomaticKeepAliveClientMixin {
  final FollowService _service = getIt<FollowService>();
  List<FollowedTitle> _items = const [];
  bool _checking = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _items = _service.list();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_items.isNotEmpty) _check(silent: true);
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final grown = await _service.checkForUpdates();
      if (!mounted) return;
      setState(() => _items = _service.list());
      if (!silent || grown > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              grown > 0
                  ? 'tracker.new_episodes_found'.tr(args: ['$grown'])
                  : 'tracker.no_new_episodes'.tr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _unfollow(FollowedTitle t) async {
    await _service.unfollow(t.contentUrl);
    if (!mounted) return;
    setState(() => _items = _service.list());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('tracker.unfollowed'.tr(args: [t.title])),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'tracker.undo'.tr(),
          onPressed: () async {
            await _service.follow(t);
            if (mounted) setState(() => _items = _service.list());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () => _check(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.textHint.withValues(alpha: 0.5),
                      size: 52,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'tracker.following_empty'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: () => _check(),
      child: Column(
        children: [
          if (_checking)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _FollowTile(
                title: _items[i],
                onUnfollow: () => _unfollow(_items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowTile extends StatelessWidget {
  const _FollowTile({required this.title, required this.onUnfollow});

  final FollowedTitle title;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: title.contentUrl.isEmpty
            ? null
            : () => context.push(
                  '/detail',
                  extra: DetailArgs(
                    contentUrl: title.contentUrl,
                    provider: title.provider,
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 46,
                  height: 65,
                  child: title.thumbnail.isEmpty
                      ? const _Placeholder()
                      : CachedNetworkImage(
                          imageUrl: title.thumbnail,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const _Placeholder(),
                          errorWidget: (_, _, _) => const _Placeholder(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AnilistChip(
                          label: title.lastEpisodeCount > 0
                              ? 'tracker.n_episodes'
                                  .tr(args: ['${title.lastEpisodeCount}'])
                              : 'tracker.not_checked'.tr(),
                          color: AppColors.textSecondary,
                        ),
                        if (title.provider.isNotEmpty)
                          AnilistChip(
                            label: title.provider,
                            color: AppColors.textHint,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'tracker.unfollow'.tr(),
                onPressed: onUnfollow,
                icon: const Icon(
                  Icons.notifications_off_outlined,
                  color: AppColors.textHint,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.movie_rounded, color: AppColors.textHint, size: 20),
      );
}
