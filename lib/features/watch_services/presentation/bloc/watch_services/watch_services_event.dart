part of 'watch_services_bloc.dart';

sealed class WatchServicesEvent extends Equatable {
  const WatchServicesEvent();

  @override
  List<Object?> get props => const [];
}

class WatchServicesLoad extends WatchServicesEvent {
  const WatchServicesLoad();
}
