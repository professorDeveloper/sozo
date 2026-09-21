import 'package:dio/dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/watch_services/data/datasources/watch_services_data_source.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/repositories/watch_services_repository.dart';

class WatchServicesRepositoryImp implements WatchServicesRepository {
  const WatchServicesRepositoryImp(this.dataSource);

  final WatchServicesDataSource dataSource;

  @override
  Future<Result<List<WatchRegionEntity>>> loadRegions() =>
      _guard(dataSource.loadRegions);

  @override
  Future<Result<List<WatchServiceEntity>>> loadServices({
    required String region,
  }) => _guard(() => dataSource.loadServices(region));

  /// The server's own sentence when it sent one.
  ///
  /// `DioException.toString()` is a paragraph about `validateStatus`; the
  /// message the backend wrote — "region must be a two-letter country code" —
  /// is the part worth showing.
  static Future<Result<List<T>>> _guard<T>(
    Future<List<T>> Function() fetch,
  ) async {
    try {
      return Success(await fetch());
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message = (raw is Map ? raw['message'] : null) ?? e.message;
      return Failure(Exception(message.toString()));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
