import 'package:soplay/features/tracker/presentation/widgets/follow_bell.dart';
import 'package:soplay/features/detail/presentation/widgets/tracking_row.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/content/catalogue_logo.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart'
    show ProviderLogo;
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/core/extensions/provider_media_kind.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/presentation/widgets/trailer_action.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_row.dart';
import 'package:soplay/features/recap/domain/recap.dart';
import 'package:soplay/features/recap/presentation/recap_sheet.dart';

class DetailContentHeader extends StatefulWidget {
  const DetailContentHeader({
    super.key,
    required this.detail,
    required this.onPrimaryAction,
    required this.playButtonKey,
    this.onDownload,
    this.via,
    this.resolvingSource = false,
    this.onChangeSource,
    this.onFindSource,
  });

  final DetailEntity detail;
  final VoidCallback onPrimaryAction;
  final Key playButtonKey;

  /// The source a catalogue title was found on. Named under the button,
  /// because a Play that silently picked a source is a Play the viewer cannot
  /// question — and the pick is a guess, however good.
  final CatalogueLink? via;

  /// The search for that source is still running. See [DetailLoaded.resolving].
  final bool resolvingSource;
  final VoidCallback? onChangeSource;

  /// For a catalogue title with no source yet: opens the search.
  final VoidCallback? onFindSource;

  /// Queues the title for offline viewing, or opens the episode list when
  /// "which episodes" is a question only the user can answer.
  final VoidCallback? onDownload;

  @override
  State<DetailContentHeader> createState() => _DetailContentHeaderState();
}

class _DetailContentHeaderState extends State<DetailContentHeader> {
  final HistoryService _history = getIt<HistoryService>();
  HistoryItem? _item;

  @override
  void initState() {
    super.initState();
    _history.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _history.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    final item = _history.get(widget.detail.contentUrl);
    if (!mounted) return;
    setState(() => _item = item);
  }

  RecapRequest? _recapRequest(HistoryItem? item) {
    final detail = widget.detail;
    if (item == null || !detail.isSerial || detail.provider.opensReader) {
      return null;
    }
    final record = detail.record;
    final ids = record != null && !record.isManga;
    return RecapRequest.fromHistory(
      item,
      tmdbId: ids ? record.tmdbId : null,
      anilistId: ids ? record.anilistId : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final recap = _recapRequest(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      // Each block lands a beat after the one above it, top to bottom, so
      // the page assembles under the poster rather than appearing whole.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ItemAppear(index: 0, child: _MetaLine(detail: widget.detail)),
          if (widget.detail.genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            ItemAppear(
              index: 1,
              child: _GenresRow(genres: widget.detail.genres),
            ),
          ],
          if (widget.detail.description.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            ItemAppear(
              index: 2,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktopPlatform ? 900 : double.infinity,
                ),
                child: _ExpandableDescription(
                  text: widget.detail.description.trim(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          // Where this title came from and where it was found, ABOVE the
          // button that will play it. Below, it read as a footnote to a
          // decision already made; above, it is the decision, and the marks
          // say who made it: "TMDB › VidAPI".
          if (widget.via != null) ...[
            ItemAppear(
              index: 3,
              child: _ViaRow(via: widget.via!, onChange: widget.onChangeSource),
            ),
            const SizedBox(height: 12),
          ],
          // Download and trailer sit BESIDE the primary button, resuming or
          // not. They used to be their own row underneath, because Continue
          // came as a block with its progress bar and caption attached — so
          // starting a title showed three controls on one line and coming back
          // to it showed one, with the other two stranded below the caption.
          if (Catalogue.isId(widget.detail.provider))
            // A catalogue title nothing installed carries. Not a Play that
            // fails; the honest button is the one that goes and looks.
            //
            // While the search is still out it says so instead, and does
            // nothing when tapped. The page renders the catalogue's record
            // without waiting for the source, so this button is on screen
            // before the answer is — and "Find a source" is a claim that the
            // looking is finished and came back empty.
            ItemAppear(
              index: 5,
              child: SizedBox(
                width: isDesktopPlatform ? 360 : double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: widget.resolvingSource
                      ? null
                      : widget.onFindSource,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.6,
                    ),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kButtonRadius),
                    ),
                  ),
                  icon: widget.resolvingSource
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(Icons.travel_explore_rounded, size: 22),
                  label: Text(
                    widget.resolvingSource
                        ? 'catalogue.finding_source'.tr()
                        : 'catalogue.find_source'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            )
          else
            ItemAppear(
              index: 5,
              child: _ContinueWatchingCard(
                item: item,
                onTap: widget.onPrimaryAction,
                reader: widget.detail.provider.opensReader,
                playButtonKey: widget.playButtonKey,
                trailing: [
                  if (recap != null) ...[
                    const SizedBox(width: 10),
                    _SquareAction(
                      icon: Icons.history_edu_rounded,
                      tooltip: 'recap.action'.tr(),
                      onTap: () => RecapSheet.show(context, recap),
                    ),
                  ],
                  // Offline used to be reachable only from inside the player:
                  // open the title, wait for a source to resolve, start playing,
                  // then find it in a menu. Four steps and a started stream to
                  // save something for the train.
                  if (widget.onDownload != null) ...[
                    const SizedBox(width: 10),
                    _SquareAction(
                      icon: Icons.download_rounded,
                      tooltip: 'detail.download_action'.tr(),
                      onTap: widget.onDownload!,
                    ),
                  ],
                  // Appears on its own once a trailer has been found, and takes
                  // no space at all when there is none — so a title without one
                  // never shows a button that cannot do anything.
                  TrailerAction(detail: widget.detail),
                ],
              ),
            ),
          // Following is for things that keep coming: a series, a manga, a
          // novel. A film has nothing to be told about.
          if (widget.detail.isSerial || widget.detail.provider.opensReader) ...[
            const SizedBox(height: 12),
            ItemAppear(index: 6, child: FollowBellPill(detail: widget.detail)),
          ],
          // Brings its own gap, so a page with nothing to track has no
          // blank band under the buttons.
          ItemAppear(index: 7, child: TrackingRow(detail: widget.detail)),
        ],
      ),
    );
  }
}

/// Resume, with how far in you already are.
///
/// The button alone said "Continue" and nothing else: not which episode was
/// half-finished, not whether it was two minutes in or two minutes from the
/// end. The progress the player already records was on the page for the
/// carousel and nowhere on the title's own screen.
class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.item,
    required this.onTap,
    required this.trailing,
    this.reader = false,
    this.playButtonKey,
  });

  /// null when nothing has been watched yet, in which case this is just the
  /// play button and its neighbours.
  final HistoryItem? item;
  final VoidCallback onTap;

  /// Download and trailer, on the same line as the button.
  final List<Widget> trailing;

  final Key? playButtonKey;

  /// A manga or novel title. The reader records a page index (or, for prose,
  /// thousandths of the chapter) in the fields the player uses for
  /// milliseconds, so "time left" and "% watched" would read page 12 of 30 as
  /// "18ms left". The bar alone is honest for both.
  final bool reader;

  /// "1h 12m" / "24m" — the shape a remaining-time label wants, and short
  /// enough to sit next to the episode on one line.
  static String _short(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final resuming =
        item != null && (item.positionMs > 0 || item.episodeNumber != null);
    final progress = resuming ? item.progress : 0.0;
    final left = resuming && !reader && item.durationMs > 0
        ? Duration(milliseconds: item.durationMs - item.positionMs)
        : null;

    final caption = !resuming
        ? ''
        : <String>[
            if (item.isSerial && item.episodeNumber != null)
              'detail.episode_n'.tr(args: ['${item.episodeNumber}']),
            if (left != null && left > const Duration(seconds: 30))
              'detail.time_left'.tr(args: [_short(left)])
            else if (!reader && progress > 0)
              'detail.watched_pct'.tr(args: ['${(progress * 100).round()}']),
          ].join(' \u00b7 ');

    return SizedBox(
      width: isDesktopPlatform ? 460 : double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: !resuming
                    ? _PlayButton(
                        key: playButtonKey,
                        onTap: onTap,
                        // Manga / manhwa / novel sources open the reader, so
                        // the primary action is "Read", not "Play" — with a
                        // book icon to match. The wrong verb on a manga title
                        // reads as a broken source.
                        reader: reader,
                      )
                    : SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: onTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                kButtonRadius,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 26),
                          label: Text(
                            item.isSerial && item.episodeNumber != null
                                ? 'detail.continue_ep'.tr(
                                    args: ['${item.episodeNumber}'],
                                  )
                                : 'detail.continue_watching'.tr(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
              ),
              ...trailing,
            ],
          ),
          // A bar is only honest when the player reported a duration; a
          // zero-length track would draw an empty rail that never moves.
          if (progress > 0) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.detail});
  final DetailEntity detail;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (detail.record?.score != null)
        '\u2605 ${detail.record!.score!.toStringAsFixed(1)}',
      if (detail.year != null) detail.year.toString(),
      if (detail.duration != null && detail.duration!.trim().isNotEmpty)
        detail.duration!.trim(),
      if (detail.country != null && detail.country!.trim().isNotEmpty)
        detail.country!.trim(),
    ];

    // Votes were parsed on every detail request and then dropped on the floor.
    // A ratio is what a viewer actually asks of them ("is this any good?"), and
    // a handful of votes cannot answer that, so a thin sample stays hidden.
    final votes = detail.likes + detail.dislikes;
    final rating = votes >= 5 ? (detail.likes * 100 / votes).round() : null;

    if (parts.isEmpty && rating == null) return const SizedBox.shrink();

    final widgets = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      widgets.add(
        Text(
          parts[i],
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      if (i != parts.length - 1) {
        widgets.add(const _Dot());
      }
    }
    if (rating != null) {
      if (widgets.isNotEmpty) widgets.add(const _Dot());
      widgets.add(_LikeRatio(percent: rating, votes: votes));
    }
    // Wrap, not Row: a long country or runtime string overflowed the line on
    // narrow phones.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: widgets,
    );
  }
}

/// How the crowd voted, as a share rather than two raw counters — with the
/// sample size beside it so a 100% from six people is not read as a verdict.
class _LikeRatio extends StatelessWidget {
  const _LikeRatio({required this.percent, required this.votes});

  final int percent;
  final int votes;

  @override
  Widget build(BuildContext context) {
    final positive = percent >= 60;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          positive ? Icons.thumb_up_rounded : Icons.thumb_down_rounded,
          size: 13,
          color: positive ? AppColors.rating : AppColors.textHint,
        ),
        const SizedBox(width: 5),
        Text(
          'detail.liked'.tr(args: ['$percent']),
          style: TextStyle(
            color: positive ? AppColors.rating : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '($votes)',
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '•',
        style: TextStyle(color: AppColors.textHint, fontSize: 12),
      ),
    );
  }
}

class _GenresRow extends StatelessWidget {
  const _GenresRow({required this.genres});
  final List<String> genres;

  static String _slugify(String value) {
    final s = value.trim().toLowerCase();
    return s.replaceAll(RegExp(r"\s+"), '-').replaceAll(RegExp(r"-+"), '-');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: genres
            .take(8)
            .map(
              (g) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: _Chip(
                  label: g,
                  onTap: () {
                    final slug = _slugify(g);
                    if (slug.isEmpty) return;
                    context.push(
                      '/view-all',
                      extra: ViewAllEntity(type: 'genre', slug: slug),
                    );
                  },
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Material owns the fill so the ink lands on top of it; on the bare
    // Container the splash painted under an opaque chip and was invisible.
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});
  final String text;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  static const int _collapsedLines = 3;
  static const TextStyle _style = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
    height: 1.5,
  );

  bool _expanded = false;

  bool _overflows(BuildContext context, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: _style),
      maxLines: _collapsedLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final exceeded = painter.didExceedMaxLines;
    painter.dispose();
    return exceeded;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, double maxWidth) {
    // Without this the synopsis was clamped to three lines with an ellipsis and
    // nothing said it could be opened, so most of the plot was unreachable.
    final clamped = maxWidth.isFinite && _overflows(context, maxWidth);
    final body = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : _collapsedLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: _style,
          ),
          if (clamped || _expanded) ...[
            const SizedBox(height: 4),
            Text(
              _expanded ? 'detail.show_less'.tr() : 'detail.show_more'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );

    // Android TV: the synopsis is clamped to three lines and tapping is the
    // only way to expand it, so without a focus stop the plot is unreadable on
    // a television. No scale — growing a paragraph under the ring looks wrong;
    // the ring alone marks it. Off TV: the original GestureDetector.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: () => setState(() => _expanded = !_expanded),
        borderRadius: 8,
        scale: 1.0,
        child: body,
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: body,
    );
  }
}

/// A square icon button sized to match [_PlayButton] beside it.
class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Material(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(kButtonRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(kButtonRadius),
            onTap: onTap,
            child: Icon(icon, size: 21, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({super.key, required this.onTap, this.reader = false});
  final VoidCallback onTap;

  /// Reading source — label and icon switch from Play/▶ to Read/book.
  final bool reader;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isDesktopPlatform ? 360 : double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kButtonRadius),
          ),
        ),
        icon: Icon(
          reader ? Icons.menu_book_rounded : Icons.play_arrow_rounded,
          size: reader ? 22 : 26,
        ),
        label: Text(
          reader ? 'detail.read'.tr() : 'detail.play'.tr(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// "TMDB › VidAPI · Change" — the hand-off, with both marks.
///
/// The catalogue's own logo and the source's own logo, so the line reads at
/// a glance without a word being read: this came from there, and it plays
/// from here. Change is the one control, because the pick is a guess.
///
/// When the pick is [CatalogueLink.approximate] it is a guess of a second,
/// worse kind, and it is caveated here rather than anywhere else because here
/// is where Play is decided. The light-novel shelf falls back to the manga
/// readers on an install with no novel source, and what a manga source carries
/// under a light novel's name is usually the adaptation — a different work
/// with the same title. Naming the source without that is telling somebody a
/// source was found for their novel when one was not.
class _ViaRow extends StatelessWidget {
  const _ViaRow({required this.via, this.onChange});

  final CatalogueLink via;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final catalogue = Catalogue.fromId(via.catalogueId);
    // Same shell as the tracker rows below Play — see [DetailRowShell] for
    // what the two used to disagree about and why it showed.
    return DetailRowShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (catalogue != null) ...[
                CatalogueLogo(catalogue: catalogue, size: kDetailRowLogoSize),
                const SizedBox(width: 7),
                Text(
                  catalogue.labelKey.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                ),
              ],
              ProviderLogo(image: via.providerImage, size: kDetailRowLogoSize),
              const SizedBox(width: 10),
              // The name and the mark share one slot, so the mark stays
              // against the name it qualifies instead of drifting off to the
              // right, and a long name gives way to it rather than pushing it
              // off the line.
              DetailRowTitle(
                name: via.providerName,
                trailing: via.approximate
                    ? _GuessPill(
                        label: 'catalogue.approximate_source'.tr(),
                        spoken: 'catalogue.approximate_source_hint'.tr(),
                      )
                    : null,
              ),
              if (onChange != null) ...[
                const SizedBox(width: 8),
                // The same control the tracker rows end in. This was a bare
                // TextButton: accent words with no box, directly above two
                // rows that ended in filled pills.
                DetailRowAction(
                  label: 'catalogue.change_source'.tr(),
                  onTap: onChange!,
                  // Opens the alternate-source sheet, like the tracker rows
                  // open theirs.
                ),
              ],
            ],
          ),
          // The whole sentence on screen, not hidden behind a long-press:
          // "Best guess" alone does not tell anybody WHICH work they are about
          // to open, and the choice in front of them is Play or Change.
          //
          // Silent to a screen reader because the pill above already speaks
          // this exact sentence as its label, and hearing it twice in a row is
          // worse than hearing it once.
          if (via.approximate) ...[
            const SizedBox(height: 7),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Text(
                  'catalogue.approximate_source_hint'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A word and a mark, in a box — "❓ Best guess".
///
/// Deliberately the same shape as the pill the alternate-source sheet puts on
/// its uncertain rows: an icon AND a word, never a tint on its own, so the
/// mark survives a greyscale screenshot, a colour-blind reader and a screen
/// reader alike. It is a second copy rather than that one because that one is
/// private to its file; a third should be the one that moves them into
/// core/widgets.
class _GuessPill extends StatelessWidget {
  const _GuessPill({required this.label, required this.spoken});

  final String label;

  /// Said instead of [label], because two words are all the line has room for
  /// and they are not the part a reader needs.
  final String spoken;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.help_outline_rounded,
              size: 11,
              color: Colors.white70,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
