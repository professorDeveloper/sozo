import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';

abstract class WatchServicesRepository {
  Future<Result<List<WatchRegionEntity>>> loadRegions();

  Future<Result<List<WatchServiceEntity>>> loadServices({
    required String region,
  });
}
