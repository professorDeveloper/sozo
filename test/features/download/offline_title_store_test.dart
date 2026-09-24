import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/download/data/offline_title_store.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';

import 'offline_fakes.dart';

DetailEntity _detail(String url, {String provider = 'old'}) => DetailEntity(
  provider: provider,
  contentId: '1',
  contentUrl: url,
  title: 'Show',
  description: 'Words about the show.',
  thumbnail: 'https://img.test/p.jpg',
  year: 2021,
  duration: null,
  country: null,
  director: null,
  genres: const ['Action'],
  cast: const [],
  likes: 0,
  dislikes: 0,
  isSerial: true,
  isFavorited: null,
  screenshots: const [],
  related: const [],
);

PlaybackEntity _playback(String url) => PlaybackEntity(
  provider: 'old',
  contentUrl: url,
  isSerial: true,
  episodes: const [
    EpisodeEntity(episode: 1, label: 'One', mediaRef: 'r1'),
    EpisodeEntity(episode: 2, label: 'Two', mediaRef: 'r2'),
    EpisodeEntity(episode: 3, label: 'Three', mediaRef: 'r3'),
  ],
  videoSources: const [],
  playerSrc: null,
  headers: const {},
);

void main() {
  const url = 'https://old.test/show';
  late Directory temp;
  late Box<dynamic> box;
  late MemoryDownloads downloads;
  late OfflineTitleStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sozo_offline_titles');
    Hive.init(temp.path);
    box = await Hive.openBox('offline_titles_test');
    downloads = MemoryDownloads();
    store = OfflineTitleStore(box: box)
      ..attach(rows: downloads.items, revision: downloads.revision);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('a title with no downloads is not written', () async {
    await store.noteDetail(_detail(url));
    await store.noteEpisodes(_playback(url));
    expect(store.get(url), isNull);
  });

  test('what was seen online is saved when a download finishes', () async {
    await store.noteDetail(_detail(url));
    await store.noteEpisodes(_playback(url));
    downloads.put(episode(1, status: DownloadStatus.downloading));
    await store.syncWithRows();
    expect(store.get(url), isNull);

    downloads.put(episode(1));
    await store.syncWithRows();
    final saved = store.get(url)!;
    expect(saved.description, 'Words about the show.');
    expect(saved.genres, ['Action']);
    expect(saved.episodes, hasLength(3));
  });

  test('a download finished with nothing seen still gets a copy', () async {
    downloads.put(episode(4));
    await store.syncWithRows();
    final saved = store.get(url)!;
    expect(saved.title, 'Show');
    expect([for (final e in saved.episodes) e.episode], [4]);
  });

  test('a loaded page refreshes the saved copy', () async {
    downloads.put(episode(1));
    await store.syncWithRows();
    expect(store.get(url)!.description, isEmpty);

    await store.noteDetail(_detail(url));
    expect(store.get(url)!.description, 'Words about the show.');
    await store.noteEpisodes(_playback(url));
    expect(store.get(url)!.episodes, hasLength(3));
  });

  test('catalogue pages are never saved as a source title', () async {
    downloads.put(episode(1, contentUrl: 'anilist:1'));
    await store.noteDetail(_detail('anilist:1', provider: 'cat:anilist'));
    await store.syncWithRows();
    expect(store.get('anilist:1')?.description ?? '', isEmpty);
  });

  test('the copy goes with the last download', () async {
    final a = episode(1);
    final b = episode(2);
    downloads
      ..put(a)
      ..put(b);
    await store.syncWithRows();
    expect(store.get(url), isNotNull);

    downloads.delete(a.id);
    await store.syncWithRows();
    expect(store.get(url), isNotNull);

    downloads.delete(b.id);
    await store.syncWithRows();
    expect(store.get(url), isNull);
    expect(store.all(), isEmpty);
  });
}
