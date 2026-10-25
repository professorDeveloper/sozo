import 'dart:async';

/// A failed mpv decoder can still be supported by Android's platform player.
/// Network and format failures must go back to source recovery instead.
Future<bool> initializeWithDecoderFallback({
  required Future<void> Function() initialize,
  required Future<void> Function() fallback,
  required bool Function() canFallback,
}) async {
  try {
    await initialize();
    return false;
  } catch (error) {
    final decoder = error.toString().toLowerCase().contains(
      'could not open codec',
    );
    if (!canFallback() || !(decoder || error is TimeoutException)) rethrow;
    await fallback();
    return true;
  }
}

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

/// Waits until [read] reports a playable stream.
///
/// [pictureTimeout], when given, is how long a stream whose video track is
/// already known may go without the decoder producing a picture. That is a
/// decoder that has stalled, not a slow network — the track list exists only
/// once the container has been read — and it is the case the platform player
/// can rescue (see [initializeWithDecoderFallback]). Measured from the first
/// snapshot that lists a video track, so a slow host's long open does not
/// count against it; [timeout] still bounds the whole wait.
Future<void> awaitPlaybackReadiness({
  required PlaybackReadiness Function() read,
  required Iterable<Stream<dynamic>> signals,
  required Future<void> canceled,
  Duration timeout = const Duration(seconds: 30),
  Duration? pictureTimeout,
}) async {
  final ready = Completer<void>();
  Timer? pictureTimer;
  void inspect() {
    if (ready.isCompleted) return;
    final snapshot = read();
    if (snapshot.error != null) {
      ready.completeError(StateError(snapshot.error!));
    } else if (snapshot.ready) {
      ready.complete();
    } else if (pictureTimeout != null &&
        snapshot.hasVideo &&
        pictureTimer == null) {
      pictureTimer = Timer(pictureTimeout, () {
        if (!ready.isCompleted) {
          ready.completeError(
            TimeoutException('No picture from the decoder', pictureTimeout),
          );
        }
      });
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
    pictureTimer?.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

/// How long a stream may take to reach its first frame before the player
/// gives up on that server and moves to the next. Null: no limit.
///
/// Neither engine bounds a start on its own. libmpv's readiness wait is 30 s
/// and on Android then hands the stream to ExoPlayer, whose initialize()
/// waits for its first READY with no limit at all, so a host that accepts the
/// connection and then trickles left "Video loading…" up for good (ticket
/// 6aba98fa). The resolve before this has had a deadline for a long time;
/// this is the same line for the second half.
///
/// The slowest healthy starts in the support logs are 17–19 s (vidapi HLS on
/// mobile data, log_2e4886), so 25 s leaves room without making a dead host
/// cost much more than it did. A stream sniffed out of an embed page gets
/// longer: those CDNs are the slow ones (a playmogo file took 43 s in
/// log_045e01). A torrent has to find peers and fetch the first pieces before
/// there is anything to decode. A live channel that will not open is
/// reconnected rather than abandoned, so a few seconds more costs nothing.
/// A file on disk has nothing remote to wait for.
Duration? startupBudget({
  required bool local,
  bool torrent = false,
  bool sniffed = false,
  bool live = false,
}) {
  if (local) return null;
  if (torrent) return const Duration(seconds: 90);
  if (sniffed) return const Duration(seconds: 35);
  if (live) return const Duration(seconds: 30);
  return const Duration(seconds: 25);
}

/// Waits for [start], failing with a [TimeoutException] once [budget] has
/// passed without it completing.
///
/// [restarts] gives the start a fresh [budget] each time it fires, at most
/// [maxRestarts] times: a controller that hands the stream to another engine
/// mid-start (libmpv to ExoPlayer) has spent part of the allowance on an
/// engine that could not play it, and the one that can deserves its own.
///
/// [start] is left running on a timeout, and anything it throws afterwards is
/// swallowed here; the caller disposes the controller behind it.
Future<void> withinStartupBudget(
  Future<void> start, {
  required Duration budget,
  Stream<void>? restarts,
  int maxRestarts = 1,
}) async {
  final done = Completer<void>();
  Timer? timer;
  void arm() {
    timer?.cancel();
    timer = Timer(budget, () {
      if (!done.isCompleted) {
        done.completeError(TimeoutException('Playback did not start', budget));
      }
    });
  }

  var restartsLeft = maxRestarts;
  arm();
  final subscription = restarts?.listen((_) {
    if (done.isCompleted || restartsLeft <= 0) return;
    restartsLeft--;
    arm();
  });
  start.then(
    (_) {
      if (!done.isCompleted) done.complete();
    },
    onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  try {
    await done.future;
  } finally {
    timer?.cancel();
    // Not awaited: the answer is already decided, and a broadcast stream's
    // cancel hands back a future that belongs to no zone in particular.
    final cancel = subscription?.cancel();
    if (cancel != null) unawaited(cancel);
  }
}

/// What a network error reported during playback turned out to be, judged
/// after a grace period.
enum NetworkStall {
  /// The playhead moved on: the engine's own retry got through.
  recovered,

  /// Playback stopped on it: still not moving while meant to be playing, or
  /// ended well short of the end. Report it, so the player can reconnect.
  fatal,

  /// Paused with the playhead where it stalled. Nothing to judge yet.
  undecided,
}

/// Judges a network error held since the playhead was at [stalledAt].
///
/// libmpv reports every error-level `tcp:` line ffmpeg logs as an error, and
/// most of them are stalls the HLS demuxer (seg_max_retry) or the http layer
/// (reconnect) gets past on its own. Only one that stopped playback is worth
/// tearing the stream down for. [completed] short of [duration] is the other
/// way playback stops on one: a progressive file whose connection could not
/// be resumed reads as an early end of file.
NetworkStall judgeNetworkStall({
  required Duration stalledAt,
  required Duration position,
  required bool playing,
  required bool completed,
  required Duration duration,
}) {
  // The end of file first: the cache keeps the playhead moving well past the
  // stall, so a file the connection cut short has always "moved" by the time
  // it ends. Without a length (a live stream) any end is the connection's.
  if (completed) {
    final early =
        duration <= Duration.zero ||
        position < duration - const Duration(seconds: 5);
    return early ? NetworkStall.fatal : NetworkStall.recovered;
  }
  // Either way: a viewer who seeked back past the stall and is watching again
  // has a stream that works, even though the playhead is behind where it was.
  if ((position - stalledAt).abs() > const Duration(seconds: 1)) {
    return NetworkStall.recovered;
  }
  return playing ? NetworkStall.fatal : NetworkStall.undecided;
}
