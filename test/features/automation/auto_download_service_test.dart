import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/automation/data/auto_download_service.dart';
import 'package:soplay/features/automation/data/automation_settings.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/storage_usage.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/download_request_builder.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

class _Downloads implements DownloadRepository {
  final rows = <String, DownloadItem>{};
  final enqueued = <String>[];
  final removed = <String>[];
  int usedBytes = 0;
  EnqueueOutcome next = EnqueueOutcome.started;

  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  @override
  List<DownloadItem> items() => rows.values.toList();

  @override
  DownloadItem? byId(String id) => rows[id];

  @override
  Future<EnqueueOutcome> enqueue(DownloadRequest request) async {
    enqueued.add(request.id);
    if (next == EnqueueOutcome.started) {
      rows[request.id] = _item(
        request.id,
        request.contentUrl,
        request.episodeNumber,
        status: DownloadStatus.downloading,
      );
    }
    return next;
  }

  @override
  Future<StorageUsage> usage() async =>
      StorageUsage(usedBytes: usedBytes, freeBytes: 1 << 40, itemCount: 0);

  @override
  Future<void> removeAll(Iterable<String> ids) async {
    for (final id in ids) {
      removed.add(id);
      rows.remove(id);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Builder implements DownloadRequestBuilder {
  final resolved = <int>[];
  final failures = <int, DownloadBuildFailure>{};

  @override
  Future<DownloadBuild> quietVideo(
    DownloadTitle title,
    EpisodeEntity ep,
  ) async {
    resolved.add(ep.episode);
    final failure = failures[ep.episode];
    if (failure != null) return DownloadBuild.failed(failure);
    return DownloadBuild.ready(
      DownloadRequest.video(
        contentUrl: title.contentUrl,
        provider: title.provider,
        title: title.title,
        sourceUrl: 'https://cdn/${ep.episode}.mp4',
        isSerial: true,
        episodeNumber: ep.episode,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _url = 'https://src/show';

DownloadItem _item(
  String id,
  String contentUrl,
  int? episode, {
  DownloadStatus status = DownloadStatus.completed,
}) => DownloadItem(
  id: id,
  contentUrl: contentUrl,
  provider: 'p1',
  title: 'Show',
  sourceUrl: '',
  relativePath: 'downloads/$id/video.mp4',
  createdAt: 0,
  status: status,
  isSerial: true,
  episodeNumber: episode,
);

String _id(int episode) =>
    DownloadRequest.videoId(contentUrl: _url, episodeNumber: episode);

List<EpisodeEntity> _episodes(int from, int to) => [
  for (var n = from; n <= to; n++)
    EpisodeEntity(episode: n, label: 'Ep $n', mediaRef: 'ref-$n'),
];

FollowedTitle _title({bool auto = true, int from = 10}) => FollowedTitle(
  contentUrl: _url,
  provider: 'p1',
  title: 'Show',
  thumbnail: '',
  lastEpisodeCount: from,
  autoDownload: auto,
  autoDownloadFrom: from,
);

void main() {
  late Box box;
  late AutomationSettings settings;
  late _Downloads downloads;
  late _Builder builder;
  var wifi = true;
  var watched = <String>{};
  var notified = <int>[];

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_auto_download');
    box = await Hive.openBox('sozo_auto_download');
  });
  tearDownAll(() async => Hive.close());

  setUp(() async {
    await box.clear();
    settings = AutomationSettings(box: box);
    await settings.setAutoDownloadEnabled(true);
    downloads = _Downloads();
    builder = _Builder();
    wifi = true;
    watched = <String>{};
    notified = <int>[];
  });

  AutoDownloadService make({Duration wait = const Duration(seconds: 1)}) =>
      AutoDownloadService(
        settings: settings,
        downloads: downloads,
        builder: builder,
        isReader: (_) => false,
        isWatched: (item) => watched.contains(item.id),
        unmeteredNetwork: () async => wifi,
        notify: (n) async => notified.add(n),
        now: () => DateTime(2026, 9, 24, 12),
        queueWait: wait,
      );

  test('settings default to off, Wi-Fi only, keep 3, 5 GB cap', () {
    final fresh = AutomationSettings(box: box);
    expect(fresh.autoDownloadWifiOnly, isTrue);
    expect(fresh.keepLast, 3);
    expect(fresh.maxBytes, AutomationSettings.defaultMaxBytes);
    expect(fresh.autoDeleteWatched, isFalse);
    expect(fresh.prefetchNextEpisode, isTrue);
    expect(fresh.prefetchNextChapter, isTrue);
  });

  test(
    'only the newest N episodes above the floor are queued, oldest first',
    () async {
      final s = make();
      s.collect(_title(), _episodes(1, 16));
      expect(s.pendingIds, [_id(14), _id(15), _id(16)]);

      final status = await s.drain();
      expect(builder.resolved, [14, 15, 16]);
      expect(downloads.enqueued, [_id(14), _id(15), _id(16)]);
      expect(status!.queued, 3);
      expect(settings.autoIds, containsAll([_id(14), _id(15), _id(16)]));
      expect(notified, [3]);
      expect(settings.lastStatus!.queued, 3);
    },
  );

  test('nothing happens when the title or the global switch is off', () {
    final s = make();
    s.collect(_title(auto: false), _episodes(1, 16));
    expect(s.pendingIds, isEmpty);
    settings.setAutoDownloadEnabled(false);
    s.collect(_title(), _episodes(1, 16));
    expect(s.pendingIds, isEmpty);
  });

  test('a title with no floor yet is only seeded, never downloaded', () {
    final s = make();
    s.collect(_title(from: 0), _episodes(1, 16));
    expect(s.pendingIds, isEmpty);
  });

  test(
    'handled, skipped and already-present episodes are not queued again',
    () async {
      await settings.rememberAuto(_id(16));
      await settings.rememberSkipped(_id(15));
      downloads.rows[_id(14)] = _item(_id(14), _url, 14);
      final s = make();
      s.collect(_title(), _episodes(11, 16));
      expect(s.pendingIds, isEmpty);
    },
  );

  test('off Wi-Fi it holds, keeps the episodes, and resumes later', () async {
    wifi = false;
    final s = make();
    s.collect(_title(), _episodes(11, 12));
    final held = await s.drain();
    expect(held!.hold, AutoDownloadHold.wifi);
    expect(builder.resolved, isEmpty, reason: 'nothing resolved early');
    expect(s.pendingIds, [_id(11), _id(12)]);

    wifi = true;
    final resumed = await s.drain();
    expect(resumed!.queued, 2);
    expect(s.pendingIds, isEmpty);
  });

  test('Wi-Fi only can be turned off', () async {
    wifi = false;
    await settings.setAutoDownloadWifiOnly(false);
    final s = make();
    s.collect(_title(), _episodes(11, 11));
    expect((await s.drain())!.queued, 1);
  });

  test('the storage cap stops the run before resolving', () async {
    await settings.setMaxBytes(AutomationSettings.maxBytesChoices[1]);
    downloads.usedBytes = AutomationSettings.maxBytesChoices[1];
    final s = make();
    s.collect(_title(), _episodes(11, 11));
    final status = await s.drain();
    expect(status!.hold, AutoDownloadHold.storageCap);
    expect(builder.resolved, isEmpty);
  });

  test('an episode waiting in the queue delays the next resolve', () async {
    downloads.rows['other'] = _item(
      'other',
      'https://src/other',
      1,
      status: DownloadStatus.pending,
    );
    final s = make();
    s.collect(_title(), _episodes(11, 11));
    final run = s.drain();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(builder.resolved, isEmpty, reason: 'resolved at start, not early');

    downloads.rows['other'] = _item('other', 'https://src/other', 1);
    downloads.revision.value++;
    expect((await run)!.queued, 1);
  });

  test('a queue that never frees up is reported as busy', () async {
    downloads.rows['other'] = _item(
      'other',
      'https://src/other',
      1,
      status: DownloadStatus.pending,
    );
    final s = make(wait: const Duration(milliseconds: 20));
    s.collect(_title(), _episodes(11, 11));
    expect((await s.drain())!.hold, AutoDownloadHold.busy);
    expect(s.pendingIds, [_id(11)]);
  });

  test('embed-only episodes are skipped once and remembered', () async {
    builder.failures[11] = DownloadBuildFailure.needsPlayback;
    builder.failures[12] = DownloadBuildFailure.resolveFailed;
    final s = make();
    s.collect(_title(), _episodes(11, 12));
    final status = await s.drain();
    expect(status!.skipped, 1);
    expect(settings.skippedIds, [_id(11)]);
    s.collect(_title(), _episodes(11, 12));
    expect(s.pendingIds, [_id(12)], reason: 'a failed resolve is retried');
  });

  test('prune removes watched auto downloads, never hand-made ones', () async {
    await settings.setAutoDeleteWatched(true);
    await settings.rememberAuto(_id(11));
    downloads.rows[_id(11)] = _item(_id(11), _url, 11);
    downloads.rows[_id(12)] = _item(_id(12), _url, 12);
    watched = {_id(11), _id(12)};
    expect(await make().prune(), 1);
    expect(downloads.removed, [_id(11)]);
  });

  test('prune keeps only the newest N finished auto downloads', () async {
    await settings.setKeepLast(2);
    for (final n in [11, 12, 13, 14]) {
      await settings.rememberAuto(_id(n));
      downloads.rows[_id(n)] = _item(
        _id(n),
        _url,
        n,
        status: n == 11 ? DownloadStatus.downloading : DownloadStatus.completed,
      );
    }
    expect(await make().prune(), 1);
    expect(downloads.removed, [_id(12)], reason: 'in-flight files are left');
  });
}
