import 'package:flutter/foundation.dart';

import 'package:soplay/features/download/domain/entities/download_item.dart';
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
  Future<List<MangaPageEntity>> localMangaPages(String id) =>
      repository.localMangaPages(id);
}
