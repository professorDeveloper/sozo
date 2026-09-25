import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_event.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_state.dart';
import 'package:soplay/features/home/presentation/widgets/view_all_widgets.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';

/// Opens one service's catalogue.
///
/// A function rather than a route constant so the argument stays typed: every
/// caller has a whole [WatchServiceEntity] in hand and nothing about it needs
/// to survive a url.
Future<void> openWatchService(
  BuildContext context,
  WatchServiceEntity service, {
  required String region,
}) => context.push(
  '/watch-service',
  extra: WatchServiceArgs(service: service, region: region),
);

class WatchServiceArgs {
  const WatchServiceArgs({required this.service, required this.region});

  final WatchServiceEntity service;
  final String region;
}

/// What one service carries, here.
///
/// A shell around [ViewAllBloc] rather than a second paging machine: the grid,
/// the skeleton, the error view, the empty view, the load-more listener and the
/// desktop auto-fill all already exist and are already right. What this adds is
/// a title, a media toggle, and the one thing the shared grid could not know —
/// that these cards belong to TMDB and not to whichever source is selected.
class WatchServiceBrowsePage extends StatefulWidget {
  const WatchServiceBrowsePage({super.key, required this.args});

  final WatchServiceArgs args;

  @override
  State<WatchServiceBrowsePage> createState() => _WatchServiceBrowsePageState();
}

class _WatchServiceBrowsePageState extends State<WatchServiceBrowsePage> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _blur = ValueNotifier<double>(0);
  late WatchServiceMedia _media;
  late final ViewAllBloc _bloc;

  @override
  void initState() {
    super.initState();
    final types = widget.args.service.types;
    _media = types.contains(WatchServiceMedia.movie) || types.isEmpty
        ? WatchServiceMedia.movie
        : WatchServiceMedia.tv;
    _bloc = getIt<ViewAllBloc>()..add(ViewAllLoad(key: _key, slug: _slug));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _blur.dispose();
    _bloc.close();
    super.dispose();
  }

  /// `<serviceId>:<movie|tv>:<REGION>`.
  ///
  /// The region is in the slug rather than read from storage at request time so
  /// that a screen opened for one country keeps showing that country even if
  /// the setting changes underneath it — a grid that silently repages to
  /// somewhere else while being scrolled is worse than one that is a little
  /// stale.
  String get _slug =>
      '${widget.args.service.id}:${_media.id}:${widget.args.region}';

  static const String _key = 'watch-service';

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _blur.value = (_scroll.offset / 80).clamp(0.0, 1.0);
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _bloc.add(ViewAllLoadMore());
    }
  }

  void _pick(WatchServiceMedia media) {
    if (media == _media) return;
    setState(() => _media = media);
    _scroll.jumpTo(0);
    _bloc.add(ViewAllLoad(key: _key, slug: _slug));
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    // A toggle with one option is a label, and one that switches to an empty
    // list is worse than none — so it appears only for a service that TMDB says
    // carries both.
    final bothKinds = service.hasMovies && service.hasSeries;
    final topPad = MediaQuery.paddingOf(context).top;
    final appBarH = topPad + 56 + (bothKinds ? 52 : 0);

    return BlocProvider<ViewAllBloc>.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            BlocBuilder<ViewAllBloc, ViewAllState>(
              builder: (context, state) => switch (state) {
                ViewAllLoaded() => ViewAllGrid(
                  state: state,
                  scroll: _scroll,
                  appBarH: appBarH,
                  // Without this, tapping a title here resolves it against
                  // whichever source is selected — which has never heard of a
                  // TMDB url.
                  provider: Catalogue.tmdb.id,
                ),
                ViewAllError(:final mesage) => ViewAllErrorView(
                  message: mesage,
                  onRetry: () => _bloc.add(ViewAllLoad(key: _key, slug: _slug)),
                ),
                _ => ViewAllSkeleton(appBarH: appBarH),
              },
            ),
            ValueListenableBuilder<double>(
              valueListenable: _blur,
              builder: (context, blur, _) => Column(
                children: [
                  ViewAllAppBar(title: service.name, blurProgress: blur),
                  if (bothKinds) _toggle(blur),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(double blur) => Container(
    height: 52,
    width: double.infinity,
    color: AppColors.background.withValues(alpha: 0.9 * blur),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(
      children: [
        _segment(WatchServiceMedia.movie, 'watch.type_movies'.tr()),
        const SizedBox(width: 8),
        _segment(WatchServiceMedia.tv, 'watch.type_series'.tr()),
      ],
    ),
  );

  Widget _segment(WatchServiceMedia media, String label) {
    final selected = _media == media;
    return InkWell(
      onTap: () => _pick(media),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
