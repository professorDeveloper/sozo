import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// Choosing where the offline library is kept.
///
/// One volume or several: a phone with no SD card has nothing to choose, and
/// the UI hides the row rather than offering a list of one.
class DownloadLocationUseCase {
  const DownloadLocationUseCase(this.repository);

  final DownloadRepository repository;

  Future<List<DownloadLocation>> call() => repository.locations();

  /// Moves everything already downloaded along with the setting. Nothing is
  /// deleted until every file has arrived at the destination.
  Future<MoveLocationOutcome> moveTo(DownloadLocation location) =>
      repository.moveTo(location);
}
