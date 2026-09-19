// Two Home loads in flight at once must land on the newer one's rows.
//
// Eleven places add HomeLoad — the page mounting, the shell seeing its first
// provider, a source change from anywhere in the app, two pull-to-refreshes, two
// Retry buttons, two Cloudflare solves — and bloc's default transformer runs
// them concurrently. So whichever backend answered LAST is what got emitted,
// which is not the same thing as whichever source the viewer picked last.
// Switching source twice quickly landed on the first source's rows, and a Retry
// that arrived while a refresh was still out repainted the error it had just
// cleared.
//
// Only one place can fix that: the bloc where all eleven meet.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
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

/// Every load parks on a completer the test controls, so two can be in flight.
class _ScriptedRepo implements HomeRepository {
  _ScriptedRepo();

  final List<Completer<Result<HomeDataEntity>>> homeCalls = [];
  final List<Completer<Result<List<GenreEntity>>>> genreCalls = [];

  @override
  Future<Result<HomeDataEntity>> loadHome() {
    final c = Completer<Result<HomeDataEntity>>();
    homeCalls.add(c);
    return c.future;
  }

  @override
  Future<Result<List<GenreEntity>>> loadGenres() {
    final c = Completer<Result<List<GenreEntity>>>();
    genreCalls.add(c);
    return c.future;
  }

  @override
  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) => throw UnimplementedError();
}

void main() {
  late _ScriptedRepo repo;
  late HomeBloc bloc;

  setUp(() {
    repo = _ScriptedRepo();
    bloc = HomeBloc(useCase: HomeUseCase(repo));
  });

  tearDown(() => bloc.close());

  test('the slower first load cannot overwrite the newer one', () async {
    final seen = <HomeState>[];
    final sub = bloc.stream.listen(seen.add);

    bloc.add(HomeLoad());
    await pumpEventQueue();
    bloc.add(HomeLoad(silent: true));
    await pumpEventQueue();
    expect(repo.homeCalls.length, 2, reason: 'both loads should be in flight');

    // The newer one answers first, the older one afterwards — the ordinary case
    // when the second source is faster or the first request is retrying.
    repo.homeCalls[1].complete(Success(dataFor('second')));
    await pumpEventQueue();
    repo.genreCalls.last.complete(const Success(<GenreEntity>[]));
    await pumpEventQueue();
    repo.homeCalls[0].complete(Success(dataFor('first')));
    await pumpEventQueue();

    final loaded = seen.whereType<HomeLoaded>().toList();
    expect(loaded, hasLength(1));
    expect(loaded.single.homeData.provider, 'second');
    await sub.cancel();
  });

  test('a stale failure cannot repaint an error over the newer rows', () async {
    final seen = <HomeState>[];
    final sub = bloc.stream.listen(seen.add);

    bloc.add(HomeLoad());
    await pumpEventQueue();
    bloc.add(HomeLoad());
    await pumpEventQueue();

    repo.homeCalls[1].complete(Success(dataFor('second')));
    await pumpEventQueue();
    repo.genreCalls.last.complete(const Success(<GenreEntity>[]));
    await pumpEventQueue();
    // The abandoned load times out. Before the token this emitted HomeError
    // over rows that were already on screen.
    repo.homeCalls[0].complete(Failure(Exception('timeout')));
    await pumpEventQueue();

    expect(seen.whereType<HomeError>(), isEmpty);
    expect(seen.last, isA<HomeLoaded>());
    await sub.cancel();
  });

  test('a stale genres answer cannot emit either', () async {
    // The genres round-trip is a second window for a newer load to start, and
    // the emit that follows it carries the OLD provider's rows.
    final seen = <HomeState>[];
    final sub = bloc.stream.listen(seen.add);

    bloc.add(HomeLoad());
    await pumpEventQueue();
    repo.homeCalls[0].complete(Success(dataFor('first')));
    await pumpEventQueue();
    expect(repo.genreCalls, hasLength(1), reason: 'genres should be pending');

    bloc.add(HomeLoad(silent: true));
    await pumpEventQueue();
    repo.homeCalls[1].complete(Success(dataFor('second')));
    await pumpEventQueue();
    // First load's genres land last.
    repo.genreCalls[0].complete(const Success(<GenreEntity>[]));
    await pumpEventQueue();
    repo.genreCalls[1].complete(const Success(<GenreEntity>[]));
    await pumpEventQueue();

    final loaded = seen.whereType<HomeLoaded>().toList();
    expect(loaded.map((s) => s.homeData.provider), ['second']);
    await sub.cancel();
  });

  test('one load on its own still emits', () async {
    // The guard must not be a way of emitting nothing at all.
    final seen = <HomeState>[];
    final sub = bloc.stream.listen(seen.add);

    bloc.add(HomeLoad());
    await pumpEventQueue();
    repo.homeCalls[0].complete(Success(dataFor('only')));
    await pumpEventQueue();
    repo.genreCalls[0].complete(const Success(<GenreEntity>[]));
    await pumpEventQueue();

    expect(seen.whereType<HomeLoaded>(), hasLength(1));
    await sub.cancel();
  });
}
