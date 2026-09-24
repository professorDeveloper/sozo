import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/social/data/social_service.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/cursor_pager.dart';
import 'package:soplay/features/social/presentation/pages/friends_page.dart';
import 'package:soplay/features/social/presentation/widgets/activity_card.dart';
import 'package:soplay/features/social/presentation/widgets/relation_actions.dart';
import 'package:soplay/features/social/presentation/widgets/social_widgets.dart';

/// Someone's public card and, when they allow it, their recent activity.
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.username});

  final String username;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final SocialService _social = getIt<SocialService>();
  late final CursorPager<ActivityItem> _activity = CursorPager(
    fetch: (cursor) =>
        _social.remote.userActivity(widget.username, cursor: cursor),
    idOf: (a) => a.id,
  );

  SocialProfile? _profile;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _activity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _social.remote.profile(widget.username);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _error = null;
      });
      if (p.canSeeActivity) await _activity.refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onRelation(SocialRelation relation, String? requestId) {
    final p = _profile;
    if (p == null) return;
    setState(
      () => _profile = p.copyWith(
        relation: relation,
        requestId: requestId,
        clearRequest: requestId == null,
      ),
    );
    // Becoming or ceasing to be friends can change what this viewer may see.
    _load();
  }

  Future<void> _block() async {
    final p = _profile;
    if (p == null) return;
    if (!await confirmBlock(context, p.user) || !mounted) return;
    try {
      await _social.block(p.user.id);
      if (!mounted) return;
      showSocialSnack(context, 'social.blocked_snack'.tr(args: [p.user.name]));
      context.pop();
    } catch (e) {
      if (mounted) showSocialSnack(context, socialErrorText(e));
    }
  }

  Future<void> _deleteActivity(ActivityItem item) async {
    final ok = await confirmSocial(
      context,
      title: 'social.activity_delete'.tr(),
      body: 'social.activity_delete_body'.tr(),
      confirm: 'general.delete'.tr(),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _social.remote.deleteActivity(item.id);
      _activity.removeWhere((a) => a.id == item.id);
    } catch (e) {
      if (mounted) showSocialSnack(context, socialErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final self = p?.relation == SocialRelation.self;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          '@${widget.username}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (p != null && !self)
            PopupMenuButton<String>(
              color: AppColors.surface,
              onSelected: (_) => _block(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    'social.action_block'.tr(),
                    style: const TextStyle(color: AppColors.errorLight),
                  ),
                ),
              ],
            ),
          if (self)
            IconButton(
              tooltip: 'social.privacy_title'.tr(),
              icon: const Icon(Icons.shield_outlined),
              onPressed: () async {
                await context.push('/friends/privacy');
                _load();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: _body(p),
      ),
    );
  }

  Widget _body(SocialProfile? p) {
    if (p == null) {
      if (_error == null) {
        return Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      final gone =
          _error is SocialException &&
          (_error as SocialException).kind == SocialError.notFound;
      return gone
          ? SocialStateView(
              icon: Icons.person_off_outlined,
              title: 'social.profile_unavailable'.tr(),
              body: 'social.profile_unavailable_body'.tr(),
            )
          : SocialStateView.error(_error, _load);
    }
    return ListenableBuilder(
      listenable: _activity,
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (p.canSeeActivity && n.metrics.extentAfter < 400) {
            _activity.loadMore();
          }
          return false;
        },
        child: MaxWidthBox(
          maxWidth: 640,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(profile: p, onRelation: _onRelation),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'social.profile_activity'.tr().toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              ..._activitySlivers(p),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _activitySlivers(SocialProfile p) {
    final self = p.relation == SocialRelation.self;
    if (!p.canSeeActivity) {
      return [
        SliverToBoxAdapter(
          child: SocialStateView(
            scrollable: false,
            icon: Icons.lock_outline_rounded,
            title: 'social.activity_hidden_title'.tr(),
            body: p.relation == SocialRelation.friends
                ? 'social.activity_hidden_friend'.tr()
                : 'social.activity_hidden_body'.tr(),
          ),
        ),
      ];
    }
    if (!_activity.loaded) {
      return [
        SliverToBoxAdapter(
          child: _activity.error != null
              ? SocialStateView.error(_activity.error, _activity.refresh)
              : Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
        ),
      ];
    }
    if (_activity.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SocialStateView(
            scrollable: false,
            icon: Icons.history_toggle_off_rounded,
            title: 'social.profile_activity_empty'.tr(),
            body: self ? 'social.profile_activity_empty_self'.tr() : null,
          ),
        ),
      ];
    }
    final items = _activity.items;
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i >= items.length) {
              return SocialListFooter(
                loading: _activity.loadingMore,
                failed: _activity.error != null,
                onRetry: _activity.loadMore,
              );
            }
            return ActivityCard(
              item: items[i],
              showActor: false,
              onDelete: self ? () => _deleteActivity(items[i]) : null,
            );
          },
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.onRelation});

  final SocialProfile profile;
  final RelationChanged onRelation;

  @override
  Widget build(BuildContext context) {
    final user = profile.user;
    final count = profile.friendsCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            SocialAvatar(user: user, size: 84),
            const SizedBox(height: 12),
            Text(
              user.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '@${user.username}',
              style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
            if (count != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'social.tab_friends'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            if (profile.relation == SocialRelation.self) ...[
              const SizedBox(height: 12),
              Text(
                'social.profile_self'.tr(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 16),
              RelationActions(
                user: user,
                relation: profile.relation,
                requestId: profile.requestId,
                acceptsRequests: profile.acceptsRequests,
                onChanged: onRelation,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
