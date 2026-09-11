import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_event.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_state.dart';
import 'package:soplay/features/home/presentation/widgets/view_all_widgets.dart';

/// A paged grid for one catalogue section.
///
/// Each page gets its own [ViewAllBloc]. It used to read one shared from the
/// app root, so opening a second "View all" on top of the first (a genre from
/// inside a category, say) re-pointed that single bloc at the new section —
/// and going back showed the second section's items under the first one's
/// title, with "load more" paging the wrong list.
class HomeViewAllPage extends StatelessWidget {
  const HomeViewAllPage({
    super.key,
    required this.keyCat,
    required this.title,
    this.slug = '',
  });

  final String keyCat;
  final String? slug;
  final String title;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ViewAllBloc>(
      create: (_) => getIt<ViewAllBloc>()
        ..add(ViewAllLoad(key: keyCat, slug: slug)),
      child: _HomeViewAllView(keyCat: keyCat, slug: slug, title: title),
    );
  }
}

class _HomeViewAllView extends StatefulWidget {
  const _HomeViewAllView({
    required this.keyCat,
    required this.title,
    this.slug = '',
  });

  final String keyCat;
  final String? slug;
  final String title;

  @override
  State<_HomeViewAllView> createState() => _HomeViewAllViewState();
}

class _HomeViewAllViewState extends State<_HomeViewAllView> {
  late final ScrollController _scroll;
  final _blurProgress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    final next = (_scroll.offset / 80).clamp(0.0, 1.0);
    if ((next - _blurProgress.value).abs() >= 0.02) _blurProgress.value = next;

    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      context.read<ViewAllBloc>().add(ViewAllLoadMore());
    }
  }

  void _maybeAutoFill(ViewAllState state) {
    if (!isDesktopPlatform) return;
    if (state is! ViewAllLoaded || !state.hasMore || state.isLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) {
        context.read<ViewAllBloc>().add(ViewAllLoadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _blurProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final appBarH = topPad + 56.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          BlocConsumer<ViewAllBloc, ViewAllState>(
            listener: (context, state) => _maybeAutoFill(state),
            builder: (context, state) {
              if (state is ViewAllLoading) {
                return ViewAllSkeleton(appBarH: appBarH);
              }
              if (state is ViewAllError) {
                return ViewAllErrorView(
                  message: state.mesage,
                  onRetry: () => context.read<ViewAllBloc>().add(
                    ViewAllLoad(key: widget.keyCat, slug: widget.slug),
                  ),
                );
              }
              if (state is ViewAllLoaded) {
                return ViewAllGrid(
                  state: state,
                  scroll: _scroll,
                  appBarH: appBarH,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _blurProgress,
              builder: (_, progress, _) => ViewAllAppBar(
                title: widget.title,
                blurProgress: progress,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
