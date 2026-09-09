import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/domain/usecases/get_favorites_usecase.dart';
import 'package:soplay/features/my_list/presentation/bloc/my_list_bloc.dart';
import 'package:soplay/features/my_list/presentation/bloc/my_list_event.dart';
import 'package:soplay/features/my_list/presentation/bloc/my_list_state.dart';
import 'package:soplay/features/my_list/presentation/widgets/favorite_card.dart';
import 'package:soplay/features/my_list/presentation/widgets/my_list_background.dart';
import 'package:soplay/features/my_list/presentation/widgets/my_list_header.dart';
import 'package:soplay/features/my_list/presentation/widgets/my_list_skeleton.dart';
import 'package:soplay/features/my_list/presentation/widgets/my_list_state_views.dart';

class MyListPage extends StatelessWidget {
  const MyListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          MyListBloc(
            useCase: getIt<GetFavoritesUseCase>(),
            private: getIt<PrivateListService>(),
          )..add(const MyListLoad()),
      child: const _MyListView(),
    );
  }
}

class _MyListView extends StatefulWidget {
  const _MyListView();

  @override
  State<_MyListView> createState() => _MyListViewState();
}

class _MyListViewState extends State<_MyListView>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _headerBlur = ValueNotifier<double>(0.0);
  late final NavController _navController;
  late final MyListLocalDataSource _localFavorites;
  late final PrivateListService _privateFavorites;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _navController = getIt<NavController>();
    _localFavorites = getIt<MyListLocalDataSource>();
    _privateFavorites = getIt<PrivateListService>();
    _navController.index.addListener(_onNavChange);
    _localFavorites.revision.addListener(_onFavoritesChanged);
    _privateFavorites.revision.addListener(_onFavoritesChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _navController.index.removeListener(_onNavChange);
    _localFavorites.revision.removeListener(_onFavoritesChanged);
    _privateFavorites.revision.removeListener(_onFavoritesChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerBlur.dispose();
    super.dispose();
  }

  void _onNavChange() {
    if (!_navController.isActive(TabId.myList)) return;
    final bloc = context.read<MyListBloc>();
    if (bloc.state is MyListLoading) return;
    // Revisiting the tab must keep the loaded grid visible (Refresh) instead of
    // flashing the skeleton and re-fetching from scratch (Load) every time.
    bloc.add(const MyListRefresh());
  }

  void _onFavoritesChanged() {
    if (!mounted) return;
    final bloc = context.read<MyListBloc>();
    // A refresh writes the server's rows into the local cache, which is itself
    // a revision bump — so reacting to one while a refresh is in flight makes
    // this listener re-trigger the very fetch that woke it.
    if (bloc.state is MyListLoading) return;
    final current = bloc.state;
    if (current is MyListLoaded && current.refreshing) return;
    bloc.add(const MyListRefresh());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = (_scrollController.offset / 80.0).clamp(0.0, 1.0);
    if ((next - _headerBlur.value).abs() > 0.01) {
      _headerBlur.value = next;
    }
  }

  Future<void> _refresh() async {
    final bloc = context.read<MyListBloc>();
    final done = bloc.stream.firstWhere(_isSettled);
    bloc.add(const MyListRefresh());
    await done.timeout(
      const Duration(seconds: 20),
      onTimeout: () => bloc.state,
    );
  }

  bool _isSettled(MyListState state) {
    return switch (state) {
      MyListLoaded(:final refreshing) => !refreshing,
      MyListUnauthorized() || MyListError() => true,
      _ => false,
    };
  }

  void _openDetail(FavoriteEntity item) {
    context.push('/detail', extra: DetailArgs(contentUrl: item.contentUrl, provider: item.provider));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final headerH = topPad + MyListHeader.contentHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const MyListBackground(),
          RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            edgeOffset: headerH,
            child: BlocBuilder<MyListBloc, MyListState>(
              builder: (context, state) {
                return CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: headerH + 16)),
                    _buildBody(state, bottomPad),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _headerBlur,
              builder: (_, blur, _) => MyListHeader(
                topPad: topPad,
                blurProgress: blur,
                onRefresh: _refresh,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(MyListState state, double bottomPad) {
    return switch (state) {
      MyListInitial() || MyListLoading() => const MyListSkeleton(),
      MyListLoaded(:final items) =>
        items.isEmpty
            ? const SliverFillRemaining(
                hasScrollBody: false,
                child: MyListEmptyView(),
              )
            : SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 96),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 142,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.56,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final item = items[i];
                      return ItemAppear(
                        index: i,
                        // The delegate is max-extent rather than fixed-count,
                        // so the column count has to be derived the same way
                        // it derives it.
                        columns: columnsForMaxExtent(
                          MediaQuery.sizeOf(context).width,
                          142,
                          spacing: 10,
                        ),
                        child: FavoriteCard(
                          item: item,
                          synced: item is FavoriteModel && item.synced,
                          onTap: () => _openDetail(item),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              ),
      MyListUnauthorized() => SliverFillRemaining(
        hasScrollBody: false,
        child: MyListUnauthorizedView(onLogin: () => context.push('/login')),
      ),
      MyListError(:final message) => SliverFillRemaining(
        hasScrollBody: false,
        child: MyListErrorView(
          message: message,
          onRetry: () => context.read<MyListBloc>().add(const MyListLoad()),
        ),
      ),
    };
  }
}
