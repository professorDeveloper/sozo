import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/shorts/domain/entities/short_entity.dart';
import 'package:soplay/features/shorts/domain/usecases/get_short_usecase.dart';
import 'package:soplay/features/shorts/presentation/bloc/shorts_bloc.dart';
import 'package:soplay/features/shorts/presentation/bloc/shorts_event.dart';
import 'package:soplay/features/shorts/presentation/bloc/shorts_state.dart';
import 'package:soplay/features/shorts/presentation/widgets/short_reel_item.dart';
import 'package:soplay/features/shorts/presentation/widgets/shorts_state_views.dart';

class ShortsPage extends StatelessWidget {
  const ShortsPage({
    super.key,
    required this.active,
    required this.refreshTick,
  });

  final bool active;
  final int refreshTick;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ShortsBloc>()..add(const ShortsLoad()),
      child: _ShortsView(active: active, refreshTick: refreshTick),
    );
  }
}

class _ShortsView extends StatefulWidget {
  const _ShortsView({required this.active, required this.refreshTick});

  final bool active;
  final int refreshTick;

  @override
  State<_ShortsView> createState() => _ShortsViewState();
}

class _ShortsViewState extends State<_ShortsView>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final PageController _controller = PageController();
  bool _appActive = true;
  bool _detailOpen = false;
  bool _loadingContent = false;

  @override
  bool get wantKeepAlive => true;

  bool get _playbackActive => widget.active && _appActive && !_detailOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _ShortsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isDesktopPlatform) return;
    final next = state == AppLifecycleState.resumed;
    if (_appActive == next) return;
    setState(() => _appActive = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    context.read<ShortsBloc>().add(const ShortsRefresh());
    if (_controller.hasClients) {
      _controller.animateToPage(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openContent(ShortEntity short) async {
    setState(() {
      _detailOpen = true;
      _loadingContent = true;
    });

    final provider = short.provider.trim();
    if (provider.isNotEmpty) {
      await getIt<HiveService>().saveCurrentProvider(provider);
    }
    if (!mounted) return;

    var contentUrl = short.contentUrl.trim();

    if (contentUrl.isEmpty && short.id.isNotEmpty) {
      final result = await getIt<GetShortUseCase>()(short.id);
      if (!mounted) return;
      if (result case Success<ShortEntity>(:final value)) {
        contentUrl = value.contentUrl.trim();
        final p = value.provider.trim();
        if (p.isNotEmpty) {
          await getIt<HiveService>().saveCurrentProvider(p);
        }
      }
      if (!mounted) return;
    }

    if (mounted) setState(() => _loadingContent = false);

    if (contentUrl.isNotEmpty) {
      await context.push('/detail', extra: DetailArgs(contentUrl: contentUrl));
      if (mounted) setState(() => _detailOpen = false);
      return;
    }

    final slug = short.tags.isNotEmpty ? short.tags.first : '';
    if (slug.isNotEmpty) {
      await context.push(
        '/view-all',
        extra: ViewAllEntity(slug: slug, type: 'movies'),
      );
      if (mounted) setState(() => _detailOpen = false);
      return;
    }

    if (mounted) setState(() => _detailOpen = false);
    _showNotice('shorts.content_unavailable'.tr());
  }

  Widget _reelFrame(Widget reel) {
    if (!isDesktopPlatform) return reel;
    return Center(
      child: LayoutBuilder(
        builder: (context, c) {
          final width = (c.maxHeight * 9 / 16).clamp(340.0, 560.0);
          return SizedBox(width: width, height: c.maxHeight, child: reel);
        },
      ),
    );
  }

  Widget _blurredBackdrop(String thumbnail) {
    if (!isDesktopPlatform || thumbnail.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.network(
                thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
              ),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          BlocConsumer<ShortsBloc, ShortsState>(
            listenWhen: (previous, current) {
              return previous is ShortsLoaded &&
                  current is ShortsLoaded &&
                  previous.noticeId != current.noticeId &&
                  current.notice != null;
            },
            listener: (context, state) {
              if (state is ShortsLoaded && state.notice != null) {
                _showNotice(state.notice!);
              }
            },
            builder: (context, state) {
              return switch (state) {
                ShortsInitial() || ShortsLoading() => const ShortsLoadingView(),
                ShortsError(:final message) => ShortsErrorView(
                  message: message,
                  onRetry: () =>
                      context.read<ShortsBloc>().add(const ShortsLoad()),
                ),
                ShortsLoaded(:final items, :final activeIndex) =>
                  items.isEmpty
                      ? const ShortsEmptyView()
                      : Stack(
                          children: [
                            _blurredBackdrop(
                              items[activeIndex.clamp(0, items.length - 1)]
                                  .thumbnail,
                            ),
                            _reelFrame(PageView.builder(
                              controller: _controller,
                              scrollDirection: Axis.vertical,
                              itemCount:
                                  items.length + (state.loadingMore ? 1 : 0),
                              onPageChanged: (index) {
                                if (index < items.length) {
                                  context.read<ShortsBloc>().add(
                                    ShortsPageChanged(index),
                                  );
                                }
                              },
                              itemBuilder: (context, index) {
                                if (index >= items.length) {
                                  return const ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(
                                          color: Colors.white70,
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final item = items[index];
                                return ShortReelItem(
                                  key: ValueKey('${item.id}:${item.videoUrl}'),
                                  short: item,
                                  active:
                                      _playbackActive &&
                                      state.activeIndex == index,
                                  likeLoading: state.loadingLikeIds.contains(
                                    item.id,
                                  ),
                                  onLike: () => context.read<ShortsBloc>().add(
                                    ShortsLikeToggled(item.id),
                                  ),
                                  onOpenDetail: () => _openContent(item),
                                );
                              },
                            )),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Container(
                                  height: topPad + 60,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.7),
                                        Colors.black.withValues(alpha: 0.3),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                  ),
                                  padding: EdgeInsetsDirectional.only(
                                    top: topPad + 12,
                                    start: 16,
                                  ),
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    'navigation.shorts'.tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (state.refreshing)
                              Positioned(
                                top: topPad,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  minHeight: 2,
                                  color: AppColors.primary,
                                  backgroundColor: Colors.transparent,
                                ),
                              ),
                            if (isDesktopPlatform)
                              Positioned(
                                top: topPad + 8,
                                right: 8,
                                child: IconButton(
                                  tooltip: 'shorts.refresh'.tr(),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  onPressed: _refresh,
                                ),
                              ),
                          ],
                        ),
              };
            },
          ),
          if (_loadingContent)
            Positioned.fill(
              child: AbsorbPointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'shorts.opening'.tr(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
