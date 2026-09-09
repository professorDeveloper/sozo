import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// Deleting, at the three sizes it comes in.
class RemoveDownloadUseCase {
  const RemoveDownloadUseCase(this.repository);

  final DownloadRepository repository;

  Future<void> call(String id) => repository.remove(id);

  /// A whole series in one action. Deleting twelve episodes one row at a time
  /// is the chore that makes people reach for "Clear all" and lose everything
  /// else with it.
  Future<void> many(Iterable<String> ids) => repository.removeAll(ids);

  Future<void> all() => repository.clearAll();
}
