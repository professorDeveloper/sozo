import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/home/domain/usecase/home_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';

HomeDataEntity dataFor(String provider) => HomeDataEntity(
  provider: provider,
  banner: const [],
  sections: const [],
  categories: const [],
  genres: const [],
);

class _Repo implements HomeRepository {
  _Repo(this.provider);
  final String Function() provider;
  final List<Completer<Result<HomeDataEntity>>> calls = [];

  @override
  Future<Result<HomeDataEntity>> loadHome() {
    final c = Completer<Result<HomeDataEntity>>();
    calls.add(c);
    return c.future;
  }

  @override
  Future<Result<List<GenreEntity>>> loadGenres() async =>
      const Success(<GenreEntity>[]);

  @override
  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) => throw UnimplementedError();
}

void main() {
  var current = 'cs:watch-source';
  late _Repo repo;
  late HomeBloc bloc;

  setUp(() {
    current = 'cs:watch-source';
    repo = _Repo(() => current);
    bloc = HomeBloc(useCase: HomeUseCase(repo), currentProvider: () => current);
  });

  tearDown(() => bloc.close());

  Future<void> loadAndAnswer(String provider) async {
    current = provider;
    bloc.add(HomeLoad(silent: true));
    await pumpEventQueue();
    repo.calls.last.complete(Success(dataFor(provider)));
    await pumpEventQueue();
  }

  test('coming back to a source shows its Home at once, no skeleton', () async {
    await loadAndAnswer('cs:watch-source');
    await loadAndAnswer('mn:manga-source');

    final seen = <HomeState>[];
    final sub = bloc.stream.listen(seen.add);
    current = 'cs:watch-source';
    bloc.add(HomeLoad(silent: true));
    await pumpEventQueue();

    expect(seen, isNotEmpty);
    expect(seen.first, isA<HomeLoaded>());
    expect((seen.first as HomeLoaded).homeData.provider, 'cs:watch-source');
    expect(seen.whereType<HomeLoading>(), isEmpty);

    // And it still refreshes underneath.
    expect(repo.calls, hasLength(3));
    await sub.cancel();
  });

  test(
    'a failed refresh keeps the restored Home instead of an error',
    () async {
      await loadAndAnswer('cs:watch-source');
      await loadAndAnswer('mn:manga-source');

      current = 'cs:watch-source';
      bloc.add(HomeLoad(silent: true));
      await pumpEventQueue();
      repo.calls.last.complete(Failure(Exception('offline')));
      await pumpEventQueue();

      expect(bloc.state, isA<HomeLoaded>());
      expect((bloc.state as HomeLoaded).homeData.provider, 'cs:watch-source');
    },
  );

  test('a source never shown still loads the ordinary way', () async {
    final seen = <HomeState>[];
    final sub = bloc.stream.listen(seen.add);
    bloc.add(HomeLoad());
    await pumpEventQueue();
    expect(seen.first, isA<HomeLoading>());
    await sub.cancel();
  });
}
