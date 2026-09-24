import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
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
  int highest = 12;

  @override
  Future<Result<PlaybackEntity>> call(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async => Success(
    PlaybackEntity(
      provider: 'p1',
      contentUrl: contentUrl,
      isSerial: true,
      episodes: [
        for (var n = 1; n <= highest; n++)
          EpisodeEntity(episode: n, label: '$n', mediaRef: 'r$n'),
      ],
      videoSources: const [],
      playerSrc: '',
      headers: const {},
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Hive hive;
  late _Episodes episodes;
  late FollowService follow;

  setUp(() {
    hive = _Hive();
    episodes = _Episodes();
    follow = FollowService(
      hive: hive,
      getEpisodes: episodes,
      notifications: _Notifications(),
    );
  });

  Future<void> addTitle({int last = 0}) => follow.follow(
    FollowedTitle(
      contentUrl: 'u',
      provider: 'p1',
      title: 'T',
      thumbnail: '',
      lastEpisodeCount: last,
    ),
  );

  test('the auto-download flag round-trips and is absent when off', () {
    const t = FollowedTitle(
      contentUrl: 'u',
      provider: 'p',
      title: 't',
      thumbnail: '',
    );
    expect(t.toJson().containsKey('autoDownload'), isFalse);
    final on = FollowedTitle.fromJson(
      t.copyWith(autoDownload: true, autoDownloadFrom: 7).toJson(),
    );
    expect(on.autoDownload, isTrue);
    expect(on.autoDownloadFrom, 7);
  });

  test('turning it on floors at the count already known', () async {
    await addTitle(last: 10);
    await follow.setAutoDownload('u', true);
    expect(follow.list().single.autoDownloadFrom, 10);
    await follow.setAutoDownload('u', false);
    expect(follow.list().single.autoDownload, isFalse);
    expect(follow.list().single.autoDownloadFrom, 0);
  });

  test(
    'a title enabled before its first check is floored by the check',
    () async {
      await addTitle();
      await follow.setAutoDownload('u', true);
      final seen = <FollowedTitle>[];
      await follow.checkForUpdates(
        notify: false,
        onChecked: (t, _) => seen.add(t),
      );
      expect(seen.single.autoDownloadFrom, 12);
      expect(follow.list().single.autoDownloadFrom, 12);
    },
  );

  test('every answering title reaches onChecked with its episodes', () async {
    await addTitle(last: 10);
    await follow.setAutoDownload('u', true);
    episodes.highest = 14;
    List<EpisodeEntity>? got;
    final grown = await follow.checkForUpdates(
      notify: false,
      onChecked: (_, eps) => got = eps,
    );
    expect(grown, 1);
    expect(got!.length, 14);
    expect(follow.list().single.autoDownloadFrom, 10, reason: 'floor kept');
  });
}
