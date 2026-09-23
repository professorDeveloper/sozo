// A country TMDB has never heard of used to be an empty screen.
//
// TMDB publishes streaming line-ups for 139 countries. Uzbekistan is not one of
// them, and neither is Kazakhstan — so a viewer in either opened Streaming
// services and found a blank grid with no explanation, which reads as the
// feature being broken rather than as their country not being covered.
//
// There is no country picker any more: the country is the device's, and where
// that has nothing the screen shows the US line-up and says so.
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/repositories/watch_services_repository.dart';
import 'package:soplay/features/watch_services/domain/usecase/watch_services_usecase.dart';
import 'package:soplay/features/watch_services/presentation/bloc/watch_services/watch_services_bloc.dart';

/// Only the countries TMDB actually lists have anything.
class _Repo implements WatchServicesRepository {
  _Repo([this.lists = const {'US': 3, 'GB': 2}]);

  /// What TMDB publishes: a line-up for some countries and nothing for the
  /// rest. Uzbekistan and Kazakhstan are real examples of the rest.
  final Map<String, int> lists;

  final asked = <String>[];

  @override
  Future<Result<List<WatchServiceEntity>>> loadServices({
    required String region,
  }) async {
    asked.add(region);
    return Success([
      for (var i = 0; i < (lists[region] ?? 0); i++)
        WatchServiceEntity(
          id: i,
          name: '$region service $i',
          slug: '$region-$i',
          logo: '',
          priority: i,
        ),
    ]);
  }
}

void main() {
  final getIt = GetIt.instance;

  // Awaited: `reset` is asynchronous, and an un-awaited one lands AFTER the
  // registration below and quietly wipes it.
  setUp(() async {
    await getIt.reset();
    // The bloc records the fallback. Suppressed, so nothing is sent and the
    // call is still exercised.
    getIt.registerSingleton<Analytics>(Analytics(suppressed: () => true));
  });

  tearDown(() async => getIt.reset());

  WatchServicesBloc blocFor(_Repo repo, {String device = 'UZ'}) =>
      WatchServicesBloc(
        useCase: WatchServicesUseCase(repo),
        deviceCountry: () => device,
      );

  Future<WatchServicesState> settle(WatchServicesBloc bloc) => bloc.stream
      .firstWhere(
        (s) =>
            s.status == WatchServicesStatus.loaded ||
            s.status == WatchServicesStatus.error,
      )
      .timeout(const Duration(seconds: 5));

  test('a country with no line-up falls back, and says so', () async {
    final repo = _Repo();
    final bloc = blocFor(repo);
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await settle(bloc);

    expect(repo.asked, [
      'UZ',
      'US',
    ], reason: 'the device first, then the stand-in');
    expect(state.region, 'US');
    expect(state.fellBackFrom, 'UZ');
    expect(state.services, hasLength(3));
  });

  test('a country that has services is left alone', () async {
    final repo = _Repo();
    final bloc = blocFor(repo, device: 'GB');
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await settle(bloc);

    expect(state.region, 'GB');
    expect(state.fellBackFrom, '');
    expect(state.services, hasLength(2));
    expect(repo.asked, ['GB']);
  });

  test('a device with no country goes straight to the stand-in', () async {
    // An emulator, or a locale set to a bare language: there is no country to
    // ask about, and asking TMDB for "" is a 400, not an empty list.
    final repo = _Repo();
    final bloc = blocFor(repo, device: '');
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await settle(bloc);

    expect(repo.asked, ['US']);
    expect(state.fellBackFrom, '', reason: 'nothing was asked for and missed');
  });

  test('the stand-in being empty too is the end of it, not a loop', () async {
    final repo = _Repo(const {});
    final bloc = blocFor(repo);
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await settle(bloc);

    expect(repo.asked, ['UZ', 'US']);
    expect(state.services, isEmpty);
  });
}
