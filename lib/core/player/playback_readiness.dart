import 'dart:async';

/// Metadata (notably duration) can arrive before the video decoder has output.
/// Only dimensions or an explicitly audio-only track list establish readiness.
class PlaybackReadiness {
  const PlaybackReadiness({
    required this.width,
    required this.height,
    required this.hasVideo,
    required this.hasAudio,
    required this.duration,
    this.error,
  });

  final int width;
  final int height;
  final bool hasVideo;
  final bool hasAudio;
  final Duration duration;
  final String? error;

  bool get ready =>
      (width > 0 && height > 0) ||
      (!hasVideo && hasAudio && duration > Duration.zero);
}

Future<void> awaitPlaybackReadiness({
  required PlaybackReadiness Function() read,
  required Iterable<Stream<dynamic>> signals,
  required Future<void> canceled,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final ready = Completer<void>();
  void inspect() {
    if (ready.isCompleted) return;
    final snapshot = read();
    if (snapshot.error != null) {
      ready.completeError(StateError(snapshot.error!));
    } else if (snapshot.ready) {
      ready.complete();
    }
  }

  final subscriptions = [
    for (final stream in signals)
      stream.listen(
        (_) => inspect(),
        onError: (Object error, StackTrace stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      ),
  ];
  canceled.then((_) {
    if (!ready.isCompleted) ready.completeError(StateError('Player disposed'));
  });
  inspect();
  try {
    await ready.future.timeout(timeout);
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
