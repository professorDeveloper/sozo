import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/repositories/detail_repository_impl.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/repositories/home_repository_imp.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';

import 'jellyfin_fakes.dart';

class _Hive implements HiveService {
  @override
  String getCurrentProvider() => 'jf:srv1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mangayomi implements MangayomiBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails the test if anything reaches the Sozo backend.
Dio _noBackend() => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, _) => fail('jf: must not call the backend: ${o.path}'),
    ),
  );

void main() {
  late FakeJellyfinAdapter adapter;
  late JellyfinBridge bridge;

  setUp(() async {
    adapter = FakeJellyfinAdapter({
      '/Items': (_) => {'Items': [], 'TotalRecordCount': 0},
      '/Items/m1': (_) => {
        'Id': 'm1',
        'Name': 'Big Buck Bunny',
        'Type': 'Movie',
      },
      '/Items/m1/Similar': (_) => {'Items': []},
      '/Items/m1/PlaybackInfo': (_) => {
        'PlaySessionId': 'ps',
        'MediaSources': [
          {'Id': 'm1', 'Container': 'mp4', 'SupportsDirectPlay': true},
        ],
      },
    });
    bridge = JellyfinBridge(
      api: fakeApi(adapter),
      store: await storeWith([testServer]),
      label: (k) => k,
    );
  });

  test('a Home genre tile pages that genre on the server', () async {
    final repo = HomeRepositoryImp(
      HomeDataSource(dio: _noBackend()),
      hive: _Hive(),
      mangayomi: _Mangayomi(),
      jellyfin: bridge,
    );
    final result = await repo.loadViewAll(key: 'genre', slug: 'g42', page: 2);
    expect(result.isSuccess, isTrue);
    final q = adapter.requests.single.uri.queryParameters;
    expect(q['GenreIds'], 'g42');
    expect(q['StartIndex'], '${JellyfinBridge.pageSize}');
  });

  test('detail, episodes and media resolve on the device', () async {
    final repo = DetailRepositoryImpl(
      DetailDataSource(dio: _noBackend()),
      hive: _Hive(),
      mangayomi: _Mangayomi(),
      jellyfin: bridge,
    );
    final detail = await repo.getDetail('m1');
    expect((detail as Success).value.title, 'Big Buck Bunny');
    final episodes = await repo.getEpisodes('m1');
    expect((episodes as Success).value.episodes.single.mediaRef, 'm1');
    final media = await repo.resolveMedia(ref: 'm1', provider: 'jf:srv1');
    expect(
      (media as Success).value.videoSources.first.videoUrl,
      contains('/Videos/m1/stream.mp4'),
    );
  });
}
