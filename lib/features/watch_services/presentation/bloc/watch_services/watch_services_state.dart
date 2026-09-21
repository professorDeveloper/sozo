part of 'watch_services_bloc.dart';

enum WatchServicesStatus { initial, loading, loaded, error }

class WatchServicesState extends Equatable {
  const WatchServicesState({
    this.status = WatchServicesStatus.initial,
    this.region = '',
    this.services = const [],
    this.regions = const [],
    this.loadingRegions = false,
    this.fellBackFrom = '',
    this.error,
  });

  final WatchServicesStatus status;

  /// The region these [services] are for. Never empty once a load has run.
  final String region;

  final List<WatchServiceEntity> services;

  /// Every country TMDB lists. Empty until the picker is first opened.
  final List<WatchRegionEntity> regions;
  final bool loadingRegions;

  /// The country that was asked for and had nothing, when [region] is a
  /// stand-in the app chose instead. Empty the rest of the time.
  ///
  /// TMDB lists providers for 139 countries and Uzbekistan is not one of them,
  /// which for a viewer there meant opening this screen and finding an empty
  /// page — the feature reading as broken rather than as unavailable. Falling
  /// back silently would be worse: a grid of services nobody here can
  /// subscribe to, under no explanation at all. So the app falls back AND says
  /// which country it is showing.
  final String fellBackFrom;

  final String? error;

  bool get hasServices => services.isNotEmpty;

  String get regionName => nameOf(region);

  /// A country's name, or its code while the list has not been fetched.
  String nameOf(String code) {
    for (final r in regions) {
      if (r.code == code) return r.name;
    }
    return code;
  }

  WatchServicesState copyWith({
    WatchServicesStatus? status,
    String? region,
    List<WatchServiceEntity>? services,
    List<WatchRegionEntity>? regions,
    bool? loadingRegions,
    String? fellBackFrom,
    String? error,
    bool clearError = false,
  }) => WatchServicesState(
    status: status ?? this.status,
    region: region ?? this.region,
    services: services ?? this.services,
    regions: regions ?? this.regions,
    loadingRegions: loadingRegions ?? this.loadingRegions,
    fellBackFrom: fellBackFrom ?? this.fellBackFrom,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    status,
    region,
    services,
    regions,
    loadingRegions,
    fellBackFrom,
    error,
  ];
}
