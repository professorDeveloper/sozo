import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/data/models/download_item_model.dart';
import 'package:soplay/features/download/data/storage/download_storage.dart';
import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';
import 'package:soplay/features/download/domain/offline_relink.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/usecases/relink_downloads_usecase.dart';

import 'offline_fakes.dart';

const _newUrl = 'https://new.test/show';

List<EpisodeEntity> _eps(List<int> numbers, {String prefix = 'new'}) => [
  for (final n in numbers)
    EpisodeEntity(episode: n, label: 'Episode $n', mediaRef: '/$prefix/$n'),
];

void main() {
  group('matching downloads to the new source', () {
    test('by episode number, with the folder following the id', () {
      final plan = OfflineRelink.plan(
        items: [episode(1), episode(2)],
        provider: 'new',
        contentUrl: _newUrl,
        episodes: _eps([1, 2, 3]),
      );

      expect(plan.moves, hasLength(2));
      expect(plan.unmatched, isEmpty);
      final to = plan.moves.first.to;
      final expected = DownloadRequest.videoId(
        contentUrl: _newUrl,
        episodeNumber: 1,
      );
      expect(to.id, expected);
      expect(to.contentUrl, _newUrl);
      expect(to.provider, 'new');
      expect(to.relativePath, 'downloads/$expected/video.mp4');
      expect(to.thumbnailRelativePath, 'downloads/$expected/thumbnail.jpg');
      expect(to.status, DownloadStatus.completed);
      expect(plan.episodeMap, {1: 1, 2: 2});
    });

    test('falls back to the label when the numbers disagree', () {
      final plan = OfflineRelink.plan(
        items: [episode(0, label: 'Special: Beach')],
        provider: 'new',
        contentUrl: _newUrl,
        episodes: const [
          EpisodeEntity(episode: 13, label: 'special:  beach', mediaRef: 'x'),
        ],
      );
      expect(plan.moves.single.to.episodeNumber, 13);
      expect(plan.episodeMap, {0: 13});
    });

    test('never matches by position', () {
      final plan = OfflineRelink.plan(
        items: [episode(40)],
        provider: 'new',
        contentUrl: _newUrl,
        episodes: _eps([1, 2, 3]),
      );
      expect(plan.moves, isEmpty);
      expect(plan.unmatched, hasLength(1));
    });

    test('leaves a download behind when the target already has one', () {
      final taken = DownloadRequest.videoId(
        contentUrl: _newUrl,
        episodeNumber: 2,
      );
      final plan = OfflineRelink.plan(
        items: [episode(1), episode(2)],
        provider: 'new',
        contentUrl: _newUrl,
        episodes: _eps([1, 2]),
        taken: (id) => id == taken,
      );
      expect(plan.moves, hasLength(1));
      expect(plan.unmatched.single.episodeNumber, 2);
      expect(plan.total, 2);
    });

    test('a chapter takes the new source ref and provider into its id', () {
      final plan = OfflineRelink.plan(
        items: [chapter(5)],
        provider: 'mn:new',
        contentUrl: 'https://new.test/manga',
        episodes: _eps([5]),
      );
      final to = plan.moves.single.to;
      expect(
        to.id,
        DownloadRequest.mangaChapterId(
          contentUrl: 'https://new.test/manga',
          provider: 'mn:new',
          chapterRef: '/new/5',
        ),
      );
      expect(to.chapterRef, '/new/5');
      expect(to.relativePath, DownloadLayout.dirFor(to.id));
      expect(to.chapterIndex, 4);
    });

    test('a film needs no episode list', () {
      final plan = OfflineRelink.plan(
        items: [movie()],
        provider: 'new',
        contentUrl: 'https://new.test/film',
        episodes: const [],
      );
      expect(
        plan.moves.single.to.id,
        DownloadRequest.videoId(contentUrl: 'https://new.test/film'),
      );
    });
  });

  group('relinking', () {
    test('moves the rows, the snapshot and hands progress over', () async {
      final downloads = MemoryDownloads([
        episode(1),
        episode(2),
        episode(7),
        episode(3, contentUrl: 'https://old.test/other'),
      ]);
      final titles = MemoryTitles()
        ..saved['https://old.test/show'] = const OfflineTitle(
          contentUrl: 'https://old.test/show',
          provider: 'old',
          title: 'Show',
          description: 'Saved words',
          savedAt: 0,
        );
      RelinkPlan? migrated;
      final relink = RelinkDownloadsUseCase(
        downloads: downloads,
        titles: titles,
        migrateProgress: (plan) async => migrated = plan,
      );

      final plan = relink.plan(
        'https://old.test/show',
        provider: 'new',
        contentUrl: _newUrl,
        episodes: _eps([1, 2]),
      );
      expect(plan.moves, hasLength(2));
      expect(plan.unmatched.single.episodeNumber, 7);

      final outcome = await relink(
        plan,
        providerName: 'New Source',
        episodes: _eps([1, 2]),
      );

      expect(outcome.moved, 2);
      expect(outcome.left, 1);
      expect(
        downloads.items().where((d) => d.contentUrl == _newUrl),
        hasLength(2),
      );
      final saved = titles.saved[_newUrl]!;
      expect(saved.provider, 'new');
      expect(saved.providerName, 'New Source');
      expect(saved.description, 'Saved words');
      expect(saved.episodes, hasLength(2));
      // Episode 7 is still on the old source, so its snapshot stays too.
      expect(titles.saved.containsKey('https://old.test/show'), isTrue);
      expect(migrated, same(plan));
    });

    test('the old snapshot goes when nothing is left behind', () async {
      final downloads = MemoryDownloads([episode(1)]);
      final titles = MemoryTitles()
        ..saved['https://old.test/show'] = const OfflineTitle(
          contentUrl: 'https://old.test/show',
          provider: 'old',
          title: 'Show',
          savedAt: 0,
        );
      final relink = RelinkDownloadsUseCase(
        downloads: downloads,
        titles: titles,
      );
      final plan = relink.plan(
        'https://old.test/show',
        provider: 'new',
        contentUrl: _newUrl,
        episodes: _eps([1]),
      );
      await relink(plan);
      expect(titles.saved.keys, [_newUrl]);
    });

    test('reports what the repository refused to move', () async {
      final downloads = MemoryDownloads([
        episode(1, status: DownloadStatus.downloading),
      ]);
      final relink = RelinkDownloadsUseCase(
        downloads: downloads,
        titles: MemoryTitles(),
      );
      final plan = relink.plan(
        'https://old.test/show',
        provider: 'new',
        contentUrl: _newUrl,
        episodes: _eps([1]),
      );
      final outcome = await relink(plan);
      expect(outcome.moved, 0);
      expect(downloads.items().single.contentUrl, 'https://old.test/show');
    });
  });

  group('on disk', () {
    late Directory temp;
    late DownloadStorage storage;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('sozo_relink');
      storage = DownloadStorage();
      await storage.initialize(preferredBase: temp.path);
    });

    tearDown(() => temp.delete(recursive: true));

    test('the folder is renamed, never onto another one', () async {
      final dir = await storage.ensureDir('old1');
      await File('${dir.path}/video.mp4').writeAsString('bytes');

      expect(await storage.rekey('old1', 'new1'), isTrue);
      expect(await File('${storage.dirOf('new1')}/video.mp4').exists(), isTrue);
      expect(await Directory(storage.dirOf('old1')).exists(), isFalse);

      await storage.ensureDir('old2');
      await storage.ensureDir('taken');
      expect(await storage.rekey('old2', 'taken'), isFalse);
      expect(await Directory(storage.dirOf('old2')).exists(), isTrue);
    });

    test('the sidecar describes the row without its secrets', () async {
      final item = episode(1).copyWith(
        headers: const {'Cookie': 'secret'},
        pageUrls: const ['https://cdn.test/p1.jpg'],
      );
      await storage.ensureDir(item.id);
      await storage.writeSidecar(item.id, DownloadItemModel.toSidecar(item));

      final file = File(
        '${storage.dirOf(item.id)}/${DownloadLayout.sidecarName}',
      );
      final json = jsonDecode(await file.readAsString()) as Map;
      expect(json['id'], item.id);
      expect(json['contentUrl'], item.contentUrl);
      expect(json['episodeNumber'], 1);
      expect(json.containsKey('headers'), isFalse);
      expect(json.containsKey('pageUrls'), isFalse);
      final back = DownloadItemModel.fromJson(Map<String, dynamic>.from(json));
      expect(back.relativePath, item.relativePath);
      expect(await File(DownloadLayout.partOf(file.path)).exists(), isFalse);
    });
  });

  group('playing from disk', () {
    test('a finished episode resolves to its local file', () {
      final ep = episode(2);
      final downloads = MemoryDownloads([ep])..paths[ep.id] = '/data/ep2.mp4';
      final local = GetDownloadsUseCase(
        downloads,
      ).localVideo(contentUrl: 'https://old.test/show', episodeNumber: 2);
      expect(local?.url, '/data/ep2.mp4');
      expect(local?.type, isNull);
    });

    test('nothing when the file is gone or the download unfinished', () {
      final gone = episode(1);
      final running = episode(2, status: DownloadStatus.downloading);
      final downloads = MemoryDownloads([gone, running])
        ..paths[running.id] = '/data/ep2.mp4';
      final uc = GetDownloadsUseCase(downloads);
      expect(
        uc.localVideo(contentUrl: 'https://old.test/show', episodeNumber: 1),
        isNull,
      );
      expect(
        uc.localVideo(contentUrl: 'https://old.test/show', episodeNumber: 2),
        isNull,
      );
      expect(uc.localVideo(contentUrl: '', episodeNumber: 2), isNull);
    });

    test('finished siblings come back in episode order', () {
      final downloads = MemoryDownloads([
        episode(3),
        episode(1),
        episode(2, status: DownloadStatus.failed),
      ]);
      final done = GetDownloadsUseCase(
        downloads,
      ).completedOf('https://old.test/show');
      expect([for (final d in done) d.episodeNumber], [1, 3]);
    });
  });
}
