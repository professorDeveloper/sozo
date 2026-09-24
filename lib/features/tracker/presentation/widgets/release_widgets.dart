import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/tracker/data/release_feed_store.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';
import 'package:soplay/features/tracker/presentation/widgets/release_labels.dart';

/// Opens [e]'s title on its first new episode.
void openRelease(BuildContext context, ReleaseEntry e) {
  context.push(
    '/detail',
    extra: DetailArgs(
      contentUrl: e.contentUrl,
      provider: e.provider.isEmpty ? null : e.provider,
      focusEpisode: e.fromEpisode,
    ),
  );
}

class ReleasePoster extends StatelessWidget {
  const ReleasePoster({
    super.key,
    required this.url,
    this.radius = 10,
    this.iconSize = 22,
  });

  final String url;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(Icons.movie_rounded, color: AppColors.textHint, size: iconSize),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : LayoutBuilder(
              builder: (context, box) => CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: box.maxWidth.isFinite
                    ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round()
                    : null,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}

/// The small red NEW tag. Breathes softly so a row of posters with one new
/// title reads at a glance; still when animations are off.
class NewBadge extends StatefulWidget {
  const NewBadge({super.key, this.compact = false});

  final bool compact;

  @override
  State<NewBadge> createState() => _NewBadgeState();
}

class _NewBadgeState extends State<NewBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _glow.stop();
    } else if (!_glow.isAnimating) {
      _glow.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 5 : 7,
          vertical: widget.compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(
                alpha: 0.25 + 0.35 * _glow.value,
              ),
              blurRadius: 6 + 6 * _glow.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Text(
        'release_notify.badge_new'.tr(),
        style: TextStyle(
          color: AppColors.onPrimary,
          fontSize: widget.compact ? 9 : 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// "EP 12" on a tinted pill.
class EpisodePill extends StatelessWidget {
  const EpisodePill({super.key, required this.text, this.strong = true});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: strong
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: strong ? AppColors.primaryLight : AppColors.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// The entry to the feed at the top of the Following tab and the inbox:
/// the newest posters fanned out, and how many are waiting.
class ReleasesHeaderCard extends StatelessWidget {
  const ReleasesHeaderCard({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final feed = getIt<ReleaseFeedStore>();
    return ValueListenableBuilder<int>(
      valueListenable: feed.revision,
      builder: (context, _, _) {
        final all = feed.entries();
        final unseen = all.where((e) => !e.seen).toList();
        final posters = (unseen.isNotEmpty ? unseen : all)
            .take(3)
            .map((e) => e.thumbnail)
            .toList();
        final count = unseen.length;
        return Padding(
          padding: margin ?? EdgeInsets.zero,
          child: HoverTap(
            onTap: () => context.push('/releases'),
            borderRadius: 16,
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: count > 0
                    ? LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.24),
                          AppColors.surface,
                        ],
                      )
                    : null,
                color: count > 0 ? null : AppColors.surface,
                border: Border.all(
                  color: count > 0
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  _PosterFan(urls: posters),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'release_notify.feed_title'.tr(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          count > 0
                              ? 'release_notify.feed_card_new'.tr(args: ['$count'])
                              : 'release_notify.feed_card_none'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: count > 0
                                ? AppColors.primaryLight
                                : AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (count > 0) ...[
                    Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PosterFan extends StatelessWidget {
  const _PosterFan({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.new_releases_rounded, color: AppColors.primary, size: 22),
      );
    }
    const w = 34.0, h = 48.0, step = 14.0;
    return SizedBox(
      width: w + step * (urls.length - 1) + 4,
      height: h + 4,
      child: Stack(
        children: [
          for (var i = urls.length - 1; i >= 0; i--)
            PositionedDirectional(
              start: step * i,
              top: 2,
              child: Transform.rotate(
                angle: (i - (urls.length - 1) / 2) * 0.06,
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.background, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66000000), blurRadius: 6),
                    ],
                  ),
                  child: ReleasePoster(url: urls[i], radius: 6, iconSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Home's "New episodes for you". Takes no room at all until a followed title
/// has something unseen.
class NewReleasesRail extends StatelessWidget {
  const NewReleasesRail({super.key});

  @override
  Widget build(BuildContext context) {
    final feed = getIt<ReleaseFeedStore>();
    return ValueListenableBuilder<int>(
      valueListenable: feed.revision,
      builder: (context, _, _) {
        final unseen = feed.unseen();
        if (unseen.isEmpty) return const SizedBox.shrink();
        final visible = unseen.take(20).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeSectionTapTarget(
                onTap: () => context.push('/releases'),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 20, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.new_releases_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'release_notify.home_rail'.tr(),
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
                      Flexible(
                        child: Text(
                          'home.view_all'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                // Poster and gaps, then the two lines of text as they scale.
                height: 173 + MediaQuery.textScalerOf(context).scale(23.5) * 1.5,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: visible.length,
                  itemBuilder: (_, i) => ItemAppear(
                    index: i,
                    axis: Axis.horizontal,
                    child: _RailCard(entry: visible[i]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({required this.entry});

  final ReleaseEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        width: 118,
        child: HoverTap(
          onTap: () => openRelease(context, entry),
          borderRadius: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 164,
                width: 118,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ReleasePoster(url: entry.thumbnail, radius: 12),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.5, 1],
                          colors: [Color(0x00000000), Color(0xCC000000)],
                        ),
                      ),
                    ),
                    const PositionedDirectional(
                      top: 7,
                      start: 7,
                      child: NewBadge(compact: true),
                    ),
                    PositionedDirectional(
                      start: 8,
                      end: 8,
                      bottom: 8,
                      child: Text(
                        releaseEpisodeLabel(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                releaseAgo(entry.time),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
