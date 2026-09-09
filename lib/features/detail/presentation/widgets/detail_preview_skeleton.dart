import 'package:flutter/material.dart';
import 'package:soplay/core/widgets/shimmer_wrapper.dart';

import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'detail_hero.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';

/// The detail page while it is still loading, drawn from what the caller
/// already knew.
///
/// ## Why this replaces the shimmer
///
/// Tapping a poster hands the detail page a [MovieEntity]: the artwork, the
/// title, the year, the rating. All of it is correct and none of it needs a
/// request. The page nevertheless drew a full grey skeleton over the lot,
/// which had two costs.
///
/// The obvious one is that it looks like nothing is there when in fact most
/// of the header is known. The subtler one is that it broke the transition:
/// a Hero flight needs something to land ON, and a shimmering rectangle is
/// not the poster, so the image flew out of the grid and dissolved into a
/// placeholder — the exact opposite of the continuity the flight exists to
/// create.
///
/// So the parts that are known are drawn for real, and only what is genuinely
/// unknown — the meta line, the genres, the synopsis, the grid under the tabs
/// — shimmers. When the response lands, the header does not change at all; the
/// grey blocks below it fill in. Nothing jumps, because nothing that was
/// already correct is redrawn.
///
/// ## What the blocks below the header track
///
/// The page opens on the 'Similar' tab, so the first thing the response paints
/// under the tab strip is DetailRelatedSection — see
/// `detail_related.dart`. The placeholders here copy that grid's delegate,
/// padding and cell shape, and the strip above it copies `_TabBarDelegate` in
/// `detail_page.dart`. Change the real grid and this follows it (so does
/// `_PosterGridSk` in `detail_skeleton.dart`), or the placeholder stops being
/// a placeholder and becomes a different layout that gets replaced.
class DetailPreviewSkeleton extends StatelessWidget {
  const DetailPreviewSkeleton({
    super.key,
    required this.preview,
    this.heroTag,
  });

  final MovieEntity preview;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    // Exactly the loaded page's header height, from the same function. Half a
    // point of disagreement here is a visible jolt, because the poster has
    // just been animated into this precise rectangle.
    final height = detailHeroHeight(context);
    final flying = heroTag != null;

    // ONE shimmer for the whole tree, not one per block, and the app's own —
    // see ShimmerWrapper. Each placeholder used to carry its own
    // Shimmer.fromColors with a highlight DARKER than its base, so thirty
    // controllers ran out of phase and each swept a dark notch backwards
    // across its own rectangle.
    return ShimmerWrapper(
      child: CustomScrollView(
      // The list underneath is placeholder content; letting somebody fling it
      // and then swapping in the real page mid-scroll is disorienting.
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: height,
            // Identical to the loaded page's header, deliberately: this widget
            // exists to be indistinguishable from what replaces it.
            child: DetailHeroBackground(
              thumbnail: preview.thumbnail,
              title: preview.title,
              heroTag: heroTag,
            ),
          ),
        ),
        SliverToBoxAdapter(
          // The placeholders arrive after the poster, not with it. Painted
          // from the first frame they are grey bars sitting under an image
          // that is still crossing the screen, which is exactly the
          // "something is covering it" the flight was meant to avoid.
          child: _LateFade(hasFlight: flying, child: const _HeaderSk()),
        ),
        SliverToBoxAdapter(
          child: _LateFade(hasFlight: flying, child: const _TabStripSk()),
        ),
        SliverPadding(
          // The loaded page's own padding around the tab body.
          padding: EdgeInsets.only(
            top: 4,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
          ),
          sliver: SliverToBoxAdapter(
            child: _LateFade(hasFlight: flying, child: const _RelatedGridSk()),
          ),
        ),
      ],
    ),
    );
  }
}

/// The block DetailContentHeader occupies, in the order it lays it out: meta
/// line, genres, synopsis, action row. Drawn action-row-first it was the same
/// bars in the wrong places, so the Play button moved when the real header
/// arrived — the one shape on this screen the eye is already aiming at.
class _HeaderSk extends StatelessWidget {
  const _HeaderSk();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _Block(width: 160, height: 13),
          SizedBox(height: 10),
          // Chip height is the genre label (12pt) plus its 5pt vertical
          // padding, and the 6pt radius is the chip's own.
          Row(
            children: [
              _Block(width: 62, height: 24, radius: 6),
              SizedBox(width: 6),
              _Block(width: 84, height: 24, radius: 6),
              SizedBox(width: 6),
              _Block(width: 70, height: 24, radius: 6),
            ],
          ),
          SizedBox(height: 14),
          // Three bars over the synopsis' three collapsed line boxes: 13pt at
          // height 1.5, so ~19.5pt of line per bar-and-gap.
          _Block(height: 12),
          SizedBox(height: 11),
          _Block(height: 12),
          SizedBox(height: 11),
          _Block(width: 220, height: 12),
          SizedBox(height: 18),
          // A real, correctly sized shape rather than a bar: the Play button
          // appears in this exact rectangle a moment later, radius included.
          Row(
            children: [
              Expanded(child: _Block(height: 46, radius: kButtonRadius)),
              SizedBox(width: 10),
              _Block(width: 46, height: 46, radius: kButtonRadius),
            ],
          ),
        ],
      ),
    );
  }
}

/// The pinned tab strip.
///
/// Nothing stood here at all, so the grid below started 49pt too high and the
/// whole page slid up the moment the strip appeared.
class _TabStripSk extends StatelessWidget {
  const _TabStripSk();

  /// From [AppTabBar], not a fourth copy of the arithmetic.
  ///
  /// Three places used to compute this strip's height independently — the
  /// pinned delegate, this skeleton and the no-preview one — and one of them
  /// was wrong, which put every sliver below the header 2pt out. The label
  /// box and the indicator stay separate here because the bars are drawn
  /// inside the first and the underline sits below it.
  static const double _labelHeight =
      AppTabBar.stripHeight - AppTabBar.indicatorWeight;
  static const double _indicatorWeight = AppTabBar.indicatorWeight;
  static const double _dividerHeight = AppTabBar.dividerHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(
          height: _labelHeight,
          child: Padding(
            // Matches _TabBarDelegate's leading inset and the TabBar's own
            // 14pt label padding, so the bars land where the labels will.
            padding: EdgeInsetsDirectional.only(start: 8),
            child: Row(
              children: [
                _TabLabelSk(width: 48),
                _TabLabelSk(width: 58),
                _TabLabelSk(width: 62),
              ],
            ),
          ),
        ),
        const SizedBox(height: _indicatorWeight),
        Container(height: _dividerHeight, color: AppColors.divider),
      ],
    );
  }
}

class _TabLabelSk extends StatelessWidget {
  const _TabLabelSk({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _Block(width: width, height: 11),
    );
  }
}

/// The 'Similar' grid the page opens on — same delegate, padding and cell
/// shape as DetailRelatedSection in `detail_related.dart`.
class _RelatedGridSk extends StatelessWidget {
  const _RelatedGridSk();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: responsiveGridDelegate(
          mobileCrossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 14,
          childAspectRatio: 0.66,
        ),
        // Two rows on a phone: enough to read as a grid, and the real one
        // paints over them before anybody scrolls past.
        itemCount: 6,
        itemBuilder: (_, _) => const _RelatedCardSk(),
      ),
    );
  }
}

/// One cell: poster, title line, year line.
///
/// The year line is laid out even though it holds nothing, exactly as
/// _RelatedCard does — it is what leaves the poster its height, so dropping it
/// would make these posters taller than the ones that replace them.
class _RelatedCardSk extends StatelessWidget {
  const _RelatedCardSk();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Block(height: double.infinity, radius: 8)),
        SizedBox(height: 6),
        // The two boxes are the real card's line heights — 12pt at 1.25 and
        // 11pt at 1.3 — with a shorter bar inked inside each.
        SizedBox(
          height: 15,
          child: Row(
            children: [
              Expanded(flex: 5, child: _Block(height: 9)),
              Spacer(),
            ],
          ),
        ),
        SizedBox(
          height: 14,
          child: Row(
            children: [
              Expanded(flex: 2, child: _Block(height: 8)),
              Spacer(flex: 3),
            ],
          ),
        ),
      ],
    );
  }
}

/// One shimmering placeholder.
///
/// The shimmer stays for the parts that really are unknown — it is the
/// standard signal that something is on its way, and removing it everywhere
/// would leave the lower half of the page looking simply empty.
class _Block extends StatelessWidget {
  const _Block({
    this.width,
    required this.height,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // A plain box. The sweep comes from the single Shimmer at the root of
    // this widget — see the note there.
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Fades in on the second half of the route transition.
///
/// Same window as the header's own overlays, so the whole page assembles in
/// one movement: the poster crosses, then everything else settles around it.
/// Fully visible when there is no route animation to read.
///
/// Stateful only so the [CurvedAnimation] can be disposed. Built inside
/// `build` it looked harmless, but its constructor attaches a status listener
/// to the parent unconditionally and only `dispose()` detaches it — so every
/// rebuild left another listener on the route's animation, for the life of
/// the route, three at a time in this widget.
class _LateFade extends StatefulWidget {
  const _LateFade({required this.hasFlight, required this.child});

  /// Only delay when a poster is actually crossing — see the same field on
  /// `_HeroOverlayFade` in detail_hero.dart.
  final bool hasFlight;

  final Widget child;

  @override
  State<_LateFade> createState() => _LateFadeState();
}

class _LateFadeState extends State<_LateFade> {
  CurvedAnimation? _curve;
  Animation<double>? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = widget.hasFlight
        ? ModalRoute.of(context)?.animation
        : null;
    if (identical(animation, _parent)) return;
    _curve?.dispose();
    _parent = animation;
    _curve = animation == null
        ? null
        : CurvedAnimation(
            parent: animation,
            curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
            reverseCurve: Curves.easeIn,
          );
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null) return widget.child;
    return FadeTransition(opacity: curve, child: widget.child);
  }
}

