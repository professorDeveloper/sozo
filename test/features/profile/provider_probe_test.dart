import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/services/provider_probe.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

void main() {
  group('ProviderProbe', () {
    test('a source that answers all the way through is playable', () async {
      final probe = _probe(
        search: _found(['One Piece']),
        playback: _serial(),
        resolve: _resolved('https://cdn.example/ep1.m3u8'),
        status: 206,
      );

      final r = await probe.run(_provider());

      expect(r.playable, isTrue);
      expect(
        r.steps.map((s) => s.outcome),
        everyElement(ProbeOutcome.ok),
      );
      expect(r.stepFor(ProbeStage.playback)!.detail, 'HTTP 206');
    });

    test('a catalogue that answers with nothing is not called broken', () async {
      // The one result that would make this worse than no tool. A film site has
      // never heard of "one piece" and is perfectly healthy.
      final probe = _probe(
        search: (_) => _result(const [], ProviderSearchStatus.empty),
        playback: _serial(),
        resolve: _resolved('https://cdn.example/ep1.m3u8'),
        status: 206,
      );

      final r = await probe.run(_provider());

      final cat = r.stepFor(ProbeStage.catalogue)!;
      expect(cat.outcome, ProbeOutcome.empty);
      expect(cat.outcome, isNot(ProbeOutcome.failed));
      expect(r.playable, isFalse);
    });

    test('the second term is tried only when the first found nothing', () async {
      final asked = <String>[];
      final probe = _probe(
        search: (q) {
          asked.add(q);
          return _result(
            q == 'naruto' ? [_movie('Naruto')] : const [],
            q == 'naruto' ? ProviderSearchStatus.ok : ProviderSearchStatus.empty,
          );
        },
        playback: _serial(),
        resolve: _resolved('https://cdn.example/ep1.m3u8'),
        status: 200,
      );

      final r = await probe.run(_provider(category: 'anime'));

      expect(asked, ['one piece', 'naruto']);
      expect(
        r.query,
        'naruto',
        reason: 'the term that worked is the one reported',
      );
      expect(r.stepFor(ProbeStage.catalogue)!.outcome, ProbeOutcome.ok);
    });

    test('a search that times out is a failure, and stops the run', () async {
      final probe = _probe(
        search: (_) => _result(const [], ProviderSearchStatus.timeout),
        playback: _serial(),
        resolve: _resolved('https://cdn.example/ep1.m3u8'),
        status: 206,
      );

      final r = await probe.run(_provider());

      expect(r.stepFor(ProbeStage.catalogue)!.outcome, ProbeOutcome.failed);
      expect(r.stepFor(ProbeStage.catalogue)!.detail, 'timed out');
      expect(r.stepFor(ProbeStage.stream)!.outcome, ProbeOutcome.skipped);
    });

    test('every stage appears in every result', () async {
      // So two sources are compared by reading the same four rows, rather than
      // by counting how many rows each one has.
      final probe = _probe(
        search: (_) => _result(const [], ProviderSearchStatus.error),
        playback: _serial(),
        resolve: _resolved('https://x/a.m3u8'),
        status: 200,
      );

      final r = await probe.run(_provider());

      expect(r.steps.map((s) => s.stage), ProbeStage.values);
    });

    test('a link that 403s fails at playback, not before', () async {
      // The case the whole thing exists for: catalogue and detail are fine and
      // the CDN still refuses this client. Reported as three greens and a red,
      // because that is a different problem from a dead source.
      final probe = _probe(
        search: _found(['One Piece']),
        playback: _serial(),
        resolve: _resolved('https://cdn.example/ep1.m3u8'),
        status: 403,
      );

      final r = await probe.run(_provider());

      expect(r.stepFor(ProbeStage.catalogue)!.isOk, isTrue);
      expect(r.stepFor(ProbeStage.detail)!.isOk, isTrue);
      expect(r.stepFor(ProbeStage.stream)!.isOk, isTrue);
      expect(r.stepFor(ProbeStage.playback)!.outcome, ProbeOutcome.failed);
      expect(r.stepFor(ProbeStage.playback)!.detail, 'HTTP 403');
      expect(r.verdict.stage, ProbeStage.playback);
    });

    test('a CDN that ignores the range header still counts as reachable',
        () async {
      // Plenty answer a ranged GET with a plain 200 and the whole file. That
      // proves it serves this client, which is the question being asked.
      final probe = _probe(
        search: _found(['One Piece']),
        playback: _serial(),
        resolve: _resolved('https://cdn.example/ep1.m3u8'),
        status: 200,
      );

      final r = await probe.run(_provider());

      expect(r.playable, isTrue);
      expect(r.stepFor(ProbeStage.playback)!.detail, 'HTTP 200');
    });

    test('a film resolves from its own sources, without an episode', () async {
      var resolveCalled = false;
      final probe = _probe(
        search: _found(['Dune']),
        playback: (_) => Success(_film('https://cdn.example/dune.mp4')),
        resolve: (_) {
          resolveCalled = true;
          return Failure(Exception('should not be called'));
        },
        status: 206,
      );

      final r = await probe.run(_provider(category: 'movies'));

      expect(
        resolveCalled,
        isFalse,
        reason: 'a film has no episode ref to resolve',
      );
      expect(r.playable, isTrue);
    });

    test('detail that opens with nothing to play is empty, not failed',
        () async {
      final probe = _probe(
        search: _found(['Ghost']),
        playback: (_) => Success(_empty()),
        resolve: _resolved('https://x/a.m3u8'),
        status: 206,
      );

      final r = await probe.run(_provider());

      expect(r.stepFor(ProbeStage.detail)!.outcome, ProbeOutcome.empty);
      expect(r.stepFor(ProbeStage.playback)!.outcome, ProbeOutcome.skipped);
    });

    test('an episode with no media ref cannot resolve to a stream', () async {
      final probe = _probe(
        search: _found(['One Piece']),
        playback: (_) => Success(_serialWithRef('')),
        resolve: _resolved('https://x/a.m3u8'),
        status: 206,
      );

      final r = await probe.run(_provider());

      expect(r.stepFor(ProbeStage.stream)!.outcome, ProbeOutcome.failed);
    });

    test('the verdict is the first thing that went wrong', () async {
      final probe = _probe(
        search: _found(['One Piece']),
        playback: (_) => Failure(Exception('504')),
        resolve: _resolved('https://x/a.m3u8'),
        status: 206,
      );

      final r = await probe.run(_provider());

      expect(r.verdict.stage, ProbeStage.detail);
      expect(r.verdict.outcome, ProbeOutcome.failed);
    });

    test('probe terms differ for anime and for everything else', () {
      expect(ProviderProbe.termsFor('anime').first, 'one piece');
      expect(
        ProviderProbe.termsFor('movies'),
        ProviderProbe.fallbackTerms,
        reason: 'an unlisted category falls back rather than having no terms',
      );
    });

    test('the stream step names the host, which is what identifies a CDN', () {
      expect(ProviderProbe.hostOf('https://cdn.example/a/b.m3u8'), 'cdn.example');
      expect(ProviderProbe.hostOf('not a url'), 'link');
    });
  });
}

// --- harness ---------------------------------------------------------------

typedef _SearchFn = ProviderSearchResult Function(String query);
typedef _PlaybackFn = Result<PlaybackEntity> Function(String url);
typedef _ResolveFn = Result<MediaResolveEntity> Function(String ref);

ProviderProbe _probe({
  required _SearchFn search,
  required _PlaybackFn playback,
  required _ResolveFn resolve,
  required int status,
}) {
  final dio = Dio()..httpClientAdapter = _StatusAdapter(status);
  return ProviderProbe(
    engine: _FakeEngine(search),
    episodes: GetEpisodesUseCase(_FakeRepo(playback: playback)),
    resolve: ResolveMediaUseCase(_FakeRepo(resolve: resolve)),
    dio: dio,
  );
}

_SearchFn _found(List<String> titles) =>
    (_) => _result(titles.map(_movie).toList(), ProviderSearchStatus.ok);

_PlaybackFn _serial() => (_) => Success(_serialWithRef('ref-1'));

_ResolveFn _resolved(String url) => (_) => Success(
      MediaResolveEntity(videoUrl: url, headers: const {'Referer': 'https://x/'}),
    );

ProviderSearchResult _result(
  List<MovieEntity> items,
  ProviderSearchStatus status,
) =>
    ProviderSearchResult(
      provider: const ProviderRef(
        id: 'p',
        name: 'P',
        kind: ProviderKind.server,
      ),
      items: items,
      status: status,
    );

MovieEntity _movie(String title) => MovieEntity(
      externalId: title,
      title: title,
      description: '',
      slug: title,
      url: 'https://site/$title',
      provider: 'p',
      thumbnail: null,
      year: null,
      rating: null,
      qualities: null,
      category: 'anime',
    );

ProviderEntity _provider({String category = 'anime'}) => ProviderEntity(
      id: 'p',
      name: 'P',
      image: '',
      url: 'https://site',
      description: '',
      domains: const ['site'],
      category: category,
    );

PlaybackEntity _serialWithRef(String ref) => PlaybackEntity(
      provider: 'p',
      contentUrl: 'https://site/x',
      isSerial: true,
      episodes: [EpisodeEntity(episode: 1, label: 'E1', mediaRef: ref)],
      videoSources: const [],
      playerSrc: null,
      headers: const {},
    );

PlaybackEntity _film(String url) => PlaybackEntity(
      provider: 'p',
      contentUrl: 'https://site/x',
      isSerial: false,
      episodes: const [],
      videoSources: [
        VideoSourceEntity(
          quality: '1080p',
          videoUrl: url,
          isDefault: true,
          accessible: true,
        ),
      ],
      playerSrc: null,
      headers: const {},
    );

PlaybackEntity _empty() => const PlaybackEntity(
      provider: 'p',
      contentUrl: 'https://site/x',
      isSerial: false,
      episodes: [],
      videoSources: [],
      playerSrc: null,
      headers: {},
    );

class _FakeEngine implements CrossSearchEngine {
  _FakeEngine(this._search);
  final _SearchFn _search;

  @override
  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int page = 1,
    int concurrency = CrossSearchEngine.defaultConcurrency,
    Duration perProviderTimeout = CrossSearchEngine.defaultTimeout,
  }) async* {
    yield _search(query);
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeRepo implements DetailRepository {
  _FakeRepo({this.playback, this.resolve});
  final _PlaybackFn? playback;
  final _ResolveFn? resolve;

  @override
  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async =>
      playback!(contentUrl);

  @override
  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async =>
      resolve!(ref);

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Answers every request with one status and an empty body.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(const [], status);

  @override
  void close({bool force = false}) {}
}
