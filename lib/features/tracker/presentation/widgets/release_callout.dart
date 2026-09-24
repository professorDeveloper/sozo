import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/notifications/presentation/widgets/animated_bell.dart';
import 'package:soplay/features/tracker/data/release_feed_store.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';

/// The release a detail page was opened for, from the feed when it has the
/// title (it knows the whole range), else just the focused episode.
ReleaseEntry? releaseForCallout(
  String contentUrl,
  int? focusEpisode, {
  bool reading = false,
}) {
  if (focusEpisode == null || focusEpisode <= 0) return null;
  ReleaseEntry? fromFeed;
  try {
    fromFeed = getIt<ReleaseFeedStore>().entries().where(
      (e) => e.contentUrl == contentUrl,
    ).firstOrNull;
  } catch (_) {}
  if (fromFeed != null && fromFeed.episode >= focusEpisode) {
    return fromFeed.copyWith(fromEpisode: focusEpisode.clamp(1, fromFeed.episode));
  }
  return ReleaseEntry(
    provider: '',
    contentUrl: contentUrl,
    title: '',
    thumbnail: '',
    mode: reading ? 'manga' : 'video',
    episode: focusEpisode,
    fromEpisode: focusEpisode,
    at: DateTime.now().millisecondsSinceEpoch,
  );
}

/// "New episode — Watch episode 12", at the top of a title opened from a
/// release notification. One tap to the list, opened on that episode.
class ReleaseCallout extends StatelessWidget {
  const ReleaseCallout({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onDismiss,
  });

  final ReleaseEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final reading = entry.isReading;
    final many = entry.newCount > 1;
    final kicker = reading
        ? (many
              ? 'release_notify.callout_new_chapters'.tr(args: ['${entry.newCount}'])
              : 'release_notify.callout_new_chapter'.tr())
        : (many
              ? 'release_notify.callout_new_episodes'.tr(args: ['${entry.newCount}'])
              : 'release_notify.callout_new_episode'.tr());
    final cta = reading
        ? 'release_notify.callout_read'.tr(args: ['${entry.fromEpisode}'])
        : 'release_notify.callout_watch'.tr(args: ['${entry.fromEpisode}']);
    final reduce = MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: const Cubic(0.05, 0.7, 0.1, 1.0),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                AppColors.primary.withValues(alpha: 0.30),
                AppColors.primary.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedBell(
                      state: BellState.on,
                      color: AppColors.onPrimary,
                      ringColor: Colors.white,
                      size: 18,
                      ringOnAppear: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      kicker.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'general.close'.tr(),
                    onPressed: onDismiss,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    autofocus: true,
                    onPressed: onOpen,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kButtonRadius),
                      ),
                    ),
                    icon: Icon(
                      reading ? Icons.menu_book_rounded : Icons.play_arrow_rounded,
                      size: reading ? 20 : 24,
                    ),
                    label: Text(
                      cta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
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
