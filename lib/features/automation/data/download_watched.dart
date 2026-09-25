import 'package:soplay/features/detail/domain/playback/watch_progress.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/manga/data/chapter_read_store.dart';

/// Whether the viewer has finished what [item] holds: a chapter marked read,
/// or an episode whose history row passed the watched threshold.
bool isDownloadWatched(
  DownloadItem item, {
  required HistoryService history,
  required ChapterReadStore chapters,
}) {
  final number = item.episodeNumber;
  if (item.isManga) {
    return number != null &&
        chapters.isRead(item.provider, item.contentUrl, number);
  }
  final row = history.get(
    item.contentUrl,
    episodeNumber: item.isSerial ? number : null,
  );
  // `get` falls back to the title's own row, which may be another episode.
  if (row == null || (item.isSerial && row.episodeNumber != number)) {
    return false;
  }
  return WatchProgress.isWatched(
    Duration(milliseconds: row.positionMs),
    Duration(milliseconds: row.durationMs),
  );
}
