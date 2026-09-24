import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';

class RelinkMove {
  const RelinkMove(this.from, this.to);

  final DownloadItem from;
  final DownloadItem to;
}

/// Which downloads of one title can follow it to another source, and which
/// cannot.
class RelinkPlan {
  const RelinkPlan({
    required this.fromProvider,
    required this.fromContentUrl,
    required this.provider,
    required this.contentUrl,
    required this.moves,
    required this.unmatched,
  });

  final String fromProvider;
  final String fromContentUrl;
  final String provider;
  final String contentUrl;
  final List<RelinkMove> moves;

  /// No episode on the new source answers to these, or one already does and
  /// has its own download. They stay where they are.
  final List<DownloadItem> unmatched;

  int get total => moves.length + unmatched.length;

  /// Old episode number to new, for carrying watch progress across.
  Map<int, int> get episodeMap => {
    for (final m in moves)
      if (m.from.episodeNumber != null && m.to.episodeNumber != null)
        m.from.episodeNumber!: m.to.episodeNumber!,
  };
}

abstract final class OfflineRelink {
  /// Matches [items] against [episodes] on the new source: by episode number
  /// first, then by label. Positions are never used — two sources rarely
  /// agree on where a run starts, and a download filed under the wrong episode
  /// is worse than one left behind.
  static RelinkPlan plan({
    required List<DownloadItem> items,
    required String provider,
    required String contentUrl,
    required List<EpisodeEntity> episodes,
    bool Function(String id)? taken,
  }) {
    final byNumber = <int, EpisodeEntity>{};
    final byLabel = <String, EpisodeEntity>{};
    for (final ep in episodes) {
      if (ep.episode > 0) byNumber.putIfAbsent(ep.episode, () => ep);
      final label = _norm(ep.label);
      if (label.isNotEmpty) byLabel.putIfAbsent(label, () => ep);
    }

    final used = <EpisodeEntity>{};
    final targets = <String>{};
    final moves = <RelinkMove>[];
    final unmatched = <DownloadItem>[];

    for (final item in items) {
      final to = _target(
        item,
        provider: provider,
        contentUrl: contentUrl,
        byNumber: byNumber,
        byLabel: byLabel,
        used: used,
      );
      if (to == null ||
          to.id == item.id ||
          targets.contains(to.id) ||
          (taken?.call(to.id) ?? false)) {
        unmatched.add(item);
        continue;
      }
      targets.add(to.id);
      moves.add(RelinkMove(item, to));
    }

    final lead = items.isEmpty ? null : items.first;
    return RelinkPlan(
      fromProvider: lead?.provider ?? '',
      fromContentUrl: lead?.contentUrl ?? '',
      provider: provider,
      contentUrl: contentUrl,
      moves: moves,
      unmatched: unmatched,
    );
  }

  static DownloadItem? _target(
    DownloadItem item, {
    required String provider,
    required String contentUrl,
    required Map<int, EpisodeEntity> byNumber,
    required Map<String, EpisodeEntity> byLabel,
    required Set<EpisodeEntity> used,
  }) {
    final isMovie =
        !item.isManga && !item.isSerial && item.episodeNumber == null;
    if (isMovie) {
      return item.rekeyed(
        id: DownloadRequest.videoId(contentUrl: contentUrl),
        contentUrl: contentUrl,
        provider: provider,
      );
    }

    EpisodeEntity? match;
    final number = item.episodeNumber;
    if (number != null && number > 0) {
      final candidate = byNumber[number];
      if (candidate != null && !used.contains(candidate)) match = candidate;
    }
    if (match == null) {
      final candidate = byLabel[_norm(item.episodeLabel ?? '')];
      if (candidate != null && !used.contains(candidate)) match = candidate;
    }
    if (match == null) return null;
    if (item.isManga && match.mediaRef.isEmpty) return null;
    used.add(match);

    final id = item.isManga
        ? DownloadRequest.mangaChapterId(
            contentUrl: contentUrl,
            provider: provider,
            chapterRef: match.mediaRef,
          )
        : DownloadRequest.videoId(
            contentUrl: contentUrl,
            episodeNumber: match.episode,
          );
    return item.rekeyed(
      id: id,
      contentUrl: contentUrl,
      provider: provider,
      chapterRef: item.isManga ? match.mediaRef : null,
      episodeNumber: match.episode,
      episodeLabel: match.label.isEmpty ? null : match.label,
    );
  }

  static String _norm(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
