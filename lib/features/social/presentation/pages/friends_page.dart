import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/social/data/social_service.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/cursor_pager.dart';
import 'package:soplay/features/social/presentation/widgets/activity_card.dart';
import 'package:soplay/features/social/presentation/widgets/relation_actions.dart';
import 'package:soplay/features/social/presentation/widgets/social_widgets.dart';

enum FriendsTab { feed, friends, requests }

/// Friends' activity, the friends list and pending requests.
///
/// Called "Friends" rather than "Following": Following already means the
/// titles whose new episodes the app watches for.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.initialTab = FriendsTab.feed});

  final FriendsTab initialTab;

  static FriendsTab tabFrom(String? raw) => FriendsTab.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => FriendsTab.feed,
  );

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  final SocialService _social = getIt<SocialService>();
  late final TabController _tabs = TabController(
    length: FriendsTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  @override
  void initState() {
    super.initState();
    _social.refreshOverview();
  }

  @override
  void dispose() {
    _tabs.dispose();
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
          'social.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'social.search_title'.tr(),
            icon: const Icon(Icons.person_search_rounded),
            onPressed: () => context.push('/friends/search'),
          ),
          IconButton(
            tooltip: 'social.privacy_title'.tr(),
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => context.push('/friends/privacy'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const AppTabBar(labels: ['', '', '']).preferredSize,
          child: ValueListenableBuilder<SocialOverview>(
            valueListenable: _social.overview,
            builder: (context, overview, _) => AppTabBar(
              controller: _tabs,
              labels: [
                'social.tab_feed'.tr(),
                'social.tab_friends'.tr(),
                overview.incoming > 0
                    ? '${'social.tab_requests'.tr()} · ${overview.incoming}'
                    : 'social.tab_requests'.tr(),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_FeedView(), _FriendsView(), _RequestsView()],
      ),
    );
  }
}

mixin _RevisionRefresh<T extends StatefulWidget> on State<T> {
  final SocialService social = getIt<SocialService>();

  void onRevision();

  @override
  void initState() {
    super.initState();
    social.revision.addListener(onRevision);
  }

  @override
  void dispose() {
    social.revision.removeListener(onRevision);
    super.dispose();
  }
}

class _FeedView extends StatefulWidget {
  const _FeedView();

  @override
  State<_FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<_FeedView>
    with AutomaticKeepAliveClientMixin, _RevisionRefresh {
  late final CursorPager<ActivityItem> _pager = CursorPager(
    fetch: (cursor) => social.remote.feed(cursor: cursor),
    idOf: (a) => a.id,
  );
  bool? _sharing;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pager.refresh();
    _loadSharing();
  }

  Future<void> _loadSharing() async {
    try {
      final s = await social.remote.settings();
      if (mounted) setState(() => _sharing = s.shareActivity);
    } catch (_) {}
  }

  @override
  void onRevision() => _pager.refresh();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      _pager.refresh(),
      social.refreshOverview(),
      _loadSharing(),
    ]);
  }

  Future<void> _openPrivacy() async {
    await context.push('/friends/privacy');
    _loadSharing();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _refresh,
      child: ListenableBuilder(
        listenable: Listenable.merge([_pager, social.overview]),
        builder: (context, _) {
          if (!_pager.loaded && _pager.error == null) {
            return const _Loading();
          }
          if (!_pager.loaded) {
            return SocialStateView.error(_pager.error, _pager.refresh);
          }
          final nudge = _sharing == false;
          if (_pager.isEmpty) {
            final noFriends = social.overview.value.friends == 0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (nudge) _ShareNudge(onTap: _openPrivacy),
                SizedBox(
                  height: 420,
                  child: SocialStateView(
                    scrollable: false,
                    icon: noFriends
                        ? Icons.group_add_rounded
                        : Icons.dynamic_feed_rounded,
                    title: noFriends
                        ? 'social.feed_no_friends_title'.tr()
                        : 'social.feed_empty_title'.tr(),
                    body: noFriends
                        ? 'social.feed_no_friends_body'.tr()
                        : 'social.feed_empty_body'.tr(),
                    actionLabel: noFriends ? 'social.find_friends'.tr() : null,
                    onAction: noFriends
                        ? () => context.push('/friends/search')
                        : null,
                  ),
                ),
              ],
            );
          }
          final items = _pager.items;
          final head = nudge ? 1 : 0;
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) _pager.loadMore();
              return false;
            },
            child: MaxWidthBox(
              maxWidth: 640,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                itemCount: head + items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (nudge && i == 0) return _ShareNudge(onTap: _openPrivacy);
                  final index = i - head;
                  if (index >= items.length) {
                    return SocialListFooter(
                      loading: _pager.loadingMore,
                      failed: _pager.error != null,
                      onRetry: _pager.loadMore,
                    );
                  }
                  return ActivityCard(item: items[index]);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShareNudge extends StatelessWidget {
  const _ShareNudge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(Icons.visibility_off_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'social.share_nudge'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'social.share_nudge_action'.tr(),
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsView extends StatefulWidget {
  const _FriendsView();

  @override
  State<_FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<_FriendsView>
    with AutomaticKeepAliveClientMixin, _RevisionRefresh {
  late final CursorPager<FriendEntry> _pager = CursorPager(
    fetch: (cursor) => social.remote.friends(cursor: cursor),
    idOf: (f) => f.user.id,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pager.refresh();
  }

  @override
  void onRevision() => _pager.refresh();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _pager.refresh,
      child: ListenableBuilder(
        listenable: _pager,
        builder: (context, _) {
          if (!_pager.loaded && _pager.error == null) return const _Loading();
          if (!_pager.loaded) {
            return SocialStateView.error(_pager.error, _pager.refresh);
          }
          if (_pager.isEmpty) {
            return SocialStateView(
              icon: Icons.people_outline_rounded,
              title: 'social.friends_empty_title'.tr(),
              body: 'social.friends_empty_body'.tr(),
              actionLabel: 'social.find_friends'.tr(),
              onAction: () => context.push('/friends/search'),
            );
          }
          final items = _pager.items;
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) _pager.loadMore();
              return false;
            },
            child: MaxWidthBox(
              maxWidth: 640,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 8,
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                ),
                itemCount: items.length + 1,
                itemBuilder: (context, i) {
                  if (i >= items.length) {
                    return SocialListFooter(
                      loading: _pager.loadingMore,
                      failed: _pager.error != null,
                      onRetry: _pager.loadMore,
                    );
                  }
                  final f = items[i];
                  final since = f.since;
                  return SocialUserTile(
                    user: f.user,
                    subtitle: since == null
                        ? null
                        : 'social.friends_since'.tr(
                            args: [socialTimeLabel(context, since)],
                          ),
                    onTap: () => context.push(
                      '/u/${Uri.encodeComponent(f.user.username)}',
                    ),
                    trailing: _FriendMenu(user: f.user),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FriendMenu extends StatelessWidget {
  const _FriendMenu({required this.user});

  final SocialUser user;

  Future<void> _remove(BuildContext context) async {
    final ok = await confirmSocial(
      context,
      title: 'social.remove_title'.tr(args: [user.name]),
      body: 'social.remove_body'.tr(),
      confirm: 'social.action_remove'.tr(),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await getIt<SocialService>().removeFriend(user.id);
      if (context.mounted) {
        showSocialSnack(context, 'social.removed_snack'.tr());
      }
    } catch (e) {
      if (context.mounted) showSocialSnack(context, socialErrorText(e));
    }
  }

  Future<void> _block(BuildContext context) async {
    final ok = await confirmBlock(context, user);
    if (!ok || !context.mounted) return;
    try {
      await getIt<SocialService>().block(user.id);
      if (context.mounted) {
        showSocialSnack(context, 'social.blocked_snack'.tr(args: [user.name]));
      }
    } catch (e) {
      if (context.mounted) showSocialSnack(context, socialErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint),
      color: AppColors.surface,
      onSelected: (v) => v == 'remove' ? _remove(context) : _block(context),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'remove',
          child: Text('social.action_remove'.tr()),
        ),
        PopupMenuItem(
          value: 'block',
          child: Text(
            'social.action_block'.tr(),
            style: const TextStyle(color: AppColors.errorLight),
          ),
        ),
      ],
    );
  }
}

Future<bool> confirmBlock(BuildContext context, SocialUser user) =>
    confirmSocial(
      context,
      title: 'social.block_title'.tr(args: [user.name]),
      body: 'social.block_body'.tr(),
      confirm: 'social.action_block'.tr(),
      destructive: true,
    );

class _RequestsView extends StatefulWidget {
  const _RequestsView();

  @override
  State<_RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<_RequestsView>
    with AutomaticKeepAliveClientMixin, _RevisionRefresh {
  List<FriendRequest>? _incoming;
  List<FriendRequest>? _outgoing;
  Object? _error;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onRevision() => _load();

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final results = await Future.wait([
        social.remote.requests(incoming: true),
        social.remote.requests(incoming: false),
      ]);
      if (!mounted) return;
      setState(() {
        _incoming = results[0];
        _outgoing = results[1];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  /// Drops the row at once; the revision reload that follows confirms it.
  void _settle(FriendRequest r) {
    setState(() {
      _incoming = _incoming?.where((e) => e.id != r.id).toList();
      _outgoing = _outgoing?.where((e) => e.id != r.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final incoming = _incoming;
    final outgoing = _outgoing;
    Widget body;
    if (incoming == null || outgoing == null) {
      body = _error == null
          ? const _Loading()
          : SocialStateView.error(_error, _load);
    } else if (incoming.isEmpty && outgoing.isEmpty) {
      body = SocialStateView(
        icon: Icons.mark_email_read_outlined,
        title: 'social.requests_empty_title'.tr(),
        body: 'social.requests_empty_body'.tr(),
        actionLabel: 'social.find_friends'.tr(),
        onAction: () => context.push('/friends/search'),
      );
    } else {
      body = MaxWidthBox(
        maxWidth: 640,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            if (incoming.isNotEmpty) ...[
              _SectionLabel('social.requests_incoming'.tr()),
              _RequestCard(requests: incoming, onSettled: _settle),
              const SizedBox(height: 20),
            ],
            if (outgoing.isNotEmpty) ...[
              _SectionLabel('social.requests_outgoing'.tr()),
              _RequestCard(requests: outgoing, onSettled: _settle),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: body,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.requests, required this.onSettled});

  final List<FriendRequest> requests;
  final ValueChanged<FriendRequest> onSettled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < requests.length; i++) ...[
            if (i > 0) Divider(color: AppColors.divider, height: 1, indent: 70),
            SocialUserTile(
              key: ValueKey(requests[i].id),
              user: requests[i].user,
              subtitle: socialTimeLabel(context, requests[i].createdAt),
              onTap: () => context.push(
                '/u/${Uri.encodeComponent(requests[i].user.username)}',
              ),
              trailing: RelationActions(
                user: requests[i].user,
                relation: requests[i].incoming
                    ? SocialRelation.incoming
                    : SocialRelation.outgoing,
                requestId: requests[i].id,
                onChanged: (_, _) => onSettled(requests[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 160),
        Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ],
    );
  }
}
