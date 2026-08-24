import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/core/extensions/provider_media_kind.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';

class DetailContentHeader extends StatefulWidget {
  const DetailContentHeader({
    super.key,
    required this.detail,
    required this.onPrimaryAction,
    required this.playButtonKey,
  });

  final DetailEntity detail;
  final VoidCallback onPrimaryAction;
  final Key playButtonKey;

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

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaLine(detail: widget.detail),
          if (widget.detail.genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            _GenresRow(genres: widget.detail.genres),
          ],
          if (widget.detail.description.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktopPlatform ? 900 : double.infinity,
              ),
              child: _ExpandableDescription(
                text: widget.detail.description.trim(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (item != null &&
              (item.positionMs > 0 || item.episodeNumber != null))
            _ContinueWatchingCard(item: item, onTap: widget.onPrimaryAction)
          else
            _PlayButton(
              key: widget.playButtonKey,
              onTap: widget.onPrimaryAction,
              // Manga / manhwa / novel sources open the reader, so the primary
              // action is "Read", not "Play" — with a book icon to match. The
              // wrong verb on a manga title reads as a broken source.
              reader: widget.detail.provider.opensReader,
            ),
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
  const _ContinueWatchingCard({required this.item, required this.onTap});
  final HistoryItem item;
  final VoidCallback onTap;

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
    final progress = item.progress;
    final left = item.durationMs > 0
        ? Duration(milliseconds: item.durationMs - item.positionMs)
        : null;

    final caption = <String>[
      if (item.isSerial && item.episodeNumber != null)
        'detail.episode_n'.tr(args: ['${item.episodeNumber}']),
      if (left != null && left > const Duration(seconds: 30))
        'detail.time_left'.tr(args: [_short(left)])
      else if (progress > 0)
        'detail.watched_pct'.tr(args: ['${(progress * 100).round()}']),
    ].join(' \u00b7 ');

    return SizedBox(
      width: isDesktopPlatform ? 360 : double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
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
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: Text(
                item.isSerial && item.episodeNumber != null
                    ? 'detail.continue_ep'.tr(args: ['${item.episodeNumber}'])
                    : 'detail.continue_watching'.tr(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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
                padding: const EdgeInsets.only(right: 6),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kButtonRadius)),
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
