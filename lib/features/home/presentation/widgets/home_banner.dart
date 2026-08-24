import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/banners/domain/entities/banner_item.dart';
import 'package:soplay/features/banners/presentation/bloc/banners_bloc.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/hero_slide.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/home/presentation/widgets/home_ui_helpers.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeBanner extends StatefulWidget {
  const HomeBanner({
    super.key,
    required this.slides,
    required this.topPadding,
    this.showSkeleton = true,
  });

  final List<HeroSlide> slides;
  final double topPadding;
  final bool showSkeleton;

  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  late final PageController _ctrl;
  Timer? _timer;
  int _page = 0;
  final Set<String> _trackedBanners = {};

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    // Desktop uses its own Akuse-style carousel with its own controller/timer.
    if (!isDesktopPlatform) _startTimer();
    _trackBannerView(0);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.slides.length < 2) return;
      if (!_ctrl.hasClients) return;
      // Auto-advancing on top of a drag or a fling yanked the slide out from
      // under the finger; skip this tick and take the next one instead.
      if (_ctrl.position.isScrollingNotifier.value) return;
      final next = (_page + 1) % widget.slides.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _trackBannerView(int index) {
    if (index >= widget.slides.length) return;
    final slide = widget.slides[index];
    if (slide is BannerHeroSlide && _trackedBanners.add(slide.banner.id)) {
      if (mounted) {
        context.read<BannersBloc>().add(BannersView(slide.banner.id));
      }
    }
  }

  Future<void> _onBannerTap(BannerItem item) async {
    context.read<BannersBloc>().add(BannersClick(item.id));
    final link = item.link;
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) {
      return widget.showSkeleton
          ? ShimmerWrapper(
              child: HomeBannerSkeleton(topPadding: widget.topPadding),
            )
          : const SizedBox.shrink();
    }

    if (isDesktopPlatform) {
      return _DesktopBanner(
        slides: widget.slides,
        topPadding: widget.topPadding,
        onBannerTap: _onBannerTap,
        onPageShown: _trackBannerView,
      );
    }

    return SizedBox(
      height: mobileHeroHeight(context),
      child: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            allowImplicitScrolling: true,
            physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
            itemCount: widget.slides.length,
            onPageChanged: (i) {
              _page = i;
              _trackBannerView(i);
            },
            itemBuilder: (_, index) {
              final slide = widget.slides[index];
              return AnimatedBuilder(
                animation: _ctrl,
                child: _SlideContent(slide: slide, onBannerTap: _onBannerTap),
                builder: (context, child) {
                  var page = index.toDouble();
                  if (_ctrl.position.haveDimensions) {
                    page = _ctrl.page ?? page;
                  }
                  final distance = (page - index).abs().clamp(0.0, 1.0);
                  final scale = 1.0 - (distance * 0.035);
                  final opacity = 1.0 - (distance * 0.18);

                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: child,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.slide, required this.onBannerTap});

  final HeroSlide slide;
  final Future<void> Function(BannerItem item) onBannerTap;

  @override
  Widget build(BuildContext context) {
    return switch (slide) {
      MovieHeroSlide(:final movie) => _MovieSlide(movie: movie),
      BannerHeroSlide(:final banner) => _BannerSlide(
          banner: banner,
          onTap: () => onBannerTap(banner),
        ),
    };
  }
}

class _MovieSlide extends StatelessWidget {
  const _MovieSlide({required this.movie});

  final MovieEntity movie;

  void _open(BuildContext context) {
    if (movie.url.isNotEmpty) {
      context.push(
        '/detail',
        extra: DetailArgs(contentUrl: movie.url, preview: movie),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Android TV: the hero is the first thing on Home and the D-pad's natural
    // landing spot, but a bare GestureDetector cannot hold focus. No scale — a
    // full-bleed slide has nowhere to grow into. Off TV: unchanged.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: () => _open(context),
        borderRadius: 0,
        scale: 1.0,
        child: _MovieSlideContent(movie: movie),
      );
    }

    return GestureDetector(
      onTap: () => _open(context),
      child: _MovieSlideContent(movie: movie),
    );
  }
}

class _MovieSlideContent extends StatelessWidget {
  const _MovieSlideContent({required this.movie});
  final MovieEntity movie;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HomeNetworkImage(
          url: movie.thumbnail,
          borderRadius: BorderRadius.zero,
          placeholderIcon: Icons.movie_creation_outlined,
        ),
        const _SlideOverlays(),
        Positioned(
          left: 20,
          right: 20,
          bottom: 34,
          child: _MovieInfo(movie: movie),
        ),
      ],
    );
  }
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({required this.banner, required this.onTap});

  final BannerItem banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: banner.imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, _) =>
              const HomeImagePlaceholder(icon: Icons.image_outlined),
          errorWidget: (_, _, _) =>
              const HomeImagePlaceholder(icon: Icons.image_not_supported_outlined),
        ),
        const _SlideOverlays(),
        Positioned(
          left: 20,
          right: 20,
          bottom: 34,
          child: _BannerInfo(banner: banner),
        ),
      ],
    );

    // Same reasoning as _MovieSlide: the promo slide shares the hero pager and
    // must be a D-pad stop on TV. Off TV: unchanged.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: onTap,
        borderRadius: 0,
        scale: 1.0,
        child: content,
      );
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}

class _SlideOverlays extends StatelessWidget {
  const _SlideOverlays();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Color(0xBB000000), Color(0x00000000)],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x55000000), Color(0x00000000)],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SizedBox(
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.background,
                    AppColors.background.withValues(alpha: 0.733),
                    AppColors.background.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MovieInfo extends StatelessWidget {
  const _MovieInfo({required this.movie});

  final MovieEntity movie;

  @override
  Widget build(BuildContext context) {
    final meta = movieMetaLabels(movie);
    final description = movieDescription(movie);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gaps ride with their content: unconditional ones left a hole above
        // the title on slides with no chips, so titles sat at different
        // heights as the hero paged.
        if (meta.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: meta.take(4).map((m) => _MetaChip(label: m)).toList(),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          movieTitle(movie),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: -0.3,
            shadows: [
              Shadow(
                color: Colors.black87,
                blurRadius: 16,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.08,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _BannerInfo extends StatelessWidget {
  const _BannerInfo({required this.banner});

  final BannerItem banner;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          banner.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: -0.3,
            shadows: [
              Shadow(
                color: Colors.black87,
                blurRadius: 16,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        if (banner.subtitle != null && banner.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            banner.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.08,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Desktop banner — Sozo-Desktop / Akuse style: rounded 450px card, blurred
// Ken Burns backdrop, crisp right poster, Play + More Info buttons. Both
// movie and CMS-banner slides are supported.
// ─────────────────────────────────────────────────────────────────────────

const double _kDesktopBannerHeight = 450.0;
const double _kDesktopBannerRadius = 18.0;

class _DesktopBanner extends StatefulWidget {
  const _DesktopBanner({
    required this.slides,
    required this.topPadding,
    required this.onBannerTap,
    required this.onPageShown,
  });

  final List<HeroSlide> slides;
  final double topPadding;
  final Future<void> Function(BannerItem item) onBannerTap;
  final ValueChanged<int> onPageShown;

  @override
  State<_DesktopBanner> createState() => _DesktopBannerState();
}

class _DesktopBannerState extends State<_DesktopBanner> {
  late final PageController _ctrl;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 12500), () {
      if (!mounted || !_ctrl.hasClients || widget.slides.length < 2) return;
      final next = (_index + 1) % widget.slides.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
      _startAutoPlay();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, widget.topPadding + 72, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _kDesktopBannerHeight,
            // No drop shadow: the slide already dissolves its edges into the
            // page background (see _EdgeBlend), so a shadow would fight that and
            // make the hero read as a card floating above the feed.
            child: PageView.builder(
              controller: _ctrl,
              itemCount: widget.slides.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                widget.onPageShown(i);
              },
              itemBuilder: (_, i) => _DesktopSlide(
                slide: widget.slides[i],
                onBannerTap: widget.onBannerTap,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.slides.length, (i) {
              final active = i == _index;
              return GestureDetector(
                onTap: () => _ctrl.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: active ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.textPrimary : AppColors.textHint,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DesktopSlide extends StatefulWidget {
  const _DesktopSlide({required this.slide, required this.onBannerTap});

  final HeroSlide slide;
  final Future<void> Function(BannerItem item) onBannerTap;

  @override
  State<_DesktopSlide> createState() => _DesktopSlideState();
}

class _DesktopSlideState extends State<_DesktopSlide>
    with TickerProviderStateMixin {
  late final AnimationController _in;
  late final AnimationController _kb;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _zoom;

  // The home feed ships movies without a synopsis; VidAPI returns it from the
  // detail endpoint, so fetch it lazily for the banner text.
  String _desc = '';

  Future<void> _fetchDesc(MovieEntity movie) async {
    if (movie.url.isEmpty) return;
    final result = await getIt<GetDetailUseCase>()(movie.url);
    if (!mounted) return;
    if (result case Success(:final value)) {
      if (value.description.trim().isNotEmpty) {
        setState(() => _desc = value.description);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final slide = widget.slide;
    if (slide is MovieHeroSlide) {
      _desc = slide.movie.description.trim();
      if (_desc.isEmpty) _fetchDesc(slide.movie);
    }
    _in = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = CurvedAnimation(parent: _in, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _in, curve: Curves.easeOut));
    _kb = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _zoom = Tween<double>(begin: 1.05, end: 1.16)
        .animate(CurvedAnimation(parent: _kb, curve: Curves.easeOut));
    _kb.forward();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _in.forward();
    });
  }

  @override
  void dispose() {
    _in.dispose();
    _kb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    final isBanner = slide is BannerHeroSlide;
    final backdrop = switch (slide) {
      MovieHeroSlide(:final movie) => movie.thumbnail,
      BannerHeroSlide(:final banner) => banner.imageUrl,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kDesktopBannerRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop: blurred poster (movie) or crisp wide image (banner).
          AnimatedBuilder(
            animation: _zoom,
            builder: (_, child) =>
                Transform.scale(scale: _zoom.value, child: child),
            child: isBanner
                ? HomeNetworkImage(
                    url: backdrop,
                    borderRadius: BorderRadius.zero,
                    placeholderIcon: Icons.movie_creation_outlined,
                  )
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: HomeNetworkImage(
                      url: backdrop,
                      borderRadius: BorderRadius.zero,
                      placeholderIcon: Icons.movie_creation_outlined,
                    ),
                  ),
          ),
          const Positioned.fill(child: ColoredBox(color: Color(0x40000000))),
          // Crisp poster on the right (movie slides only).
          if (!isBanner)
            Positioned(
              right: 40,
              top: 34,
              bottom: 34,
              child: FadeTransition(
                opacity: _opacity,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: HomeNetworkImage(
                      url: backdrop,
                      borderRadius: BorderRadius.zero,
                      placeholderIcon: Icons.movie_creation_outlined,
                    ),
                  ),
                ),
              ),
            ),
          // Scrims for text legibility. Same rule as _EdgeBlend directly
          // below: every stop is the page background at some opacity, so the
          // scrim follows the theme instead of freezing at #181818.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.background.withValues(alpha: 0.949),
                    AppColors.background.withValues(alpha: 0.8),
                    AppColors.background.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.42, 0.72],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: _EdgeBlend()),
          // Content.
          Positioned(
            left: 34,
            right: 34,
            bottom: 30,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: FadeTransition(
                  opacity: _opacity,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: _content(context, slide),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, HeroSlide slide) {
    switch (slide) {
      case MovieHeroSlide(:final movie):
        final meta = movieMetaLabels(movie);
        final desc = _desc;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (meta.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    meta.take(4).map((m) => _MetaChip(label: m)).toList(),
              ),
            const SizedBox(height: 12),
            Text(
              movieTitle(movie),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1.12,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1, 1)),
                ],
              ),
            ),
            if (desc.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                _BannerButton(
                  label: 'player.play'.tr(),
                  icon: Icons.play_arrow_rounded,
                  primary: true,
                  onTap: () => _openMovie(context, movie),
                ),
                const SizedBox(width: 10),
                _BannerButton(
                  label: 'home.more_info'.tr(),
                  icon: Icons.info_outline_rounded,
                  primary: false,
                  onTap: () => _openMovie(context, movie),
                ),
              ],
            ),
          ],
        );
      case BannerHeroSlide(:final banner):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              banner.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1.12,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1, 1)),
                ],
              ),
            ),
            if (banner.subtitle != null && banner.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                banner.subtitle!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _BannerButton(
              label: 'home.more_info'.tr(),
              icon: Icons.open_in_new_rounded,
              primary: true,
              onTap: () => widget.onBannerTap(banner),
            ),
          ],
        );
    }
  }

  void _openMovie(BuildContext context, MovieEntity movie) {
    if (movie.url.isNotEmpty) {
      context.push(
        '/detail',
        extra: DetailArgs(contentUrl: movie.url, preview: movie),
      );
    }
  }
}

/// Dissolves the card's four edges into the page background instead of ending
/// them on a hard rectangle — the bottom carries the most, so the hero reads as
/// part of the feed rather than a poster pasted on top of it.
class _EdgeBlend extends StatelessWidget {
  const _EdgeBlend();

  /// Every stop is the page background at some opacity — that is the whole
  /// trick, the card fades into whatever the feed sits on. So they are derived
  /// from [AppColors.background] rather than written as literals: under AMOLED
  /// the feed is true black, and a hard-coded #181818 edge would leave a grey
  /// halo glowing around the hero.
  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background;
    final clear = bg.withValues(alpha: 0.0);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bottom: the card doesn't end, it dissolves into the feed.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [bg, bg.withValues(alpha: 0.8), clear],
                stops: const [0.0, 0.14, 0.5],
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [bg.withValues(alpha: 0.8), clear],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [bg.withValues(alpha: 0.702), clear],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg.withValues(alpha: 0.6), clear],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerButton extends StatefulWidget {
  const _BannerButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_BannerButton> createState() => _BannerButtonState();
}

class _BannerButtonState extends State<_BannerButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    // Play stays white — it sits on artwork and needs the highest contrast
    // there is. The second action is where the accent belongs: tinted glass,
    // so the row says which theme is on without ever fighting the poster.
    final bg = primary
        ? Colors.white
        : AppColors.primary.withValues(alpha: _hover ? 0.46 : 0.30);
    final fg = primary ? Colors.black : Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Container(
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: primary ? 24 : 20),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: fg, size: primary ? 24 : 20),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
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

/// Height of the mobile hero. The skeleton MUST use the same number: it used
/// to clamp to 460–580 against the real 440–480, so the whole feed jumped by up
/// to 100px the moment the banners arrived.
double mobileHeroHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.63).clamp(440.0, 480.0);

class HomeBannerSkeleton extends StatelessWidget {
  const HomeBannerSkeleton({super.key, required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24, topPadding + 72, 24, 22),
        child: const HomeSkeletonBox(
          width: double.infinity,
          height: _kDesktopBannerHeight,
          radius: _kDesktopBannerRadius,
        ),
      );
    }

    // Was a box painted in the page background colour — indistinguishable from
    // an empty screen, so the load read as "nothing is happening".
    return HomeSkeletonBox(
      width: double.infinity,
      height: mobileHeroHeight(context),
      radius: 0,
    );
  }
}
