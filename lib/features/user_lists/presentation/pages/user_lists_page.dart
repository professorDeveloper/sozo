import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';

/// The user's curated lists, one tab per [UserListKind].
///
/// A page of its own rather than another mode inside `MyListPage`: that page is
/// driven by `MyListBloc` around a single favorites source, and threading two
/// more sources through it would couple three independent lists to one bloc.
/// Tabs are generated from the enum, so a third list needs no code here.
class UserListsPage extends StatefulWidget {
  const UserListsPage({super.key, this.initialKind});

  /// Which tab opens first — used when arriving from a "Watch Later" shortcut.
  final UserListKind? initialKind;

  @override
  State<UserListsPage> createState() => _UserListsPageState();
}

class _UserListsPageState extends State<UserListsPage>
    with SingleTickerProviderStateMixin {
  static const _kinds = UserListKind.values;

  late final TabController _tabs = TabController(
    length: _kinds.length,
    vsync: this,
    initialIndex: widget.initialKind == null
        ? 0
        : _kinds.indexOf(widget.initialKind!).clamp(0, _kinds.length - 1),
  );

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
          'user_lists.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        bottom: AppTabBar(
          // Two tabs: split the bar rather than hugging the left edge.
          isScrollable: false,
          controller: _tabs,
          labels: [for (final k in _kinds) _labelOf(k)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [for (final k in _kinds) _UserListTab(kind: k)],
      ),
    );
  }
}

/// The enum's own `label` is an English developer-facing name; the tabs and
/// headings the user reads come from the same keys the detail page uses.
String _labelOf(UserListKind kind) => switch (kind) {
  UserListKind.watchLater => 'detail.watch_later'.tr(),
  UserListKind.watched => 'detail.watched'.tr(),
};

class _UserListTab extends StatefulWidget {
  const _UserListTab({required this.kind});

  final UserListKind kind;

  @override
  State<_UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends State<_UserListTab>
    with AutomaticKeepAliveClientMixin {
  List<FavoriteEntity>? _items;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Refreshing keeps the rows on screen: replacing them with a spinner while
  /// the pull-to-refresh indicator is already spinning blanks the whole tab.
  Future<void> _load() async {
    final result = await getIt<UserListsRepository>().getList(widget.kind);
    if (!mounted) return;
    setState(() => _items = result.getOrNull() ?? const []);
  }

  Future<void> _remove(FavoriteEntity item) async {
    setState(
      () => _items = [
        for (final e in _items ?? const <FavoriteEntity>[])
          if (e.contentUrl != item.contentUrl) e,
      ],
    );
    await getIt<UserListsRepository>().remove(widget.kind, item.contentUrl);
  }

  void _open(FavoriteEntity item) {
    context.push(
      '/detail',
      extra: DetailArgs(contentUrl: item.contentUrl, provider: item.provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    if (items == null) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: items.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  Divider(color: AppColors.divider, height: 1, indent: 84),
              itemBuilder: (context, i) {
                final item = items[i];
                return _UserListRow(
                  item: item,
                  onTap: () => _open(item),
                  onRemove: () => _remove(item),
                );
              },
            ),
    );
  }
}

class _UserListRow extends StatelessWidget {
  const _UserListRow({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final FavoriteEntity item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Fixed box: the thumbnail loads late, and letting it size the row
            // makes the whole list jump as images arrive.
            SizedBox(
              width: 54,
              height: 76,
              child: HomeNetworkImage(
                url: item.thumbnail,
                borderRadius: BorderRadius.circular(8),
                placeholderIcon: Icons.movie_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title.trim().isEmpty
                        ? 'my_list.untitled'.tr()
                        : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.provider,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'user_lists.remove'.tr(),
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // Scrollable so the empty tab still answers a pull-to-refresh.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            // Biased above the true centre. The app bar and the tab strip take
            // the top of the screen, so a block centred in what is left reads
            // as sitting too low — the eye measures against the whole screen,
            // not against the viewport it was given. The same 1/8 nudge is what
            // the My List empty state gets from its bottom padding.
            padding: EdgeInsets.only(
              left: 32,
              right: 32,
              bottom: constraints.maxHeight / 8,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.playlist_add_check_rounded,
                  color: AppColors.textHint,
                  size: 52,
                ),
                const SizedBox(height: 14),
                Text(
                  'user_lists.empty_title'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'user_lists.empty_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                    height: 1.4,
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
