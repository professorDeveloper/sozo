import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/usecase/watch_services_usecase.dart';
import 'package:soplay/features/watch_services/domain/watch_region.dart';

part 'watch_services_event.dart';
part 'watch_services_state.dart';

/// Which services a country has, held for the life of the app.
///
/// A singleton rather than a per-screen bloc, which is the opposite of how
/// every other bloc here is registered, and it is load-bearing: the Home feed
/// is torn down and rebuilt on every `HomeLoading -> HomeLoaded`, so a
/// per-screen instance would refetch this on every source switch and every
/// pull-to-refresh. What it holds is a fact about a country, not about the
/// current source, and it does not change when the source does.
///
/// Every handler carries a run token, for the same reason HomeBloc's does: the
/// region can change while a load is out, and the answer that lands last is not
/// necessarily the one that was asked for last.
class WatchServicesBloc extends Bloc<WatchServicesEvent, WatchServicesState> {
  WatchServicesBloc({
    required this.useCase,
    required this.hive,
    String Function()? deviceCountry,
  }) : _country = deviceCountry ?? _platformCountry,
       super(const WatchServicesState()) {
    on<WatchServicesLoad>(_onLoad);
    on<WatchServicesRegionChanged>(_onRegionChanged);
    on<WatchServicesRegionsRequested>(_onRegionsRequested);
  }

  final WatchServicesUseCase useCase;
  final HiveService hive;

  /// Where the viewer is, when they have not said.
  ///
  /// A seam rather than a direct read of [PlatformDispatcher], for the same
  /// reason the countdown takes its clock: the whole of the fallback behaviour
  /// depends on this value, and `PlatformDispatcher.instance` is a global a
  /// test cannot move — `localeTestValue` sets the binding's dispatcher, not
  /// the static one the app would otherwise read.
  final String Function() _country;

  int _runToken = 0;

  static String _platformCountry() =>
      PlatformDispatcher.instance.locale.countryCode ?? '';

  Future<void> _onLoad(
    WatchServicesLoad event,
    Emitter<WatchServicesState> emit,
  ) async {
    if (state.status == WatchServicesStatus.loading) return;
    // The stored region is resolved against nothing on the first load, because
    // the region list has not been fetched — `resolveRegion` treats an empty
    // list as "cannot contradict this", so a stored choice is honoured and the
    // device's country is used otherwise.
    final region = resolveRegion(
      hive.getWatchRegion(),
      state.regions,
      deviceCountry: _country(),
    );
    // Explicit when it came from storage: that is a country somebody picked,
    // and an empty answer to it is an answer, not a failure to find one.
    await _fetch(region, emit, explicit: hive.getWatchRegion().isNotEmpty);
  }

  Future<void> _onRegionChanged(
    WatchServicesRegionChanged event,
    Emitter<WatchServicesState> emit,
  ) async {
    final region = event.region.trim().toUpperCase();
    if (region.isEmpty) return;
    await hive.setWatchRegion(region);
    await _fetch(region, emit, explicit: true);
  }

  /// The country list, fetched the first time somebody opens the picker.
  ///
  /// Not on startup: it is ninety-odd rows that only the picker reads, and
  /// asking for them before anyone has looked is a request nobody needed.
  Future<void> _onRegionsRequested(
    WatchServicesRegionsRequested event,
    Emitter<WatchServicesState> emit,
  ) async {
    if (state.regions.isNotEmpty || state.loadingRegions) return;
    emit(state.copyWith(loadingRegions: true));
    final result = await useCase.callRegions();
    if (result case Success(:final value)) {
      // Now that the real list is known, a stored region TMDB has dropped can
      // be corrected rather than left showing an empty shelf.
      final corrected = resolveRegion(
        state.region,
        value,
        deviceCountry: _country(),
      );
      emit(state.copyWith(regions: value, loadingRegions: false));
      if (corrected != state.region) add(WatchServicesRegionChanged(corrected));
      return;
    }
    emit(state.copyWith(loadingRegions: false));
  }

  /// The country shown when the viewer's own has no line-up at all. TMDB lists
  /// more for it than for anywhere else, so it is the one that always has
  /// something to show.
  static const String fallbackRegion = 'US';

  Future<void> _fetch(
    String region,
    Emitter<WatchServicesState> emit, {
    required bool explicit,
    String fellBackFrom = '',
  }) async {
    final token = ++_runToken;
    emit(
      state.copyWith(
        status: WatchServicesStatus.loading,
        region: region,
        fellBackFrom: fellBackFrom,
        clearError: true,
      ),
    );
    final result = await useCase(region: region);
    if (token != _runToken) return;
    switch (result) {
      case Success(:final value):
        // Nothing here, and nobody asked for here specifically. TMDB lists
        // providers for 139 countries; a viewer in one of the other sixty
        // opened this and found a blank page, which reads as the feature
        // being broken rather than as their country not being covered. The
        // region list would have said so, but it is only fetched when the
        // picker is opened — so the first thing that knows is this.
        if (value.isEmpty &&
            !explicit &&
            region != fallbackRegion &&
            fellBackFrom.isEmpty) {
          getIt<Analytics>().track(
            AnalyticsEvent.watchServicesRegionFellBack,
            props: {'from': region, 'to': fallbackRegion},
          );
          // So the picker, and the resolver, know the real list next time.
          add(const WatchServicesRegionsRequested());
          await _fetch(
            fallbackRegion,
            emit,
            explicit: true,
            fellBackFrom: region,
          );
          return;
        }
        emit(
          state.copyWith(
            status: WatchServicesStatus.loaded,
            services: value,
            region: region,
            fellBackFrom: fellBackFrom,
          ),
        );
      case Failure(:final error):
        emit(
          state.copyWith(
            status: WatchServicesStatus.error,
            services: const [],
            error: error.toString().replaceFirst('Exception: ', ''),
          ),
        );
    }
  }
}
