// The page has to ask for its own data.
//
// The bloc is a singleton so that one answer serves Home and the page without
// being fetched twice, and the load used to be started by the Home rail. That
// rail came off Home — so the page was left waiting on a load nobody had
// started, and showed its skeleton for as long as it was open. Reusing an
// answer somebody else fetched is not the same as relying on them to fetch it.
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/repositories/watch_services_repository.dart';
import 'package:soplay/features/watch_services/domain/usecase/watch_services_usecase.dart';
import 'package:soplay/features/watch_services/presentation/bloc/watch_services/watch_services_bloc.dart';

class _Repo implements WatchServicesRepository {
  var calls = 0;

  @override
  Future<Result<List<WatchServiceEntity>>> loadServices({
    required String region,
  }) async {
    calls++;
    return const Success([
      WatchServiceEntity(
        id: 8,
        name: 'Netflix',
        slug: 'netflix',
        logo: 'https://example.test/n.jpg',
        priority: 0,
      ),
    ]);
  }
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<Analytics>(Analytics(suppressed: () => true));
  });

  tearDown(() async => getIt.reset());

  test('an untouched bloc is still on its initial state', () {
    // The premise. If this ever stops being true the page's guard below is
    // doing nothing and the skeleton bug can come back unnoticed.
    final bloc = WatchServicesBloc(useCase: WatchServicesUseCase(_Repo()));
    addTearDown(bloc.close);
    expect(bloc.state.status, WatchServicesStatus.initial);
    expect(bloc.state.hasServices, isFalse);
  });

  test('and a load fills it', () async {
    final repo = _Repo();
    final bloc = WatchServicesBloc(
      useCase: WatchServicesUseCase(repo),
      deviceCountry: () => 'US',
    );
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await bloc.stream
        .firstWhere((s) => s.status == WatchServicesStatus.loaded)
        .timeout(const Duration(seconds: 5));

    expect(state.services.single.name, 'Netflix');
    expect(repo.calls, 1);
  });

  test('a second load on a filled bloc does not refetch', () async {
    // Which is the whole reason it is a singleton: Home and the page both ask,
    // and the country's line-up is not a thing that changes while the app is
    // open.
    final repo = _Repo();
    final bloc = WatchServicesBloc(
      useCase: WatchServicesUseCase(repo),
      deviceCountry: () => 'US',
    );
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    await bloc.stream
        .firstWhere((s) => s.status == WatchServicesStatus.loaded)
        .timeout(const Duration(seconds: 5));
    expect(repo.calls, 1);

    // What both callers do: ask only when there is nothing there.
    if (bloc.state.status == WatchServicesStatus.initial) {
      bloc.add(const WatchServicesLoad());
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.calls, 1);
  });
}
