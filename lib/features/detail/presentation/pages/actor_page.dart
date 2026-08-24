import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_event.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/home/presentation/widgets/home_ui_helpers.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

class ActorArgs {
  final String id;
  final String name;
  final String image;
  final String? role;

  const ActorArgs({
    required this.name,
    this.image = '',
    this.role,
    this.id = '',
  });
}

class ActorPage extends StatelessWidget {
  const ActorPage({super.key, required this.args});

  final ActorArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<ViewAllBloc>()..add(ViewAllLoad(key: 'actor', slug:args.name)),
      child: _ActorScaffold(args: args),
    );
  }
}

class _ActorScaffold extends StatefulWidget {
  const _ActorScaffold({required this.args});

  final ActorArgs args;

  @override
  State<_ActorScaffold> createState() => _ActorScaffoldState();
}

class _ActorScaffoldState extends State<_ActorScaffold> {
  late final ScrollController _scroll;
  final ValueNotifier<double> _collapse = ValueNotifier<double>(0);
  // Shown until the poster's palette is extracted (and kept when there is no
  // poster). Follows the chosen accent rather than the old hard-coded brand
  // red, so the hero never opens in a colour the app no longer uses.
  Color _accent = AppColors.primaryDark;
  Color _accentDeep = _deepen(AppColors.primary);

  /// The very dark, desaturated floor a hero gradient falls to. The old literal
  /// #3A0306 is what this produces for the default red.
  static Color _deepen(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 0.94).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.265).clamp(0.0, 1.0))
        .toColor();
  }

  static const double _heroExtent = 320;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);
    _resolvePalette();
  }

  Future<void> _resolvePalette() async {
    if (widget.args.image.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(widget.args.image),
        size: const Size(120, 120),
        maximumColorCount: 12,
      );
      final dominant =
          palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color ??
          _accent;
      if (!mounted) return;
      setState(() {
        _accent = dominant;
        _accentDeep = Color.lerp(dominant, Colors.black, 0.7) ?? _accentDeep;
      });
    } catch (_) {
    }
  }

  void _onScroll() {
    final v = (_scroll.offset / 180).clamp(0.0, 1.0);
    if ((v - _collapse.value).abs() > 0.01) _collapse.value = v;

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
    _collapse.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            BlocConsumer<ViewAllBloc, ViewAllState>(
              listener: (context, state) => _maybeAutoFill(state),
              builder: (context, state) {
                return CustomScrollView(
                  controller: _scroll,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _ActorHero(
                        name: widget.args.name,
                        image: widget.args.image,
                        topPad: topPad,
                        height: _heroExtent + topPad,
                        accent: _accent,
                        accentDeep: _accentDeep,
                      ),
                    ),
                    if (state is ViewAllLoading)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      )
                    else if (state is ViewAllError)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 60,
                            horizontal: 32,
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: AppColors.textHint,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  state.mesage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (state is ViewAllLoaded)
                      ..._buildLoadedSlivers(state),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).bottom + 24,
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _collapse,
                builder: (_, c, _) => _ActorTopBar(
                  collapse: c,
                  title: widget.args.name,
                  onBack: _goBack,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLoadedSlivers(ViewAllLoaded state) {
    if (state.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.movie_outlined,
                    color: AppColors.textHint,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'detail.no_films'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(
                'detail.filmography'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${state.items.length})',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _ActorMovieCard(movie: state.items[i]),
            childCount: state.items.length,
          ),
          gridDelegate: responsiveGridDelegate(
            mobileCrossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 8,
            childAspectRatio: 0.52,
          ),
        ),
      ),
      if (state.isLoadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

class _ActorHero extends StatelessWidget {
  const _ActorHero({
    required this.name,
    required this.image,
    required this.topPad,
    required this.height,
    required this.accent,
    required this.accentDeep,
  });

  final String name;
  final String image;
  final double topPad;
  final double height;
  final Color accent;
  final Color accentDeep;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.55),
                  accentDeep.withValues(alpha: 0.85),
                  AppColors.background,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: Opacity(
              opacity: 0.45,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [accent.withValues(alpha: 0.6), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -60,
            child: Opacity(
              opacity: 0.35,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accentDeep.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topPad + 56),
            child: Column(
              children: [
                _AvatarRing(image: image, name: name, accent: accent),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'detail.actor'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.image,
    required this.name,
    required this.accent,
  });

  final String image;
  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: 132,
      height: 132,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.5) ?? accent],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.45),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
          border: Border.all(color: AppColors.background, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: image.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _AvatarInitials(initials: initials),
                  Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _AvatarInitials(initials: initials),
                    // Initials snapping to a photo at 132px is the loudest
                    // thing on the screen; fade instead.
                    frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                        child: child,
                      );
                    },
                  ),
                ],
              )
            : _AvatarInitials(initials: initials),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final t = name.trim();
    return t.isNotEmpty ? t[0].toUpperCase() : '?';
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 36,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActorTopBar extends StatelessWidget {
  const _ActorTopBar({
    required this.collapse,
    required this.title,
    required this.onBack,
  });

  final double collapse;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final solid = Curves.easeIn.transform(collapse).clamp(0.0, 1.0);
    final titleOp = ((collapse - 0.5) / 0.4).clamp(0.0, 1.0);

    return Stack(
      children: [
        IgnorePointer(
          child: Opacity(
            opacity: solid,
            child: Container(
              height: topPad + kToolbarHeight,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.96),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.divider.withValues(alpha: solid),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topPad + 6, left: 4, right: 8),
          child: SizedBox(
            height: kToolbarHeight - 12,
            child: Row(
              children: [
                // The hero behind this bar is tinted from the actor's photo and
                // can come out pale, which left a bare white glyph with nothing
                // to sit on. The disc keeps it readable whatever the palette.
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.42 * (1 - solid)),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onBack,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: titleOp,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActorMovieCard extends StatelessWidget {
  const _ActorMovieCard({required this.movie});

  final MovieEntity movie;

  @override
  Widget build(BuildContext context) {
    final quality = primaryQuality(movie);
    return HoverTap(
      onTap: () {
        if (movie.url.isNotEmpty) {
          context.push(
            '/detail',
            extra: DetailArgs(contentUrl: movie.url, preview: movie),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HomeNetworkImage(
                    url: movie.thumbnail,
                    borderRadius: BorderRadius.zero,
                    placeholderIcon: Icons.movie_outlined,
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xAA000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (quality != null)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          quality,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            movieTitle(movie),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          // Always laid out: the poster is the Expanded child, so a missing
          // year made that card's artwork taller than the rest of the row.
          Text(
            movie.year?.toString() ?? '',
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
