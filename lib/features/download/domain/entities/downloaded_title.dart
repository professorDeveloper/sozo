import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';

/// One title in the offline library: everything finished for it, in one card.
class DownloadedTitle {
  const DownloadedTitle({
    required this.key,
    required this.lead,
    required this.completed,
    required this.total,
    required this.sizeBytes,
    required this.lastAt,
    this.snapshot,
  });

  final String key;

  /// The newest finished download, whose poster and name the card shows.
  final DownloadItem lead;
  final int completed;
  final int total;
  final int sizeBytes;
  final int lastAt;
  final OfflineTitle? snapshot;

  String get title {
    final saved = snapshot?.title ?? '';
    return saved.isNotEmpty ? saved : lead.title;
  }

  String get provider => lead.provider;
  String? get thumbnailUrl => snapshot?.thumbnail ?? lead.thumbnailUrl;
  bool get isReader => lead.isManga;
  bool get isMovie => !lead.isManga && !lead.isSerial && total == 1;

  /// Titles with at least one finished download, most recently finished first.
  static List<DownloadedTitle> group(
    List<DownloadItem> items, {
    OfflineTitle? Function(String key)? snapshotOf,
  }) {
    final groups = <String, List<DownloadItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.groupKey, () => []).add(item);
    }
    final out = <DownloadedTitle>[];
    for (final entry in groups.entries) {
      final done = [
        for (final d in entry.value)
          if (d.status == DownloadStatus.completed) d,
      ];
      if (done.isEmpty) continue;
      done.sort((a, b) => _at(b).compareTo(_at(a)));
      out.add(
        DownloadedTitle(
          key: entry.key,
          lead: done.first,
          completed: done.length,
          total: entry.value.length,
          sizeBytes: done.fold(0, (sum, d) => sum + d.sizeBytes),
          lastAt: _at(done.first),
          snapshot: snapshotOf?.call(entry.key),
        ),
      );
    }
    out.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return out;
  }

  static int _at(DownloadItem d) => d.updatedAt > 0 ? d.updatedAt : d.createdAt;
}
