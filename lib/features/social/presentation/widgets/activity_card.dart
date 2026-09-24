import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/widgets/social_widgets.dart';

/// The translation key for what [item] says its actor did.
String activityVerbKey(ActivityItem item) => switch (item.type) {
  ActivityType.watched =>
    item.finished && item.episodeTo == null
        ? 'social.verb_finished'
        : 'social.verb_watched',
  ActivityType.read => 'social.verb_read',
  ActivityType.favorited => 'social.verb_favorited',
  ActivityType.planned => 'social.verb_planned',
  ActivityType.completed => 'social.verb_completed',
  ActivityType.unknown =>
    item.isReading ? 'social.verb_read' : 'social.verb_watched',
};

/// "Episodes 3–7", "Chapter 12", or null when the entry is about the title.
String? activityEpisodeText(ActivityItem item) {
  final from = item.episodeFrom;
  final to = item.episodeTo ?? from;
  if (to == null) return null;
  final unit = item.isReading ? 'chapter' : 'episode';
  if (from == null || from == to) {
    final label = item.episodeLabel?.trim();
    if (label != null && label.isNotEmpty && int.tryParse(label) == null) {
      return label;
    }
    return 'social.${unit}_one'.tr(args: ['$to']);
  }
  return 'social.${unit}_range'.tr(args: ['$from', '$to']);
}

void openActivityTitle(BuildContext context, ActivityItem item) {
  final url = item.contentUrl;
  if (url == null || !item.canOpen) return;
  context.push(
    '/detail',
    extra: DetailArgs(contentUrl: url, provider: item.provider),
  );
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.item,
    this.showActor = true,
    this.onDelete,
  });

  final ActivityItem item;
  final bool showActor;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final actor = showActor ? item.actor : null;
    final episodes = activityEpisodeText(item);
    final title = item.title ?? 'general.unknown'.tr();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.canOpen ? () => openActivityTitle(context, item) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Poster(url: item.thumbnail, reading: item.isReading),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (actor != null)
                      _ActorLine(actor: actor, verb: activityVerbKey(item).tr())
                    else
                      Text(
                        _capitalise(activityVerbKey(item).tr()),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (episodes != null) ...[
                          Flexible(child: _Chip(episodes)),
                          const SizedBox(width: 8),
                        ],
                        if (item.finished && item.type == ActivityType.watched)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: AppColors.success,
                            ),
                          ),
                        Text(
                          socialTimeLabel(context, item.at),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'social.activity_delete'.tr(),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalise(String s) => s.isEmpty
      ? s
      : s.characters.first.toUpperCase() +
            s.substring(s.characters.first.length);
}

class _ActorLine extends StatelessWidget {
  const _ActorLine({required this.actor, required this.verb});

  final SocialUser actor;
  final String verb;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/u/${Uri.encodeComponent(actor.username)}'),
      child: Row(
        children: [
          SocialAvatar(user: actor, size: 22),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: actor.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' $verb'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.primaryLight,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.reading});

  final String? url;
  final bool reading;

  static const double _w = 58;
  static const double _h = 84;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        reading ? Icons.menu_book_rounded : Icons.movie_outlined,
        color: AppColors.textHint,
        size: 22,
      ),
    );
    final src = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _w,
        height: _h,
        child: src == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: src,
                fit: BoxFit.cover,
                memCacheWidth: (_w * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
