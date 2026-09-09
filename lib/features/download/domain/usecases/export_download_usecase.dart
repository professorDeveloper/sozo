import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// Copy a finished download somewhere the rest of the device can see it.
///
/// Everything is kept in app-private storage, which is right while the app
/// owns it and useless the moment anybody wants the file for anything else —
/// no file manager can see it, no cable can reach it, and uninstalling to
/// "free" the space deletes it.
class ExportDownloadUseCase {
  const ExportDownloadUseCase(this.repository);

  final DownloadRepository repository;

  /// The user-visible location, or null when it could not be copied.
  Future<String?> call(String id) => repository.exportToPublicDownloads(id);
}
