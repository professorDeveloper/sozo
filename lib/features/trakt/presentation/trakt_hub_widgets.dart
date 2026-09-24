import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/system/app_dates.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_hub_models.dart';
import 'package:soplay/features/trakt/presentation/trakt_brand.dart';
import 'package:soplay/features/trakt/presentation/trakt_hub_controller.dart';

/// Opens a Trakt title in the app: the TMDB catalogue's page when Trakt
/// knows the TMDB id — which finds the sources that carry it — and a search
/// across sources by name when it does not.
void openTraktTitle(BuildContext context, TraktMedia media) {
  final url = media.tmdbUrl;
  if (url == null) {
    context.push('/cross-search', extra: media.title);
    return;
  }
  context.push(
    '/detail',
    extra: DetailArgs(
      contentUrl: url,
      provider: Catalogue.tmdb.id,
      preview: MovieEntity(
        externalId: '${media.tmdbId}',
        title: media.title,
        description: media.overview ?? '',
        slug: media.slug ?? '',
        url: url,
        provider: Catalogue.tmdb.id,
        thumbnail: media.poster,
        banner: media.fanart,
        year: media.year,
        rating: media.rating == null ? null : (media.rating! * 10).round(),
        qualities: null,
        category: media.isMovie ? 'movie' : 'tv',
      ),
    ),
  );
}

/// "1.2k" rather than "1234" in a stat tile.
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) {
    final k = (n / 1000).toStringAsFixed(1);
    return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
  }
  return '${(n / 1000).round()}k';
}

/// "Today", "Tomorrow", "Yesterday", or the date.
String dayLabel(BuildContext context, DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'trakt.today'.tr();
  if (diff == 1) return 'trakt.tomorrow'.tr();
  if (diff == -1) return 'trakt.yesterday'.tr();
  final weekday = DateFormat.EEEE(context.locale.toLanguageTag()).format(at);
  return '$weekday · ${AppDates.short(context, at)}';
}

String clock(BuildContext context, DateTime at) =>
    DateFormat.Hm(context.locale.toLanguageTag()).format(at);

/// The line under a title: the episode, or what kind of title it is.
String entrySubtitle(TraktEntry e) {
  final ep = e.episode;
  if (ep != null) {
    return ep.title == null ? ep.code : '${ep.code} · ${ep.title}';
  }
  final year = e.media.year;
  final kind = e.isMovie ? 'trakt.movie'.tr() : 'trakt.show'.tr();
  return year == null ? kind : '$year · $kind';
}

/// A poster in a grid: the art, the title under it, and one badge.
class TraktPosterTile extends StatelessWidget {
  const TraktPosterTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.badge,
    this.busy = false,
  });

  final TraktEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;
  final bool busy;

  static const double _titleSize = 12.5;
  static const double _titleHeight = 1.25;
  static const double _subSize = 11;
  static const double _subHeight = 1.3;

  /// The title (two lines), the line under it and the gaps, in whole pixels
  /// at the viewer's text size — what a grid of these adds to the poster.
  static double textBlockHeight(TextScaler scaler) =>
      (6 +
              2 * scaler.scale(_titleSize) * _titleHeight +
              2 +
              scaler.scale(_subSize) * _subHeight)
          .ceilToDouble() +
      2;

  @override
  Widget build(BuildContext context) {
    final m = entry.media;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AnilistCover(url: m.poster, radius: 10),
              if (badge != null)
                PositionedDirectional(top: 6, start: 6, child: badge!),
              if (busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x88000000),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kTraktRed,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            m.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            strutStyle: const StrutStyle(
              fontSize: _titleSize,
              height: _titleHeight,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: _titleSize,
              fontWeight: FontWeight.w700,
              height: _titleHeight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entrySubtitle(entry),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            strutStyle: const StrutStyle(
              fontSize: _subSize,
              height: _subHeight,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: _subSize,
              height: _subHeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small dark label on a poster corner.
class TraktBadge extends StatelessWidget {
  const TraktBadge({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color ?? Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A list row: small poster, title, a line under it, and whatever trails.
class TraktEntryRow extends StatelessWidget {
  const TraktEntryRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.subtitle,
    this.caption,
    this.trailing,
    this.showProgress = false,
  });

  final TraktEntry entry;
  final VoidCallback onTap;
  final String? subtitle;

  /// A third, quieter line: a time, a count.
  final String? caption;
  final Widget? trailing;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final fraction = entry.fraction;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              AnilistCover(url: entry.media.poster, width: 50, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle ?? entrySubtitle(entry),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        caption!,
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                    if (showProgress && fraction != null) ...[
                      const SizedBox(height: 7),
                      AnilistProgressBar(value: fraction, color: kTraktRed),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A wide card for a paused playback: the still, how far in, the title.
class TraktPlaybackCard extends StatelessWidget {
  const TraktPlaybackCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  final TraktEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final image =
        entry.episode?.screenshot ?? entry.media.fanart ?? entry.media.poster;
    final progress = ((entry.progress ?? 0) / 100).clamp(0.0, 1.0);
    return SizedBox(
      width: 236,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            ColoredBox(color: AppColors.surfaceVariant),
                      )
                    else
                      ColoredBox(color: AppColors.surfaceVariant),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xB0000000)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x88000000),
                        ),
                        tooltip: 'trakt.action_remove_playback'.tr(),
                        onPressed: onRemove,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Row(
                        children: [
                          Expanded(
                            child: AnilistProgressBar(
                              value: progress,
                              color: kTraktRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              entry.media.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entrySubtitle(entry),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// A heading between groups of rows.
class TraktSectionHeader extends StatelessWidget {
  const TraktSectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: kTraktRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Everything that can be done with one title, in one sheet.
class TraktItemSheet extends StatefulWidget {
  const TraktItemSheet({
    super.key,
    required this.entry,
    required this.controller,
    this.inWatchlist,
    this.extraActions = const [],
  });

  final TraktEntry entry;
  final TraktHubController controller;

  /// Known from the list it was opened from; null when unknown.
  final bool? inWatchlist;

  /// Rows only one list offers — "Not interested", "Remove from history".
  final List<TraktSheetAction> extraActions;

  static Future<void> show(
    BuildContext context, {
    required TraktEntry entry,
    required TraktHubController controller,
    bool? inWatchlist,
    List<TraktSheetAction> extraActions = const [],
  }) => showAdaptiveModal<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => TraktItemSheet(
      entry: entry,
      controller: controller,
      inWatchlist: inWatchlist,
      extraActions: extraActions,
    ),
  );

  @override
  State<TraktItemSheet> createState() => _TraktItemSheetState();
}

class TraktSheetAction {
  const TraktSheetAction({
    required this.icon,
    required this.label,
    required this.run,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final Future<String?> Function() run;
  final bool destructive;
}

class _TraktItemSheetState extends State<TraktItemSheet> {
  late final bool? _inWatchlist = widget.inWatchlist;
  late int? _rating = widget.entry.rating;
  bool _busy = false;

  TraktMedia get _media => widget.entry.media;

  Future<void> _run(Future<String?> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? done),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (error == null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final m = _media;
    final ep = widget.entry.episode;
    final c = widget.controller;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnilistCover(url: m.poster, width: 84, radius: 10),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          AnilistChip(
                            label: m.isMovie
                                ? 'trakt.movie'.tr()
                                : 'trakt.show'.tr(),
                            color: kTraktRed,
                          ),
                          if (m.year != null)
                            AnilistChip(
                              label: '${m.year}',
                              color: AppColors.textSecondary,
                            ),
                          if (m.rating != null && m.rating! > 0)
                            AnilistChip(
                              label: m.rating!.toStringAsFixed(1),
                              icon: Icons.star_rounded,
                              color: AppColors.rating,
                            ),
                          if (m.runtime != null && m.runtime! > 0)
                            AnilistChip(
                              label: '${m.runtime} min',
                              icon: Icons.schedule_rounded,
                              color: AppColors.textSecondary,
                            ),
                        ],
                      ),
                      if (ep != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          entrySubtitle(widget.entry),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (m.genres.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          m.genres.take(4).join(' · '),
                          style: TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if ((m.overview ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                m.overview!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kTraktRed,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  openTraktTitle(context, m);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('trakt.action_open'.tr()),
              ),
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: _inWatchlist == true
                  ? Icons.bookmark_remove_rounded
                  : Icons.bookmark_add_outlined,
              label: _inWatchlist == true
                  ? 'trakt.action_watchlist_remove'.tr()
                  : 'trakt.action_watchlist_add'.tr(),
              busy: _busy,
              onTap: () {
                final add = _inWatchlist != true;
                _run(
                  () => c.setWatchlisted(m, add),
                  add ? 'trakt.added'.tr() : 'trakt.removed'.tr(),
                );
              },
            ),
            _ActionRow(
              icon: Icons.check_circle_outline_rounded,
              label: ep != null
                  ? 'trakt.action_mark_next'.tr(args: [ep.code])
                  : m.isMovie
                  ? 'trakt.action_mark_watched'.tr()
                  : 'trakt.action_mark_next_episode'.tr(),
              busy: _busy,
              onTap: () =>
                  _run(() => c.markWatched(widget.entry), 'trakt.marked'.tr()),
            ),
            for (final a in widget.extraActions)
              _ActionRow(
                icon: a.icon,
                label: a.label,
                busy: _busy,
                destructive: a.destructive,
                onTap: () => _run(a.run, 'trakt.removed'.tr()),
              ),
            const SizedBox(height: 12),
            Text(
              'trakt.action_rate'.tr(),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _RatingPicker(
              value: _rating,
              enabled: !_busy,
              onChanged: (v) {
                setState(() => _rating = v);
                _run(
                  () => c.rate(widget.entry, v ?? 0),
                  v == null
                      ? 'trakt.rating_cleared'.tr()
                      : 'trakt.rated'.tr(args: ['$v']),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.busy,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.errorLight : AppColors.textPrimary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      leading: Icon(icon, color: destructive ? color : kTraktRed, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: busy ? null : onTap,
    );
  }
}

/// Ten numbered steps, Trakt's own scale; tapping the chosen one clears it.
class _RatingPicker extends StatelessWidget {
  const _RatingPicker({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 10; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: enabled ? () => onChanged(value == i ? null : i) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value != null && i <= value!
                        ? kTraktRed.withValues(alpha: i == value ? 1 : 0.35)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      color: value != null && i <= value!
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
