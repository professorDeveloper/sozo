// The follow list travels to the account when there is one, survives being
// offline, and carries on locally when the server has no /follows yet.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/follow_sync_remote_data_source.dart';
import 'package:soplay/features/tracker/data/follow_sync_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

class _Hive implements HiveService {
  List<Map<String, dynamic>> raw = [];

  @override
  List<Map<String, dynamic>> getFollowedRaw() =>
      raw.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> setFollowedRaw(List<Map<String, dynamic>> items) async =>
      raw = items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Episodes implements GetEpisodesUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _Mode { ok, notDeployed, offline }

class _Remote implements FollowSyncRemoteDataSource {
  _Mode mode = _Mode.ok;
  final calls = <String>[];
  List<FollowedTitle> server = [];
  List<FollowedTitle>? lastSyncItems;
  List<({String provider, String contentUrl, int at})>? lastDeleted;
  Completer<void>? hold;

  void _gate() {
    switch (mode) {
      case _Mode.notDeployed:
        throw const FollowsNotDeployed();
      case _Mode.offline:
        throw DioException(
          requestOptions: RequestOptions(path: '/follows'),
          type: DioExceptionType.connectionError,
        );
      case _Mode.ok:
        return;
    }
  }

  @override
  Future<FollowedTitle?> add(FollowedTitle title) async {
    calls.add('add ${title.contentUrl}');
    await hold?.future;
    _gate();
    return title;
  }

  @override
  Future<void> remove(String provider, String contentUrl) async {
    calls.add('remove $contentUrl');
    _gate();
  }

  @override
  Future<FollowedTitle?> patch(
    String provider,
    String contentUrl, {
    bool? notify,
    int? lastEpisodeCount,
  }) async {
    calls.add('patch $contentUrl notify=$notify count=$lastEpisodeCount');
    _gate();
    return null;
  }

  @override
  Future<List<FollowedTitle>> sync({
    required List<FollowedTitle> items,
    required List<({String provider, String contentUrl, int at})> deleted,
  }) async {
    calls.add('sync');
    await hold?.future;
    _gate();
    lastSyncItems = items;
    lastDeleted = deleted;
    return server;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FollowedTitle _title(String url, {int count = 0, String provider = 'cs:x'}) =>
    FollowedTitle(
      contentUrl: url,
      provider: provider,
      title: url.toUpperCase(),
      thumbnail: '',
      lastEpisodeCount: count,
      addedAt: 1,
    );

void main() {
  late Box box;
  late _Hive hive;
  late _Remote remote;
  late FollowService follows;
  late FollowSyncService sync;
  var signedIn = true;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_follow_sync');
    box = await Hive.openBox('sozo_follow_sync');
  });
  tearDownAll(() async => Hive.close());

  setUp(() async {
    ProfileScope.reset();
    await box.clear();
    signedIn = true;
    hive = _Hive();
    remote = _Remote();
    follows = FollowService(
      hive: hive,
      getEpisodes: _Episodes(),
      notifications: _Notifications(),
    );
    sync = FollowSyncService(
      remote: remote,
      follows: follows,
      isSignedIn: () => signedIn,
      box: box,
    );
    follows.sink = sync;
  });

  test('a guest never reaches the network', () async {
    signedIn = false;
    await follows.follow(_title('a'));
    await pumpEventQueue();
    expect(await sync.fullSync(force: true), isFalse);
    expect(remote.calls, isEmpty);
    expect(sync.pendingCount, 0);
  });

  test('a follow goes up and the server is then known to be there', () async {
    await follows.follow(_title('a'));
    await pumpEventQueue();
    expect(remote.calls, ['add a']);
    expect(sync.pendingCount, 0);
    expect(sync.serverLive, isTrue);
  });

  test('offline changes wait in the queue and go up later', () async {
    remote.mode = _Mode.offline;
    await follows.follow(_title('a'));
    await follows.setNotify('a', false);
    await pumpEventQueue();
    expect(sync.isPending(_title('a').key), isTrue);

    remote.mode = _Mode.ok;
    remote.calls.clear();
    expect(await sync.flush(), isTrue);
    // The mute folded into the queued follow: one add, sent as it stands now.
    expect(remote.calls, ['add a']);
    expect(sync.pendingCount, 0);
  });

  test(
    'a 404 means not deployed: local keeps working, nothing is lost',
    () async {
      remote.mode = _Mode.notDeployed;
      await follows.follow(_title('a'));
      await pumpEventQueue();
      expect(sync.serverLive, isFalse);
      expect(follows.list().single.contentUrl, 'a');
      expect(sync.pendingCount, 1);
      expect(await sync.fullSync(force: true), isFalse);
      expect(follows.list(), hasLength(1));
    },
  );

  test('an unfollow travels as a tombstone in the full sync', () async {
    remote.mode = _Mode.offline;
    await follows.follow(_title('a'));
    await follows.unfollow('a');
    await pumpEventQueue();
    remote.mode = _Mode.ok;
    expect(await sync.fullSync(force: true), isTrue);
    expect(remote.lastDeleted!.single.contentUrl, 'a');
    expect(sync.pendingCount, 0);
  });

  test('the merge keeps device-only fields and never lowers a count', () async {
    hive.raw = [
      _title(
        'a',
        count: 12,
      ).copyWith(autoDownload: true, autoDownloadFrom: 9).toJson(),
    ];
    remote.server = [
      _title('a', count: 10).copyWith(anilistId: 7),
      _title('b', count: 3),
    ];
    expect(await sync.fullSync(force: true), isTrue);
    final byUrl = {for (final t in follows.list()) t.contentUrl: t};
    expect(byUrl.keys, containsAll(['a', 'b']));
    expect(byUrl['a']!.lastEpisodeCount, 12);
    expect(byUrl['a']!.autoDownload, isTrue);
    expect(byUrl['a']!.autoDownloadFrom, 9);
    expect(byUrl['a']!.anilistId, 7);
  });

  test('startup syncs are throttled, sign-in ones are not', () async {
    expect(await sync.fullSync(force: true), isTrue);
    remote.calls.clear();
    await sync.fullSync();
    expect(remote.calls, isNot(contains('sync')));
    await sync.fullSync(force: true);
    expect(remote.calls, contains('sync'));
  });

  test(
    'an unfollow made while the follow is in flight still goes up',
    () async {
      remote.hold = Completer<void>();
      await follows.follow(_title('a'));
      await pumpEventQueue();
      expect(remote.calls, ['add a']);
      await follows.unfollow('a');
      await pumpEventQueue();
      remote.hold!.complete();
      remote.hold = null;
      // The queue drains through real storage I/O, not only microtasks, so a
      // fixed number of event-queue pumps passed locally and failed on a slower
      // CI runner. Wait for the outcome itself, with a ceiling.
      for (
        var i = 0;
        i < 200 && (remote.calls.length < 2 || sync.pendingCount > 0);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(remote.calls, ['add a', 'remove a']);
      expect(sync.pendingCount, 0);
    },
  );

  test(
    'a profile switch mid-sync keeps the old list out of the new profile',
    () async {
      hive.raw = [_title('mine').toJson()];
      remote.server = [_title('theirs')];
      remote.hold = Completer<void>();
      final first = sync.fullSync(force: true);
      await pumpEventQueue();
      ProfileScope.set(namespace: 'kid', remoteId: 'kid');
      remote.hold!.complete();
      remote.hold = null;
      remote.server = [_title('mine')];
      expect(await first, isFalse);
      expect(hive.raw.map((e) => e['contentUrl']), ['mine']);
      await pumpEventQueue();
      // The new profile gets a sync of its own instead of being skipped.
      expect(remote.calls.where((c) => c == 'sync'), hasLength(2));
      ProfileScope.reset();
    },
  );

  group('collapse', () {
    test('a delete wins over whatever was queued', () {
      expect(
        FollowSyncService.collapse({'op': 'upsert'}, {'op': 'delete'})['op'],
        'delete',
      );
    });

    test('patches merge, keeping both fields', () {
      final out = FollowSyncService.collapse(
        {'op': 'patch', 'notify': false},
        {'op': 'patch', 'lastEpisodeCount': 5},
      );
      expect(out['notify'], isFalse);
      expect(out['lastEpisodeCount'], 5);
    });

    test('a patch on a queued upsert is already in it', () {
      expect(
        FollowSyncService.collapse(
          {'op': 'upsert'},
          {'op': 'patch', 'notify': true},
        ),
        {'op': 'upsert'},
      );
    });
  });
}
