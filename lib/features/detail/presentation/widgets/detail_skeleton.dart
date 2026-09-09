import 'package:flutter/material.dart';
import 'package:soplay/core/widgets/shimmer_wrapper.dart';

import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';

/// The detail page with nothing known about it yet — the fallback for the
/// routes that arrive without a preview entity.
///
/// The shapes below the header track the loaded page: the strip is
/// `_TabBarDelegate` in `detail_page.dart`, and the grid under it is
/// DetailRelatedSection in `detail_related.dart`, which is what the 'Similar'
/// tab the page opens on draws. Change that grid and this follows it — as does
/// `_RelatedGridSk` in `detail_preview_skeleton.dart`.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // The third hand-copy of this formula used to live here, and it was the
    // one that disagreed: it left the status bar out, so this skeleton drew a
    // header a full inset shorter than the page that replaced it. There is now
    // exactly one definition, in core/widgets/poster_hero.dart, and all three
    // call sites read it.
    final heroHeight = detailHeroHeight(context);
    return ShimmerWrapper(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkBox(width: double.infinity, height: heroHeight, radius: 0),
            const _Pad(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16),
                  Row(
                    children: [
                      _SkBox(width: 50, height: 14, radius: 4),
                      SizedBox(width: 12),
                      _SkBox(width: 60, height: 14, radius: 4),
                      SizedBox(width: 12),
                      _SkBox(width: 70, height: 14, radius: 4),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      _SkBox(width: 60, height: 22, radius: 6),
                      SizedBox(width: 8),
                      _SkBox(width: 80, height: 22, radius: 6),
                      SizedBox(width: 8),
                      _SkBox(width: 70, height: 22, radius: 6),
                    ],
                  ),
                  SizedBox(height: 18),
                  _SkBox(width: double.infinity, height: 13, radius: 4),
                  SizedBox(height: 6),
                  _SkBox(width: double.infinity, height: 13, radius: 4),
                  SizedBox(height: 6),
                  _SkBox(width: 200, height: 13, radius: 4),
                  SizedBox(height: 18),
                  _SkBox(
                    width: double.infinity,
                    height: 46,
                    radius: kButtonRadius,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _TabStripSk(),
            // The loaded page's padding above the tab body.
            const SizedBox(height: 4),
            const _PosterGridSk(),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _SkBox extends StatelessWidget {
  const _SkBox({required this.width, required this.height, this.radius = 8});
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(width: width, height: height, color: Colors.white),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

/// The pinned tab strip: the label box, the indicator and the divider under
/// it. A single 14pt row of bars stood in for all of it, so the grid below sat
/// a strip's worth too high until the page loaded.
///
/// Every number comes from [AppTabBar], which is the one definition the real
/// strip and both skeletons now read.
class _TabStripSk extends StatelessWidget {
  const _TabStripSk();

  static const double _labelHeight =
      AppTabBar.stripHeight - AppTabBar.indicatorWeight;

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(
          height: _labelHeight,
          child: Padding(
            // _TabBarDelegate's leading inset, then the TabBar's own 14pt
            // label padding.
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
        SizedBox(height: AppTabBar.indicatorWeight),
        _SkBox(
          width: double.infinity,
          height: AppTabBar.dividerHeight,
          radius: 0,
        ),
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
      child: _SkBox(width: width, height: 11, radius: 4),
    );
  }
}

/// Stands in for the first tab, which is the related poster grid — same
/// delegate, padding and cell shape as DetailRelatedSection in
/// `detail_related.dart`.
///
/// The columns were hardcoded at three, so desktop drew three enormous cells
/// where the real grid packs 160pt ones; and the 0.66 ratio was on the artwork
/// alone rather than on the whole cell, which made every placeholder poster
/// taller than the one that replaced it.
class _PosterGridSk extends StatelessWidget {
  const _PosterGridSk();

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
        itemCount: 6,
        itemBuilder: (_, _) => const _PosterCellSk(),
      ),
    );
  }
}

/// Poster, title line, year line — the year line laid out empty, as
/// _RelatedCard lays it out, because it is what leaves the poster its height.
class _PosterCellSk extends StatelessWidget {
  const _PosterCellSk();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SkBox(
            width: double.infinity,
            height: double.infinity,
            radius: 8,
          ),
        ),
        SizedBox(height: 6),
        // The real card's line boxes: 12pt at 1.25, then 11pt at 1.3.
        SizedBox(
          height: 15,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: _SkBox(width: double.infinity, height: 9, radius: 4),
              ),
              Spacer(),
            ],
          ),
        ),
        SizedBox(
          height: 14,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _SkBox(width: double.infinity, height: 8, radius: 4),
              ),
              Spacer(flex: 3),
            ],
          ),
        ),
      ],
    );
  }
}
