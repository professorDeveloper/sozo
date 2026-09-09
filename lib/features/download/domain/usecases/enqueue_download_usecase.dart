import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// Ask for something to be kept.
///
/// Returns an [EnqueueOutcome] rather than a bool so the caller can say which
/// of the five things happened. Every screen that offers a download shows a
/// message afterwards, and "already downloaded", "no room on the device" and
/// "play it once first" are three different messages.
class EnqueueDownloadUseCase {
  const EnqueueDownloadUseCase(this.repository);

  final DownloadRepository repository;

  Future<EnqueueOutcome> call(DownloadRequest request) =>
      repository.enqueue(request);
}
