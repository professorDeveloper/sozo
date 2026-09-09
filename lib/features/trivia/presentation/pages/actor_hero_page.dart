import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/actor_profile_entity.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/domain/entities/challenge_entity.dart';
import 'package:soplay/features/trivia/domain/entities/top_fan_entity.dart';
import 'package:soplay/features/trivia/domain/usecases/create_challenge_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_actor_profile_usecase.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_state.dart';
import 'package:soplay/features/trivia/presentation/trivia_args.dart';
import 'package:soplay/features/trivia/presentation/widgets/cast_card.dart';
import 'package:soplay/features/trivia/presentation/widgets/top_fans_strip.dart';

/// The selected actor / character hero: a full-bleed blurred backdrop, the
/// circular profile that receives the Hero flight from the cast card, a Top Fans
/// preview strip, a filmography rail, and a sticky "Start Fan Test" bottom bar.
class ActorHeroPage extends StatefulWidget {
  const ActorHeroPage({super.key, required this.person});

  final CastPersonEntity person;

  @override
  State<ActorHeroPage> createState() => _ActorHeroPageState();
}

class _ActorHeroPageState extends State<ActorHeroPage> {
  /// Held on the state (not created inline in `BlocProvider(create:)`) so the
  /// strip can be refetched after a round: the game route replaces itself with
  /// the result route, so this Element survives and would otherwise keep
  /// showing the pre-round standings.
  late final TopFansBloc _topFansBloc;

  ActorProfileEntity? _profile;
  bool _loading = true;
  String? _error;
  bool _creatingChallenge = false;

  CastPersonEntity get _person => widget.person;

  @override
  void initState() {
    super.initState();
    _topFansBloc = getIt<TopFansBloc>();
    _requestTopFans();
    _load();
  }

  @override
  void dispose() {
    _topFansBloc.close();
    super.dispose();
  }

  void _requestTopFans() {
    _topFansBloc.add(TopFansRequested(actorId: _person.id, kind: _person.kind));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await getIt<GetActorProfileUseCase>()(
      id: _person.id,
      kind: _person.kind,
    );
    if (!mounted) return;
    switch (result) {
      case Success<ActorProfileEntity>(:final value):
        setState(() {
          _profile = value;
          _loading = false;
        });
      case Failure<ActorProfileEntity>(:final error):
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  String get _backdropUrl {
    final film = _profile?.filmography;
    if (film != null && film.isNotEmpty && film.first.poster.isNotEmpty) {
      return film.first.poster;
    }
    return _person.profileUrl;
  }

  int get _titleCount =>
      _profile?.filmography.length ?? _person.knownFor.length;

  Future<void> _startFanTest() async {
    HapticFeedback.mediumImpact();
    await openGame(
      context,
      GameArgs(
        actorRef: ActorRefEntity(
          id: _person.id,
          kind: _person.kind,
          name: _person.name,
          profileUrl: _person.profileUrl,
        ),
      ),
    );
    // The round just scored: pull the standings the server rewrote.
    if (mounted) _requestTopFans();
  }

  Future<void> _challengeFriend() async {
    if (_creatingChallenge) return;
    HapticFeedback.lightImpact();
    setState(() => _creatingChallenge = true);
    final result = await getIt<CreateChallengeUseCase>()(
      mode: kFanTestMode,
      actorId: _person.id,
      kind: _person.kind,
    );
    if (!mounted) return;
    setState(() => _creatingChallenge = false);
    switch (result) {
      case Success<ChallengeEntity>(:final value):
        final link = value.deepLink.isNotEmpty ? value.deepLink : value.webLink;
        Share.share(
          '${'trivia.challenge_share_text'.tr(namedArgs: {'name': _person.name})}\n$link',
        );
      case Failure<ChallengeEntity>(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppColors.surface,
          ),
        );
    }
  }

  void _openTopFans() {
    openTopFans(
      context,
      TopFansArgs(actorId: _person.id, kind: _person.kind),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.paddingOf(context).top;

    return BlocProvider<TopFansBloc>.value(
      value: _topFansBloc,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            _Backdrop(url: _backdropUrl),
            Positioned.fill(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _HeroHead(
                      person: _person,
                      profile: _profile,
                      loading: _loading,
                      titleCount: _titleCount,
                      topSafe: topSafe,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: _TopFansSection(onTap: _openTopFans),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FilmographySection(
                      loading: _loading,
                      items: _profile?.filmography ?? const [],
                    ),
                  ),
                  if (_error != null && _profile == null)
                    SliverToBoxAdapter(
                      child: _InlineError(message: _error!, onRetry: _load),
                    ),
                  // Exactly the sticky bar's own height (+ a 12 breathing gap),
                  // derived from its geometry constants — never a magic number.
                  SliverToBoxAdapter(
                    child: SizedBox(height: _actionBarHeight(context) + 12),
                  ),
                ],
              ),
            ),
            _FloatingBack(topSafe: topSafe),
            _StickyBar(
              onStart: _startFanTest,
              onChallenge: _challengeFriend,
              creatingChallenge: _creatingChallenge,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backdrop
// ─────────────────────────────────────────────────────────────────────────────

/// Mirrors the shipped detail hero (`DetailHeroBackground`): sharp artwork, a
/// top black gradient so the back button stays legible, and a tall bottom scrim
/// that dissolves into the page colour. No blur wash — the app never blurs a
/// hero backdrop, and doing so is what made this screen read as a different
/// product.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});
  final String url;

  static const double _height = 460;

  /// Tall enough to cover the name / subtitle / chip block (which starts around
  /// y = 250) while leaving the artwork readable behind the profile circle.
  static const double _scrimHeight = 300;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, _) =>
                  ColoredBox(color: AppColors.surfaceVariant),
              errorWidget: (_, _, _) =>
                  ColoredBox(color: AppColors.surfaceVariant),
            )
          else
            ColoredBox(color: AppColors.surfaceVariant),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, 0.4),
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: _scrimHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    // Every stop is the page background at falling opacity,
                    // so the backdrop dissolves into whatever the page is —
                    // #181818 or true black.
                    colors: [
                      AppColors.background,
                      AppColors.background.withValues(alpha: 0.933),
                      AppColors.background.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
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

// ─────────────────────────────────────────────────────────────────────────────
// Hero head (profile circle + name + meta)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHead extends StatelessWidget {
  const _HeroHead({
    required this.person,
    required this.profile,
    required this.loading,
    required this.titleCount,
    required this.topSafe,
  });

  final CastPersonEntity person;
  final ActorProfileEntity? profile;
  final bool loading;
  final int titleCount;
  final double topSafe;

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? person.name;
    final birthplace = profile?.birthplace ?? '';
    final knownFor = person.knownFor
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .join(' · ');
    final subtitle = birthplace.isNotEmpty ? birthplace : knownFor;

    return Padding(
      // The back button sits at topSafe + 8 and is 38 high, so topSafe + 62
      // leaves an 16px gap under it without stranding the profile circle in the
      // middle of an empty backdrop.
      padding: EdgeInsets.only(top: topSafe + 62, left: 24, right: 24),
      child: Column(
        children: [
          SizedBox(
            width: 128,
            height: 128,
            child: Hero(
              tag: CastCard.heroTag(person),
              child: CastAvatar(
                url: person.profileUrl,
                name: name,
                highlightRing: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
              ],
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            const ShimmerWrapper(
              child: HomeSkeletonBox(width: 160, height: 12, radius: 4),
            ),
          ] else if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _TitlesChip(count: titleCount, loading: loading),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _TitlesChip extends StatelessWidget {
  const _TitlesChip({required this.count, required this.loading});
  final int count;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.film_fill,
              color: AppColors.primaryLight, size: 14),
          const SizedBox(width: 7),
          Text(
            loading
                ? '…'
                : 'trivia.n_titles'.tr(namedArgs: {'count': '$count'}),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top fans section (reads TopFansBloc)
// ─────────────────────────────────────────────────────────────────────────────

class _TopFansSection extends StatelessWidget {
  const _TopFansSection({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TopFansBloc, TopFansState>(
      builder: (context, state) {
        final loading = state.status == TopFansStatus.loading ||
            state.status == TopFansStatus.initial;
        final fans = state.fanStat?.topFans ?? const <TopFanEntity>[];
        final myId = _currentUserId();
        int? myRank;
        if (myId != null) {
          for (final f in fans) {
            if (f.userId == myId) {
              myRank = f.rank;
              break;
            }
          }
        }
        return TopFansStrip(
          topFans: fans,
          myRank: myRank,
          loading: loading,
          onTap: onTap,
        );
      },
    );
  }
}

String? _currentUserId() {
  final state = getIt<AuthBloc>().state;
  return state is AuthLoaded ? state.token.user.id : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Filmography rail
// ─────────────────────────────────────────────────────────────────────────────

// Filmography rail geometry. The rail height is fixed and the poster is
// `Expanded`, exactly like the home rails: when the system font scale grows, the
// text block takes what it needs and the poster gives up the difference, so the
// rail cannot overflow at any textScale. (The old code pinned the poster with
// AspectRatio(2/3) inside a 196 box — 174 + 7 + 14.65 + 12.89 = 208.5 at scale
// 1.0 and 211.3 at the owner's scale 1.1, which is the reported 15px overflow.)
const double _kFilmCardWidth = 116;
const double _kFilmRailHeight = 208;
const double _kFilmPosterGap = 7;

/// Poster height at textScale 1.0:
/// 208 - (7 + 12.5*1.25 + 11*1.3) = 208 - 36.925 = 171.075 -> ratio 116/171.1 =
/// 0.678, inside the app's emergent 0.68-0.70 poster band. The skeleton uses the
/// same number so loading and loaded states do not jump.
const double _kFilmPosterHeight = 171;

class _FilmographySection extends StatelessWidget {
  const _FilmographySection({required this.loading, required this.items});

  final bool loading;
  final List<FilmographyItemEntity> items;

  @override
  Widget build(BuildContext context) {
    if (!loading && items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(13, 18, 16, 14),
          child: Text(
            'trivia.filmography'.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        SizedBox(
          height: _kFilmRailHeight,
          child: loading
              ? _railSkeleton()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _PosterCard(item: items[i]),
                ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _railSkeleton() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      // Mirrors the real card's structure (poster / title / year) rather than
      // being one tall block: 171 + 7 + 12 + 4 + 10 = 204 <= 208.
      itemBuilder: (_, _) => const ShimmerWrapper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSkeletonBox(
              width: _kFilmCardWidth,
              height: _kFilmPosterHeight,
              radius: 10,
            ),
            SizedBox(height: _kFilmPosterGap),
            HomeSkeletonBox(width: 92, height: 12, radius: 4),
            SizedBox(height: 4),
            HomeSkeletonBox(width: 44, height: 10, radius: 4),
          ],
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item});
  final FilmographyItemEntity item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kFilmCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.poster.isEmpty
                  ? const HomeImagePlaceholder(icon: Icons.movie_outlined)
                  : CachedNetworkImage(
                      imageUrl: item.poster,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (_, _) => const HomeImagePlaceholder(
                        icon: Icons.movie_outlined,
                      ),
                      errorWidget: (_, _, _) => const HomeImagePlaceholder(
                        icon: Icons.movie_outlined,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: _kFilmPosterGap),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          // Always rendered, even when the year is missing, so every poster in
          // the rail resolves to the same height.
          Text(
            item.year.isEmpty ? ' ' : item.year,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chrome: back button, sticky CTA bar, inline error
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingBack extends StatelessWidget {
  const _FloatingBack({required this.topSafe});
  final double topSafe;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topSafe + 8,
      left: 8,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 38,
              height: 38,
              color: Colors.black.withValues(alpha: 0.38),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

// Sticky action-bar geometry. The scroll view's bottom spacer is derived from
// these constants so the last row of content clears the bar by exactly one gap
// — replacing the old hardcoded 140, which left a visible void.
const double _kActionButtonHeight = 46;
const double _kActionBarVPadding = 14;

/// 14 + 46 + 14 + safe-area = 74 + safe-area.
double _actionBarHeight(BuildContext context) =>
    _kActionBarVPadding * 2 +
    _kActionButtonHeight +
    MediaQuery.paddingOf(context).bottom;

class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.onStart,
    required this.onChallenge,
    required this.creatingChallenge,
  });

  final VoidCallback onStart;
  final VoidCallback onChallenge;
  final bool creatingChallenge;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          _kActionBarVPadding,
          16,
          _kActionBarVPadding + bottomSafe,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background.withValues(alpha: 0),
              AppColors.background,
            ],
            stops: const [0.0, 0.35],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _PrimaryButton(onTap: onStart),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _SecondaryButton(
                onTap: onChallenge,
                busy: creatingChallenge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: _kActionButtonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'trivia.start_fan_test'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.onTap, required this.busy});
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: _kActionButtonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.person_2_fill,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'trivia.challenge_friend'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'general.retry'.tr(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
