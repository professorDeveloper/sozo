import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/onboarding/data/genre_catalog.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/kind_style.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_tappable.dart';

/// Genres, as chips over the picked kinds' posters. Three or more to go on.
class OnboardingGenresPage extends StatefulWidget {
  const OnboardingGenresPage({super.key, this.catalog});

  final GenreCatalog? catalog;

  @override
  State<OnboardingGenresPage> createState() => _OnboardingGenresPageState();
}

class _OnboardingGenresPageState extends State<OnboardingGenresPage> {
  final OnboardingController _c = getIt<OnboardingController>();
  late final GenreCatalog _catalog = widget.catalog ?? getIt<GenreCatalog>();
  List<TasteGenre>? _genres;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final kinds = _c.kinds.isEmpty ? TasteKind.values : _c.kinds;
    final result = await _catalog.load(kinds);
    if (!mounted) return;
    await _c.refreshGenres(result.genres);
    if (!mounted) return;
    setState(() {
      _genres = result.genres;
      _offline = result.offline;
    });
  }

  void _toggle(TasteGenre genre) {
    final picked = _c.genres.contains(genre);
    final reaches =
        !picked && _c.genres.length + 1 == OnboardingController.minGenres;
    reaches ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    _c.toggleGenre(genre);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _c.kinds;
    final accent = kinds.isEmpty ? AppColors.primary : kinds.first.accent;
    final picked = _c.genres;
    final genres = _genres;
    return OnboardingScaffold(
      step: OnboardingStep.genres,
      glow: accent,
      background: _BlurredPosters(posters: postersFor(kinds)),
      onSkip: () => onboardingNext(context),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            sliver: SliverToBoxAdapter(
              child: OnboardingHeading(
                title: 'onboarding.genres_title'.tr(),
                subtitle: 'onboarding.genres_subtitle'.tr(),
                trailing: _Counter(count: picked.length, accent: accent),
              ),
            ),
          ),
          if (_offline)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'onboarding.genres_offline'.tr(),
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: OnbType.small - 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: genres == null
                  ? const _ChipsLoading()
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final (i, g) in genres.indexed)
                          ItemAppear(
                            index: i,
                            columns: 3,
                            staggerLimit: 24,
                            child: GenreChip(
                              genre: g,
                              accent: accent,
                              selected: picked.contains(g),
                              autofocus: isTvPlatform && i == 0,
                              onTap: () => _toggle(g),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      footer: OnboardingFocusButton(
        child: AppPrimaryButton(
          label: _c.canLeaveGenres
              ? 'onboarding.continue'.tr()
              : 'onboarding.genres_pick_more'.tr(
                  args: ['${OnboardingController.minGenres - picked.length}'],
                ),
          onPressed: _c.canLeaveGenres ? () => onboardingNext(context) : null,
        ),
      ),
    );
  }
}

/// "2 of 3" filling a ring, then a check once there are enough.
class _Counter extends StatelessWidget {
  const _Counter({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const min = OnboardingController.minGenres;
    final done = count >= min;
    final text = done
        ? 'onboarding.genres_count_done'.tr(args: ['$count'])
        : 'onboarding.genres_count'.tr(args: ['$count', '$min']);
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: done
                ? accent.withValues(alpha: 0.18)
                : const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: done ? accent : const Color(0x33FFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: (count / min).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 400),
                  curve: const Cubic(0.05, 0.7, 0.1, 1.0),
                  builder: (context, v, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: v,
                        strokeWidth: 2.5,
                        color: accent,
                        backgroundColor: const Color(0x33FFFFFF),
                      ),
                      if (done)
                        Icon(Icons.check_rounded, size: 14, color: accent),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: OnbType.small,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GenreChip extends StatefulWidget {
  const GenreChip({
    super.key,
    required this.genre,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.autofocus = false,
  });

  final TasteGenre genre;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final bool autofocus;

  @override
  State<GenreChip> createState() => _GenreChipState();
}

class _GenreChipState extends State<GenreChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void didUpdateWidget(GenreChip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected &&
        !MediaQuery.disableAnimationsOf(context)) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.genre;
    final on = widget.selected;
    final accent = widget.accent;
    final name = genreDisplayName(g);
    final h = isTvPlatform ? 52.0 : 44.0;
    return OnboardingTappable(
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      borderRadius: h / 2,
      selected: on,
      semanticLabel: name,
      ringColor: Colors.white,
      child: AnimatedBuilder(
        animation: _bounce,
        builder: (context, child) {
          final t = _bounce.value;
          final scale = 1 + 0.08 * (t < 0.4 ? t / 0.4 : (1 - t) / 0.6);
          return Transform.scale(scale: scale, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: const Cubic(0.05, 0.7, 0.1, 1.0),
          height: h,
          padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 16, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h / 2),
            gradient: on
                ? LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.black, 0.25)!],
                  )
                : null,
            color: on ? null : const Color(0x2EFFFFFF),
            border: Border.all(
              color: on ? accent : const Color(0x33FFFFFF),
              width: 1.2,
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 16,
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GenreThumb(genre: g, size: h - 12, accent: accent),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: OnbType.small + 1.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: on
                    ? const Padding(
                        padding: EdgeInsetsDirectional.only(start: 6),
                        child: Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreThumb extends StatelessWidget {
  const _GenreThumb({
    required this.genre,
    required this.size,
    required this.accent,
  });

  final TasteGenre genre;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hue = (genre.slug.hashCode % 360).abs().toDouble();
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1, hue, 0.6, 0.55).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.35).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Text(
          genreDisplayName(genre).characters.first.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.45,
          ),
        ),
      ),
    );
    final image = genre.image;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: image == null || image.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _ChipsLoading extends StatelessWidget {
  const _ChipsLoading();

  @override
  Widget build(BuildContext context) {
    const widths = [96.0, 124.0, 84.0, 140.0, 110.0, 92.0, 130.0, 104.0, 88.0];
    return Shimmer.fromColors(
      baseColor: const Color(0x22FFFFFF),
      highlightColor: const Color(0x44FFFFFF),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final w in widths)
            Container(
              width: w,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
        ],
      ),
    );
  }
}

/// The picked kinds' posters, tilted, blurred and darkened into a backdrop.
class _BlurredPosters extends StatelessWidget {
  const _BlurredPosters({required this.posters});

  final List<String> posters;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.rotate(
                angle: -0.12,
                child: Transform.scale(
                  scale: 1.3,
                  child: LayoutBuilder(
                    builder: (context, _) {
                      final size = MediaQuery.sizeOf(context);
                      final tileW = size.width / 3.2;
                      return SizedBox(
                        width: size.width * 1.2,
                        height: size.height * 1.2,
                        child: Wrap(
                          children: [
                            for (final p in posters)
                              SizedBox(
                                width: tileW,
                                height: tileW * 1.45,
                                child: Image.asset(
                                  p,
                                  fit: BoxFit.cover,
                                  cacheWidth: 200,
                                  excludeFromSemantics: true,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.72),
                  AppColors.background.withValues(alpha: 0.88),
                  AppColors.background,
                ],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
