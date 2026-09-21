import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  WatchServicesBloc({required this.useCase, required this.hive})
    : super(const WatchServicesState()) {
    on<WatchServicesLoad>(_onLoad);
    on<WatchServicesRegionChanged>(_onRegionChanged);
    on<WatchServicesRegionsRequested>(_onRegionsRequested);
  }

  final WatchServicesUseCase useCase;
  final HiveService hive;

  int _runToken = 0;

  /// The device's country, for a viewer who has never chosen one.
  static String get _deviceCountry =>
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
      deviceCountry: _deviceCountry,
    );
    await _fetch(region, emit);
  }

  Future<void> _onRegionChanged(
    WatchServicesRegionChanged event,
    Emitter<WatchServicesState> emit,
  ) async {
    final region = event.region.trim().toUpperCase();
    if (region.isEmpty) return;
    await hive.setWatchRegion(region);
    await _fetch(region, emit);
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
        deviceCountry: _deviceCountry,
      );
      emit(state.copyWith(regions: value, loadingRegions: false));
      if (corrected != state.region) add(WatchServicesRegionChanged(corrected));
      return;
    }
    emit(state.copyWith(loadingRegions: false));
  }

  Future<void> _fetch(String region, Emitter<WatchServicesState> emit) async {
    final token = ++_runToken;
    emit(
      state.copyWith(
        status: WatchServicesStatus.loading,
        region: region,
        clearError: true,
      ),
    );
    final result = await useCase(region: region);
    if (token != _runToken) return;
    switch (result) {
      case Success(:final value):
        emit(
          state.copyWith(
            status: WatchServicesStatus.loaded,
            services: value,
            region: region,
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
