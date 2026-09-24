import 'package:flutter/foundation.dart';

import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';

/// Reading the offline library.
///
/// Everything a screen needs in order to DRAW downloads, and nothing that
/// changes them. It carries [revision] and the two path resolvers as well as
/// the list, so a widget never has to reach past the domain for them — the
/// alternative was every list, badge and row holding the repository directly,
/// which is how the old code ended up with six widgets each deciding for
/// themselves what "downloaded" meant.
class GetDownloadsUseCase {
  const GetDownloadsUseCase(this.repository);

  final DownloadRepository repository;

  /// Newest first.
  List<DownloadItem> call() => repository.items();

  DownloadItem? byId(String id) => repository.byId(id);

  /// Ticks whenever anything in the library changes.
  ValueListenable<int> get revision => repository.revision;

  /// True while the queue is holding for Wi-Fi.
  bool get isWaitingForWifi => repository.isWaitingForWifi;

  /// A path that can actually be opened, or null when the artefact is gone.
  ///
  /// Null is a real answer and callers are expected to use it: a row can say
  /// "Downloaded" and still have nothing behind it if the file was removed
  /// outside the app between the sweep and the tap.
  String? pathOf(DownloadItem item) => repository.absolutePathOf(item);

  /// The cached poster, or null.
  String? thumbnailOf(DownloadItem item) => repository.thumbnailPathOf(item);

  /// The pages of a finished chapter, as local files.
  /// A finished episode (or, with no [episodeNumber], a film) of [contentUrl]
  /// that can be played from disk right now.
  LocalVideo? localVideo({required String contentUrl, int? episodeNumber}) {
    if (contentUrl.isEmpty) return null;
    final item = repository.byId(
      DownloadRequest.videoId(
        contentUrl: contentUrl,
        episodeNumber: episodeNumber,
      ),
    );
    if (item == null ||
        item.isManga ||
        item.status != DownloadStatus.completed) {
      return null;
    }
    final path = repository.absolutePathOf(item);
    if (path == null) return null;
    return LocalVideo(
      item: item,
      url: item.isHls ? Uri.file(path).toString() : path,
      type: item.isHls ? 'hls' : null,
    );
  }

  /// Every finished download of one title, in reading/watching order.
  List<DownloadItem> completedOf(String groupKey) =>
      [
        for (final d in repository.items())
          if (d.groupKey == groupKey && d.status == DownloadStatus.completed) d,
      ]..sort((a, b) {
        final byNumber = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
        if (byNumber != 0) return byNumber;
        return (a.chapterIndex ?? 0).compareTo(b.chapterIndex ?? 0);
      });

  Future<List<MangaPageEntity>> localMangaPages(String id) =>
      repository.localMangaPages(id);

  Future<String?> localChapterHtml(String id) =>
      repository.localChapterHtml(id);
}

class LocalVideo {
  const LocalVideo({required this.item, required this.url, this.type});

  final DownloadItem item;

  /// What the player opens: a `file://` uri for a playlist, a plain path for
  /// a single file.
  final String url;
  final String? type;
}
