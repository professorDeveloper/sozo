import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/usecase/watch_services_usecase.dart';

part 'watch_services_event.dart';
part 'watch_services_state.dart';

/// Which services the viewer's country has, held for the life of the app.
///
/// A singleton rather than a per-screen bloc, which is the opposite of how
/// every other bloc here is registered, and it is load-bearing: the Home feed
/// is torn down and rebuilt on every `HomeLoading -> HomeLoaded`, so a
/// per-screen instance would refetch this on every source switch and every
/// pull-to-refresh. What it holds is a fact about a country, not about the
/// current source, and it does not change when the source does.
///
/// ## Why there is no country picker
///
/// There was one, and it was a filter nobody needed: the services worth
/// showing are the ones the viewer can subscribe to, and those are the ones
/// where they are. The country is the device's, and only where TMDB lists
/// nothing for it does the screen show [fallbackRegion] instead — and say so.
///
/// A choice stored by the picker is not read either. With no way left to
/// change it, it would pin the screen to that country for good.
class WatchServicesBloc extends Bloc<WatchServicesEvent, WatchServicesState> {
  WatchServicesBloc({required this.useCase, String Function()? deviceCountry})
    : _country = deviceCountry ?? _platformCountry,
      super(const WatchServicesState()) {
    on<WatchServicesLoad>(_onLoad);
  }

  final WatchServicesUseCase useCase;

  /// Where the viewer is.
  ///
  /// A seam rather than a direct read of [PlatformDispatcher], for the same
  /// reason the countdown takes its clock: the whole of the fallback behaviour
  /// depends on this value, and `PlatformDispatcher.instance` is a global a
  /// test cannot move — `localeTestValue` sets the binding's dispatcher, not
  /// the static one the app would otherwise read.
  final String Function() _country;

  static String _platformCountry() =>
      PlatformDispatcher.instance.locale.countryCode ?? '';

  /// The country shown when the viewer's own has no line-up at all. TMDB lists
  /// more for it than for anywhere else, so it is the one that always has
  /// something to show.
  static const String fallbackRegion = 'US';

  Future<void> _onLoad(
    WatchServicesLoad event,
    Emitter<WatchServicesState> emit,
  ) async {
    if (state.status == WatchServicesStatus.loading) return;
    final device = _country().trim().toUpperCase();
    await _fetch(_isCountry(device) ? device : fallbackRegion, emit);
  }

  static bool _isCountry(String code) =>
      code.length == 2 &&
      code.codeUnits.every((c) => c >= 0x41 && c <= 0x5A);

  Future<void> _fetch(
    String region,
    Emitter<WatchServicesState> emit, {
    String fellBackFrom = '',
  }) async {
    emit(
      state.copyWith(
        status: WatchServicesStatus.loading,
        region: region,
        fellBackFrom: fellBackFrom,
        clearError: true,
      ),
    );
    final result = await useCase(region: region);
    switch (result) {
      case Success(:final value):
        // Nothing here. TMDB lists providers for 139 countries; a viewer in
        // one of the other sixty opened this and found a blank page, which
        // reads as the feature being broken rather than as their country not
        // being covered.
        if (value.isEmpty && region != fallbackRegion && fellBackFrom.isEmpty) {
          getIt<Analytics>().track(
            AnalyticsEvent.watchServicesRegionFellBack,
            props: {'from': region, 'to': fallbackRegion},
          );
          await _fetch(fallbackRegion, emit, fellBackFrom: region);
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
