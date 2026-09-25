import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/repositories/watch_services_repository.dart';

class WatchServicesUseCase {
  const WatchServicesUseCase(this.repository);

  final WatchServicesRepository repository;

  Future<Result<List<WatchServiceEntity>>> call({required String region}) =>
      repository.loadServices(region: region);
}
