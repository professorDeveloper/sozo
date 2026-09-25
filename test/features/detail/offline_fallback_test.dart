import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/presentation/blocs/detail_bloc/detail_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/episodes_bloc/episodes_bloc.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';

import '../download/offline_fakes.dart';

const _url = 'https://old.test/show';

class _Source implements DetailRepository {
  _Source({this.up = true});

  bool up;
  int calls = 0;

  @override
  Future<Result<DetailEntity>> getDetail(
    String contentUrl, {
    String? provider,
  }) async {
    calls++;
    if (!up) return Failure(Exception('SocketException: host unreachable'));
    return Success(
      DetailEntity(
        provider: 'old',
        contentId: '1',
        contentUrl: contentUrl,
        title: 'Live title',
        description: 'From the source',
        thumbnail: null,
        year: null,
        duration: null,
        country: null,
        director: null,
        genres: const [],
        cast: const [],
        likes: 0,
        dislikes: 0,
        isSerial: true,
        isFavorited: null,
        screenshots: const [],
        related: const [],
      ),
    );
  }

  @override
  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async {
    calls++;
    if (!up) return Failure(Exception('SocketException: host unreachable'));
    return Success(
      PlaybackEntity(
        provider: 'old',
        contentUrl: contentUrl,
        isSerial: true,
        episodes: const [EpisodeEntity(episode: 1, label: '1', mediaRef: 'a')],
        videoSources: const [],
        playerSrc: null,
        headers: const {},
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MemoryTitles _saved() => MemoryTitles()
  ..saved[_url] = const OfflineTitle(
    contentUrl: _url,
    provider: 'old',
    title: 'Saved title',
    description: 'Saved words',
    isSerial: true,
    savedAt: 1,
    episodes: [
      EpisodeEntity(episode: 1, label: 'One', mediaRef: 'r1'),
      EpisodeEntity(episode: 2, label: 'Two', mediaRef: 'r2'),
    ],
  );

Future<S> _settle<S>(Stream<Object?> stream) async =>
    await stream.firstWhere((s) => s is S) as S;

void main() {
  group('the title page', () {
    test('falls back to the saved copy when the source fails', () async {
      final source = _Source(up: false);
      final bloc = DetailBloc(
        useCase: GetDetailUseCase(source),
        offline: _saved(),
      )..add(const DetailLoad(_url, provider: 'old'));

      final state = await _settle<DetailLoaded>(bloc.stream);
      expect(state.offline, isTrue);
      expect(state.detail.title, 'Saved title');
      expect(state.detail.description, 'Saved words');
      await bloc.close();
    });

    test('skips the request altogether with no network', () async {
      final source = _Source();
      final bloc = DetailBloc(
        useCase: GetDetailUseCase(source),
        offline: _saved(),
        isOffline: () async => true,
      )..add(const DetailLoad(_url, provider: 'old'));

      final state = await _settle<DetailLoaded>(bloc.stream);
      expect(state.offline, isTrue);
      expect(source.calls, 0);
      await bloc.close();
    });

    test('online, the source wins and the copy is refreshed', () async {
      final titles = _saved();
      final bloc = DetailBloc(
        useCase: GetDetailUseCase(_Source()),
        offline: titles,
        isOffline: () async => false,
      )..add(const DetailLoad(_url, provider: 'old'));

      final state = await _settle<DetailLoaded>(bloc.stream);
      expect(state.offline, isFalse);
      expect(state.detail.title, 'Live title');
      await bloc.close();
      expect(titles.notedDetails.single.title, 'Live title');
    });

    test('with no saved copy a failure is still an error', () async {
      final bloc = DetailBloc(
        useCase: GetDetailUseCase(_Source(up: false)),
        offline: MemoryTitles(),
      )..add(const DetailLoad(_url, provider: 'old'));

      final state = await _settle<DetailError>(bloc.stream);
      expect(state.message, contains('host unreachable'));
      await bloc.close();
    });
  });

  group('the episode list', () {
    test('falls back to the saved list', () async {
      final bloc = EpisodesBloc(
        useCase: GetEpisodesUseCase(_Source(up: false)),
        offline: _saved(),
      )..add(const EpisodesLoad(_url, provider: 'old'));

      final state = await _settle<EpisodesLoaded>(bloc.stream);
      expect(state.offline, isTrue);
      expect(state.playback.episodes, hasLength(2));
      expect(state.playback.totalPages, 1);
      await bloc.close();
    });

    test('offline, it never asks the source', () async {
      final source = _Source();
      final bloc = EpisodesBloc(
        useCase: GetEpisodesUseCase(source),
        offline: _saved(),
        isOffline: () async => true,
      )..add(const EpisodesLoad(_url, provider: 'old'));

      await _settle<EpisodesLoaded>(bloc.stream);
      expect(source.calls, 0);
      await bloc.close();
    });

    test('online, the fresh list is kept for next time', () async {
      final titles = _saved();
      final bloc = EpisodesBloc(
        useCase: GetEpisodesUseCase(_Source()),
        offline: titles,
      )..add(const EpisodesLoad(_url, provider: 'old'));

      final state = await _settle<EpisodesLoaded>(bloc.stream);
      expect(state.offline, isFalse);
      await bloc.close();
      expect(titles.notedEpisodes, hasLength(1));
    });
  });
}
