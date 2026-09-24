import 'package:soplay/features/download/domain/offline_relink.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/data/chapter_read_store.dart';

/// Moves history rows and read marks from the old source's keys to the new
/// one's, renumbering episodes the way the downloads were matched.
class RelinkProgressMigrator {
  RelinkProgressMigrator({
    required HistoryService history,
    ChapterReadStore? reads,
  }) : _history = history,
       _reads = reads ?? ChapterReadStore();

  final HistoryService _history;
  final ChapterReadStore _reads;

  Future<void> call(RelinkPlan plan) async {
    final from = plan.fromContentUrl;
    final to = plan.contentUrl;
    if (from.isEmpty || to.isEmpty || from == to) return;
    final map = plan.episodeMap;

    final rows = [
      for (final h in _history.getAll())
        if (h.contentUrl == from) h,
    ];
    var carried = rows.isEmpty;
    for (final h in rows) {
      final number = h.episodeNumber;
      await _history.save(
        HistoryItem(
          contentUrl: to,
          provider: plan.provider,
          title: h.title,
          thumbnail: h.thumbnail,
          isSerial: h.isSerial,
          episodeIndex: h.episodeIndex,
          episodeNumber: number == null ? null : (map[number] ?? number),
          episodeLabel: h.episodeLabel,
          positionMs: h.positionMs,
          durationMs: h.durationMs,
          watchedAt: h.watchedAt,
          mediaType: h.mediaType,
        ),
      );
    }
    if (rows.isNotEmpty) carried = _history.get(to) != null;
    // Incognito or a private title refuses the copy; the old rows then stay.
    if (carried && rows.isNotEmpty) await _history.removeByContentUrl(from);

    final read = _reads.read(plan.fromProvider, from);
    if (read.isNotEmpty) {
      await _reads.mark(plan.provider, to, [for (final n in read) map[n] ?? n]);
      await _reads.clear(plan.fromProvider, from);
    }
  }
}
