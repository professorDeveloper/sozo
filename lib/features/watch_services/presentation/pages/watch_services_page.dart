import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/home/presentation/widgets/view_all_widgets.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/presentation/bloc/watch_services/watch_services_bloc.dart';
import 'package:soplay/features/watch_services/presentation/pages/watch_service_browse_page.dart';
import 'package:soplay/features/watch_services/presentation/widgets/watch_region_menu.dart';
import 'package:soplay/features/watch_services/presentation/widgets/watch_service_tile.dart';

/// Every streaming service in the chosen country.
///
/// A grid of marks rather than a list of rows: a service is recognised by its
/// logo, and a hundred and thirty rows of text is not something anybody scans.
///
/// Nothing is capped here. A cap means a service somebody pays for is silently
/// absent, which is worse than a long grid — and the grid is lazy, so the tail
/// costs nothing until it is scrolled to.
class WatchServicesPage extends StatefulWidget {
  const WatchServicesPage({super.key});

  @override
  State<WatchServicesPage> createState() => _WatchServicesPageState();
}

class _WatchServicesPageState extends State<WatchServicesPage> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _blur = ValueNotifier<double>(0);
  String _query = '';

  /// Above this, the country has a long tail nobody recognises by logo, and
  /// TMDB's own priority ordering is worth surfacing separately.
  static const int _topThreshold = 20;
  static const int _topCount = 12;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients) {
        _blur.value = (_scroll.offset / 80).clamp(0.0, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _blur.dispose();
    super.dispose();
  }

  static int columnsFor(double width) =>
      width >= 900 ? 8 : (width >= 620 ? 6 : 4);

  List<WatchServiceEntity> _match(List<WatchServiceEntity> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return [
      for (final s in all)
        if (s.name.toLowerCase().contains(q) ||
            s.slug.toLowerCase().contains(q))
          s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bloc = getIt<WatchServicesBloc>();
    final topPad = MediaQuery.paddingOf(context).top;
    final appBarH = topPad + 56;

    return BlocProvider<WatchServicesBloc>.value(
      value: bloc,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<WatchServicesBloc, WatchServicesState>(
          builder: (context, state) => Stack(
            children: [
              _body(context, state, bloc, appBarH),
              ValueListenableBuilder<double>(
                valueListenable: _blur,
                builder: (context, blur, _) => ViewAllAppBar(
                  title: 'watch.services_title'.tr(),
                  blurProgress: blur,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WatchServicesState state,
    WatchServicesBloc bloc,
    double appBarH,
  ) {
    if (state.status == WatchServicesStatus.error) {
      return ViewAllErrorView(
        message: state.error ?? 'watch.load_failed'.tr(),
        onRetry: () => bloc.add(const WatchServicesLoad()),
      );
    }
    if (!state.hasServices) {
      if (state.status == WatchServicesStatus.loading ||
          state.status == WatchServicesStatus.initial) {
        return ViewAllSkeleton(appBarH: appBarH);
      }
      return _empty(context, state, bloc, appBarH);
    }

    final shown = _match(state.services);
    final showTop = _query.isEmpty && state.services.length > _topThreshold;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        return CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: appBarH + 8)),
            SliverToBoxAdapter(child: _regionMenu(state, bloc)),
            SliverToBoxAdapter(child: _search(state.services.length)),
            if (showTop) ...[
              _label('watch.top_services'.tr()),
              _grid(
                state.services.take(_topCount).toList(),
                columns,
                state.region,
                keyPrefix: 'top',
              ),
            ],
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'watch.no_match'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              )
            else ...[
              if (showTop) _label('watch.all_services'.tr()),
              _grid(
                showTop
                    ? ([...shown]..sort((a, b) => a.name.compareTo(b.name)))
                    : shown,
                columns,
                state.region,
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        );
      },
    );
  }

  Widget _regionMenu(WatchServicesState state, WatchServicesBloc bloc) =>
      WatchRegionMenu(
        region: state.region,
        regionName: state.regionName,
        serviceCount: state.services.length,
        regions: state.regions,
        loadingRegions: state.loadingRegions,
        deviceRegion:
            WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '',
        onOpen: () => bloc.add(const WatchServicesRegionsRequested()),
        onPick: (code) => bloc.add(WatchServicesRegionChanged(code)),
      );

  Widget _search(int total) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'watch.services_search_hint'.tr(),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
      ),
    ),
  );

  Widget _label(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    ),
  );

  Widget _grid(
    List<WatchServiceEntity> services,
    int columns,
    String region, {
    String keyPrefix = 'all',
  }) {
    final scale = MediaQuery.textScalerOf(context);
    final size = WatchServiceTile.sizeFor();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, i) => ItemAppear(
            index: i,
            columns: columns,
            child: WatchServiceTile(
              key: ValueKey('$keyPrefix:${services[i].id}'),
              service: services[i],
              onTap: (s) => openWatchService(context, s, region: region),
            ),
          ),
          childCount: services.length,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          // Measured rather than an aspect ratio, so at 1.8x text the name
          // grows instead of overflowing.
          mainAxisExtent: size + 6 + scale.scale(10.5) * 1.35,
        ),
      ),
    );
  }

  Widget _empty(
    BuildContext context,
    WatchServicesState state,
    WatchServicesBloc bloc,
    double appBarH,
  ) => CustomScrollView(
    controller: _scroll,
    slivers: [
      SliverToBoxAdapter(child: SizedBox(height: appBarH + 8)),
      SliverToBoxAdapter(child: _regionMenu(state, bloc)),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                size: 40,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 14),
              Text(
                'watch.empty_region_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'watch.empty_region_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
