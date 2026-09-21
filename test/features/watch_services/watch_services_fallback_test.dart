// A country TMDB has never heard of used to be an empty screen.
//
// TMDB publishes streaming line-ups for 139 countries. Uzbekistan is not one of
// them, and neither is Kazakhstan — so a viewer in either opened Streaming
// services and found a blank grid with no explanation, which reads as the
// feature being broken rather than as their country not being covered.
//
// The region list would have said so, but it is only fetched when the picker is
// opened, so the first thing in the app that knows is the empty answer itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/repositories/watch_services_repository.dart';
import 'package:soplay/features/watch_services/domain/usecase/watch_services_usecase.dart';
import 'package:soplay/features/watch_services/presentation/bloc/watch_services/watch_services_bloc.dart';

/// Only the countries TMDB actually lists have anything.
class _Repo implements WatchServicesRepository {
  /// What TMDB publishes: a line-up for some countries and nothing for the
  /// rest. Uzbekistan and Kazakhstan are real examples of the rest.
  static const Map<String, int> lists = {'US': 3, 'GB': 2};

  final asked = <String>[];
  var regionsAsked = 0;

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

  @override
  Future<Result<List<WatchRegionEntity>>> loadRegions() async {
    regionsAsked++;
    return const Success([
      WatchRegionEntity(code: 'US', name: 'United States'),
      WatchRegionEntity(code: 'GB', name: 'United Kingdom'),
    ]);
  }
}

/// The stored region, without opening Hive.
class _Hive implements HiveService {
  _Hive([this._region = '']);

  String _region;

  @override
  String getWatchRegion() => _region;

  @override
  Future<void> setWatchRegion(String code) async =>
      _region = code.toUpperCase();

  @override
  dynamic noSuchMethod(Invocation i) => null;
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

  /// Uzbekistan, which is exactly the case this is about: a real country that
  /// TMDB does not publish a line-up for.
  WatchServicesBloc blocFor(_Repo repo, _Hive hive, {String device = 'UZ'}) =>
      WatchServicesBloc(
        useCase: WatchServicesUseCase(repo),
        hive: hive,
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
    final bloc = blocFor(repo, _Hive());
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    // The first answer is the fallback's, because the empty one is not an
    // answer anybody can use.
    final state = await bloc.stream
        .firstWhere(
          (s) => s.status == WatchServicesStatus.loaded && s.hasServices,
        )
        .timeout(const Duration(seconds: 5));

    expect(repo.asked, [
      'UZ',
      'US',
    ], reason: 'the device first, then the stand-in');
    expect(state.region, 'US');
    expect(state.fellBackFrom, 'UZ');
    expect(state.services, hasLength(3));
    // And the real country list is fetched, so the picker and the resolver are
    // right from here on rather than repeating this every open.
    expect(repo.regionsAsked, 1);
  });

  test('a country somebody CHOSE is left empty, not overridden', () async {
    // An empty answer to a question somebody asked is an answer. Substituting
    // a different country would be the app overruling a choice it was given.
    final repo = _Repo();
    final bloc = blocFor(repo, _Hive('FR'));
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await settle(bloc);

    expect(state.region, 'FR');
    expect(state.services, isEmpty);
    expect(state.fellBackFrom, '');
    expect(repo.asked, ['FR'], reason: 'it must not go looking elsewhere');
  });

  test('and a region picked by hand is honoured even when empty', () async {
    final repo = _Repo();
    final bloc = blocFor(repo, _Hive());
    addTearDown(bloc.close);

    bloc.add(const WatchServicesRegionChanged('DE'));
    final state = await settle(bloc);

    expect(state.region, 'DE');
    expect(state.services, isEmpty);
    expect(state.fellBackFrom, '');
  });

  test('a country that has services is left alone', () async {
    final repo = _Repo();
    final bloc = blocFor(repo, _Hive('GB'));
    addTearDown(bloc.close);

    bloc.add(const WatchServicesLoad());
    final state = await settle(bloc);

    expect(state.region, 'GB');
    expect(state.fellBackFrom, '');
    expect(state.services, hasLength(2));
    expect(repo.regionsAsked, 0, reason: 'nothing needed correcting');
  });
}
