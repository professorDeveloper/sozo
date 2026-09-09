import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// Make the list tell the truth about the filesystem.
///
/// Run at startup and whenever the Downloads screen opens. Without it a row
/// can claim "Downloaded" for a file that is no longer there — which is
/// exactly what happened when the stored path was absolute and the app was
/// restored, reinstalled or opened under a second Android user: every row read
/// as finished and every tap answered "File not found", with no retry offered
/// because the row was not `failed`.
class VerifyDownloadsUseCase {
  const VerifyDownloadsUseCase(this.repository);

  final DownloadRepository repository;

  Future<void> call() => repository.verifyAll();
}
