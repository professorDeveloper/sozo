import 'package:flutter/foundation.dart';

import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';
import 'package:soplay/features/download/domain/offline_relink.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/repositories/offline_title_repository.dart';

DownloadItem episode(
  int number, {
  String contentUrl = 'https://old.test/show',
  String provider = 'old',
  DownloadStatus status = DownloadStatus.completed,
  String? label,
}) {
  final id = DownloadRequest.videoId(
    contentUrl: contentUrl,
    episodeNumber: number,
  );
  return DownloadItem(
    id: id,
    contentUrl: contentUrl,
    provider: provider,
    title: 'Show',
    sourceUrl: 'https://cdn.test/$number.mp4',
    relativePath: DownloadLayout.artefactFor(id, kind: DownloadKind.video),
    thumbnailRelativePath: DownloadLayout.thumbnailFor(id, '.jpg'),
    createdAt: number,
    updatedAt: number,
    status: status,
    isSerial: true,
    episodeNumber: number,
    episodeLabel: label ?? 'Episode $number',
    sizeBytes: 100,
  );
}

DownloadItem chapter(
  int number, {
  String contentUrl = 'https://old.test/manga',
  String provider = 'mn:old',
  DownloadStatus status = DownloadStatus.completed,
}) {
  final ref = '/old/ch$number';
  final id = DownloadRequest.mangaChapterId(
    contentUrl: contentUrl,
    provider: provider,
    chapterRef: ref,
  );
  return DownloadItem(
    id: id,
    contentUrl: contentUrl,
    provider: provider,
    title: 'Manga',
    sourceUrl: '',
    kind: DownloadKind.manga,
    relativePath: DownloadLayout.dirFor(id),
    createdAt: number,
    status: status,
    isSerial: true,
    episodeNumber: number,
    episodeLabel: 'Chapter $number',
    chapterRef: ref,
    chapterIndex: number - 1,
  );
}

DownloadItem movie({
  String contentUrl = 'https://old.test/film',
  String provider = 'old',
}) {
  final id = DownloadRequest.videoId(contentUrl: contentUrl);
  return DownloadItem(
    id: id,
    contentUrl: contentUrl,
    provider: provider,
    title: 'Film',
    sourceUrl: 'https://cdn.test/film.mp4',
    relativePath: DownloadLayout.artefactFor(id, kind: DownloadKind.video),
    createdAt: 1,
    status: DownloadStatus.completed,
  );
}

class MemoryDownloads implements DownloadRepository {
  MemoryDownloads([Iterable<DownloadItem> items = const []]) {
    for (final i in items) {
      rows[i.id] = i;
    }
  }

  final Map<String, DownloadItem> rows = {};
  final ValueNotifier<int> _revision = ValueNotifier(0);

  /// Paths [absolutePathOf] answers with, by id. Absent means not on disk.
  final Map<String, String> paths = {};

  void put(DownloadItem item) {
    rows[item.id] = item;
    _revision.value++;
  }

  void delete(String id) {
    rows.remove(id);
    _revision.value++;
  }

  @override
  ValueListenable<int> get revision => _revision;

  @override
  List<DownloadItem> items() => rows.values.toList();

  @override
  DownloadItem? byId(String id) => rows[id];

  @override
  String? absolutePathOf(DownloadItem item) => paths[item.id];

  @override
  String? thumbnailPathOf(DownloadItem item) => null;

  @override
  Future<int> relink(List<RelinkMove> moves) async {
    var moved = 0;
    for (final m in moves) {
      final from = rows[m.from.id];
      if (from == null || from.status.isActive) continue;
      rows.remove(m.from.id);
      rows[m.to.id] = m.to;
      moved++;
    }
    _revision.value++;
    return moved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryTitles implements OfflineTitleRepository {
  final Map<String, OfflineTitle> saved = {};
  final List<DetailEntity> notedDetails = [];
  final List<PlaybackEntity> notedEpisodes = [];

  @override
  ValueListenable<int> get revision => ValueNotifier(0);

  @override
  OfflineTitle? get(String contentUrl) => saved[contentUrl];

  @override
  List<OfflineTitle> all() => saved.values.toList();

  @override
  Future<void> noteDetail(DetailEntity detail) async =>
      notedDetails.add(detail);

  @override
  Future<void> noteEpisodes(
    PlaybackEntity playback, {
    String? contentUrl,
  }) async => notedEpisodes.add(playback);

  @override
  Future<void> remove(String contentUrl) async => saved.remove(contentUrl);

  @override
  Future<void> save(OfflineTitle title) async =>
      saved[title.contentUrl] = title;
}
