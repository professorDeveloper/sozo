import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/repositories/watch_services_repository.dart';

/// Bundled the way [HomeUseCase] bundles `callGenres`: two questions about one
/// screen, asked separately because the second is only needed once somebody
/// opens the picker.
class WatchServicesUseCase {
  const WatchServicesUseCase(this.repository);

  final WatchServicesRepository repository;

  Future<Result<List<WatchServiceEntity>>> call({required String region}) =>
      repository.loadServices(region: region);

  Future<Result<List<WatchRegionEntity>>> callRegions() =>
      repository.loadRegions();
}
