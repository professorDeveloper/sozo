import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// Pause, resume, retry, cancel — the four things a viewer can do to a
/// transfer that is already in the list.
///
/// One use case rather than four files: they take the same argument, they are
/// always registered together, and splitting them would be four identical
/// wrappers around four one-line calls. The distinctions that matter are in
/// the repository, which is where pausing keeps the partial file and
/// cancelling throws it away.
class ControlDownloadUseCase {
  const ControlDownloadUseCase(this.repository);

  final DownloadRepository repository;

  Future<void> pause(String id) => repository.pause(id);

  Future<void> resume(String id) => repository.resume(id);

  /// Clears the recorded failure and starts again, ignoring the automatic
  /// retry budget — somebody who pressed the button is not to be told the
  /// budget is spent.
  Future<void> retry(String id) => repository.retry(id);

  Future<void> cancel(String id) => repository.cancel(id);
}
