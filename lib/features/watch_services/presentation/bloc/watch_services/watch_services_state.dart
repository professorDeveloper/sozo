part of 'watch_services_bloc.dart';

enum WatchServicesStatus { initial, loading, loaded, error }

class WatchServicesState extends Equatable {
  const WatchServicesState({
    this.status = WatchServicesStatus.initial,
    this.region = '',
    this.services = const [],
    this.regions = const [],
    this.loadingRegions = false,
    this.error,
  });

  final WatchServicesStatus status;

  /// The region these [services] are for. Never empty once a load has run.
  final String region;

  final List<WatchServiceEntity> services;

  /// Every country TMDB lists. Empty until the picker is first opened.
  final List<WatchRegionEntity> regions;
  final bool loadingRegions;

  final String? error;

  bool get hasServices => services.isNotEmpty;

  String get regionName {
    for (final r in regions) {
      if (r.code == region) return r.name;
    }
    return region;
  }

  WatchServicesState copyWith({
    WatchServicesStatus? status,
    String? region,
    List<WatchServiceEntity>? services,
    List<WatchRegionEntity>? regions,
    bool? loadingRegions,
    String? error,
    bool clearError = false,
  }) => WatchServicesState(
    status: status ?? this.status,
    region: region ?? this.region,
    services: services ?? this.services,
    regions: regions ?? this.regions,
    loadingRegions: loadingRegions ?? this.loadingRegions,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    status,
    region,
    services,
    regions,
    loadingRegions,
    error,
  ];
}
