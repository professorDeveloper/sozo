part of 'watch_services_bloc.dart';

sealed class WatchServicesEvent extends Equatable {
  const WatchServicesEvent();

  @override
  List<Object?> get props => const [];
}

class WatchServicesLoad extends WatchServicesEvent {
  const WatchServicesLoad();
}

class WatchServicesRegionChanged extends WatchServicesEvent {
  const WatchServicesRegionChanged(this.region);

  final String region;

  @override
  List<Object?> get props => [region];
}

class WatchServicesRegionsRequested extends WatchServicesEvent {
  const WatchServicesRegionsRequested();
}
