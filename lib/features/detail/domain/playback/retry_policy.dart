/// What the player does when a stream fails.
///
/// These rules decided whether an episode recovered or ended on an error
/// screen, and they lived as four loose counters and three predicates spread
/// through a 1,400-line extension on a widget State. Nothing could exercise
/// them: the budgets, the backoff and the recoverable/decoder split all needed
/// a live controller and a widget tree to reach.
///
/// They are the same rules, unchanged. The substrings in particular are the
/// ones the player already matched on — arrived at from real failures across
/// ExoPlayer, AVFoundation and libmpv — and rewriting them would be inventing
/// behaviour under cover of a refactor.
///
/// Pure: a message and a count in, a decision out. No Flutter, no I/O, no
/// clock. There is a test that keeps it that way.
library;

/// What should happen next after a failure.
enum RetryAction {
  /// Try the next mirror. The ladder decides which.
  nextSource,

  /// Re-open the same stream. Live only — a channel that dropped is usually a
  /// channel that will be back.
  reconnect,

  /// Nothing is left to try. Show the error.
  giveUp,
}

/// Budgets, backoff and classification for one episode's failures.
abstract final class RetryPolicy {
  /// Auto-retries per episode before the player stops trying.
  ///
  /// A film either plays or is broken, so four attempts is generous.
  static const int maxLifetimeRetries = 4;

  /// Reconnects allowed for a live broadcast, which is a different problem.
  ///
  /// A channel drops — a segment gap, a CDN failing over, a phone changing
  /// network — and the only correct answer is to reconnect and keep watching.
  /// Four in a two-hour evening meant the player gave up permanently on
  /// something that was working again seconds later.
  static const int maxLiveRetries = 1000;

  /// Consecutive attempts on ONE source before moving on.
  static const int maxAttemptsPerSource = 2;

  /// How long to wait before reconnecting a dropped channel.
  ///
  /// Fast enough that a blip is invisible, backing off so a channel that is
  /// genuinely off air is not hammered all evening.
  static Duration liveBackoff(int attempt) {
    const steps = [1, 2, 4, 8, 15];
    final i = attempt < 0 ? 0 : attempt;
    return Duration(seconds: steps[i < steps.length ? i : steps.length - 1]);
  }

  /// Whether the device simply cannot decode this stream.
  ///
  /// Distinct from a recoverable error, and the distinction is the whole point:
  /// a decoder that lacks the profile will lack it again in a second, so
  /// retrying the same file is wasted time. Another mirror — a different encode
  /// — is the only thing that can help.
  static bool isDecoderError(String raw) {
    final l = raw.toLowerCase();
    return
        // iOS / AVFoundation.
        l.contains('cannot decode') ||
        l.contains('-12906') ||
        l.contains('-12939') ||
        l.contains('coremediaerror') ||
        // Android / ExoPlayer.
        l.contains('exceeds_capabilities') ||
        l.contains('exceeds selected codec') ||
        l.contains('mediacodecvideodecoderexception') ||
        l.contains('decoder failed') ||
        l.contains('decoderinitializationexception') ||
        l.contains('no_unsupported_type');
  }

  /// Whether re-opening the same stream could plausibly work.
  static bool isRecoverableError(String msg) {
    final l = msg.toLowerCase();
    // Never both. The branch order at the call site already routes decoder
    // errors first, but relying on that makes the order load-bearing — and the
    // next person to reorder them has no way to know.
    if (isDecoderError(msg)) return false;
    if (l.contains('-12939') ||
        l.contains('-12938') ||
        l.contains('-12660') ||
        l.contains('404') ||
        l.contains('403') ||
        l.contains('not found') ||
        l.contains('forbidden') ||
        l.contains('coremediaerror') ||
        l.contains('cannot decode') ||
        l.contains('-12906')) {
      return false;
    }
    return l.contains('timed out') ||
        l.contains('timeout') ||
        l.contains('-1001') ||
        l.contains('-1005') ||
        l.contains('source error') ||
        l.contains('mediacodec') ||
        l.contains('decoder');
  }

  /// What to do about [message], given what has already been spent.
  ///
  /// [attempts] is consecutive tries on the current source; [lifetime] is the
  /// budget for the whole episode; [hasUntriedSource] is the ladder's answer.
  static RetryAction decide({
    required String message,
    required bool isLive,
    required int attempts,
    required int lifetime,
    required bool hasUntriedSource,
  }) {
    // Live first and on its own budget: for a channel, a 403 or a 404 is
    // usually a rotated token or a segment that expired while we were away,
    // and the next playlist fetch has the current one. On a file the same code
    // is fatal.
    if (isLive) {
      return lifetime < maxLiveRetries ? RetryAction.reconnect : RetryAction.giveUp;
    }
    if (lifetime >= maxLifetimeRetries) return RetryAction.giveUp;

    // A decode failure never benefits from re-opening the same encode.
    if (isDecoderError(message)) {
      return hasUntriedSource ? RetryAction.nextSource : RetryAction.giveUp;
    }
    if (isRecoverableError(message) && attempts < maxAttemptsPerSource) {
      return RetryAction.nextSource;
    }
    return hasUntriedSource ? RetryAction.nextSource : RetryAction.giveUp;
  }
}
