import 'package:soplay/features/download/domain/entities/storage_usage.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// What the library costs, and reclaiming what nothing points at.
class DownloadStorageUseCase {
  const DownloadStorageUseCase(this.repository);

  final DownloadRepository repository;

  Future<StorageUsage> usage() => repository.usage();

  /// Deletes folders left behind by cancelled or half-removed downloads.
  /// Returns how many were removed.
  Future<int> sweepOrphans() => repository.sweepOrphans();
}
