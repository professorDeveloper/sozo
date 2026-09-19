/// The shape every "this title, on that service" row on the detail page takes.
///
/// There were two of these, written separately, stacked a few hundred pixels
/// apart — the source line ("AniList › AnimeKAI · Change") and the tracker
/// lines ("AniList · Not on your list · Add to list"). They agreed on nothing:
/// radius 12 against 14, one with a hairline border and one without, padding
/// (10,6,6,6) against (12,8,8,8), 13pt names against 14pt. Side by side that
/// reads as two things built at different times, which is exactly what it was.
///
/// The trailing control was the worst of it. The source row ended in a bare
/// `TextButton` — accent-coloured words with no box — while the tracker rows
/// ended in a filled, bordered pill tinted with each tracker's own brand blue.
/// So three stacked rows offered three differently-shaped ways to press the
/// same kind of thing, and because MyAnimeList's blue is much darker than
/// AniList's, the same pill at the same opacities came out looking disabled on
/// the MAL row and enabled on the one above it.
///
/// One shell and one action here, and the brand stays where brand belongs: on
/// the logo at the left. A neutral control cannot be mistaken for disabled and
/// cannot make two rows look like different kinds of row.
library;

import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// Radius, fill and border shared by every detail row.
const double kDetailRowRadius = 14;
const EdgeInsetsDirectional kDetailRowPadding =
    EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8);

/// The logo at the head of a row. One size, so the two rows' marks line up
/// down the page instead of being 22 in one place and whatever in the other.
const double kDetailRowLogoSize = 22;

BoxDecoration detailRowDecoration() => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(kDetailRowRadius),
  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
);

/// The container a detail row sits in.
///
/// [onTap] makes the whole row pressable, which the tracker rows are and the
/// source row is not; without it this is a plain box and no ink is wasted on
/// it.
class DetailRowShell extends StatelessWidget {
  const DetailRowShell({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return DecoratedBox(
        decoration: detailRowDecoration(),
        child: Padding(padding: kDetailRowPadding, child: child),
      );
    }
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(kDetailRowRadius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kDetailRowRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: kDetailRowPadding, child: child),
        ),
      ),
    );
  }
}

/// The name of the service, and where you are on it.
///
/// One text style for both halves, so "AnimeKAI" on the source row and
/// "AniList" on the tracker row are the same weight and size rather than 13
/// and 14.
class DetailRowTitle extends StatelessWidget {
  const DetailRowTitle({
    super.key,
    required this.name,
    this.status,
    this.spokenStatus,
    this.trailing,
  });

  final String name;

  /// The part after the separator dot — "Not on your list", "Watching 5/12".
  /// Null when there is nothing true to say.
  final String? status;

  /// What a screen reader hears in place of [status]. Defaults to [status]; a
  /// row whose status is a placeholder shape rather than a value passes the
  /// empty string, because a reader must not announce a position the app does
  /// not know yet.
  final String? spokenStatus;

  /// Sits directly after the name, inside the same slot, so a long name gives
  /// way to it instead of pushing it off the line.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final spoken = spokenStatus ?? status;
    final line = RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: const TextStyle(fontSize: 14),
        children: [
          TextSpan(
            text: name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (status != null)
            TextSpan(
              text: '  ·  $status',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

    final labelled = Semantics(
      label: (spoken == null || spoken.isEmpty) ? name : '$name, $spoken',
      excludeSemantics: true,
      child: line,
    );

    if (trailing == null) return Expanded(child: labelled);
    return Expanded(
      child: Row(
        children: [
          Flexible(child: labelled),
          const SizedBox(width: 6),
          trailing!,
        ],
      ),
    );
  }
}

/// The one control a detail row ends in.
///
/// Neutral rather than brand-tinted, for the reason in the library comment: at
/// the alphas the tracker pill used, MyAnimeList's darker blue read as a
/// disabled button sitting directly beneath an enabled one.
class DetailRowAction extends StatelessWidget {
  const DetailRowAction({
    super.key,
    required this.label,
    required this.onTap,
    this.showChevron = true,
  });

  final String label;
  final VoidCallback onTap;

  /// The chevron says "this opens something". A row whose action completes in
  /// place rather than opening a sheet leaves it off.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // Asymmetric because the chevron carries its own optical space on
          // the right; with equal padding the label looked off-centre.
          padding: EdgeInsetsDirectional.fromSTEB(12, 8, showChevron ? 6 : 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (showChevron)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
