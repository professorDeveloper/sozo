import 'package:soplay/features/comments/domain/episode_key.dart';
import 'package:soplay/features/detail/domain/playback/watch_progress.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

/// How a comment is drawn with spoilers in mind.
enum SpoilerVisibility {
  visible,

  /// Its author marked it a spoiler.
  spoiler,

  /// It is about an episode the viewer has not finished.
  unwatched,
}

class SpoilerRules {
  const SpoilerRules._();

  /// Own comments and ones the viewer already tapped open always show.
  ///
  /// Watching the episode right now ([playheadSec] set) only hides what was
  /// written about a later moment than the playhead; a comment with no
  /// moment is the episode's general thread and shows.
  static SpoilerVisibility visibility({
    required bool spoiler,
    required bool isOwn,
    required bool revealed,
    required bool hideUnwatched,
    required String? episodeKey,
    required bool episodeFinished,
    int? atSec,
    int? playheadSec,
  }) {
    if (isOwn || revealed) return SpoilerVisibility.visible;
    if (spoiler) return SpoilerVisibility.spoiler;
    if (!hideUnwatched || episodeKey == null || episodeFinished) {
      return SpoilerVisibility.visible;
    }
    if (playheadSec != null) {
      return atSec != null && atSec > playheadSec
          ? SpoilerVisibility.unwatched
          : SpoilerVisibility.visible;
    }
    return SpoilerVisibility.unwatched;
  }

  /// Whether history says the viewer has finished the episode [episodeKey].
  ///
  /// Finished means watched past the threshold the trackers use, or moved on
  /// to a later episode of the same title: people skip a recap episode and
  /// still know what happened in it.
  static bool episodeFinished(
    String? episodeKey,
    String contentUrl,
    Iterable<HistoryItem> history,
  ) {
    final n = EpisodeKey.numberOf(episodeKey);
    if (n == null) return true;
    for (final row in history) {
      if (row.contentUrl != contentUrl) continue;
      final rowN = row.episodeNumber ?? row.episodeIndex;
      if (rowN == null) continue;
      if (rowN > n) return true;
      if (rowN == n &&
          WatchProgress.isWatched(
            Duration(milliseconds: row.positionMs),
            Duration(milliseconds: row.durationMs),
          )) {
        return true;
      }
    }
    return false;
  }
}
