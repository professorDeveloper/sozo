/// Why a download stopped, as a value rather than a sentence.
///
/// The old code stored nothing at all: a failed row said "Failed" and that was
/// the whole story, so "the disk is full", "the link expired" and "there is no
/// network" were one indistinguishable state with one useless retry button.
///
/// Classification is pure and testable; the wording lives in the widget layer,
/// which is where localisation belongs. There is a test that keeps this file
/// free of Flutter.
enum DownloadFailureKind {
  /// No connection, a timeout, a dropped socket. Retrying is the right move.
  network('network', retryable: true),

  /// The host refused: 401/403, or a token that has expired. The link has to
  /// be resolved again, which means playing the title once.
  refused('refused', retryable: false),

  /// 404 / 410 — the file has moved or gone.
  gone('gone', retryable: false),

  /// Not enough room on the device.
  noSpace('no_space', retryable: true),

  /// The server answered, but with something that is not media — an HTML
  /// error page or a challenge served as 200. Saving it produces a file that
  /// completes and then fails to open, which is the worst shape a failure can
  /// take.
  notMedia('not_media', retryable: false),

  /// The transfer finished but the artefact did not survive verification:
  /// missing segments, a zero-length file, a truncated part.
  incomplete('incomplete', retryable: true),

  /// Anything else. The raw message is kept and shown.
  unknown('unknown', retryable: true);

  const DownloadFailureKind(this.id, {required this.retryable});

  /// Persisted. Never rename one.
  final String id;

  /// Whether trying the same thing again can plausibly work.
  final bool retryable;

  String get messageKey => 'downloads.error.$id';

  static DownloadFailureKind fromId(String? id) {
    for (final k in DownloadFailureKind.values) {
      if (k.id == id) return k;
    }
    return DownloadFailureKind.unknown;
  }

  /// What went wrong, from whatever the transfer layer said.
  ///
  /// The substrings are the ones the two engines actually produce — Dio's
  /// exception text on the Dart path, `HttpURLConnection`'s on the Android
  /// one — so a message from either lands in the same bucket.
  static DownloadFailureKind classify(String raw) {
    final l = raw.toLowerCase();
    if (l.isEmpty) return DownloadFailureKind.unknown;
    if (l.contains('enospc') ||
        l.contains('no space') ||
        l.contains('not enough space') ||
        l.contains('disk full')) {
      return DownloadFailureKind.noSpace;
    }
    if (l.contains('403') || l.contains('401') || l.contains('forbidden')) {
      return DownloadFailureKind.refused;
    }
    if (l.contains('404') || l.contains('410') || l.contains('not found')) {
      return DownloadFailureKind.gone;
    }
    if (l.contains('timeout') ||
        l.contains('timed out') ||
        l.contains('connection') ||
        l.contains('socket') ||
        l.contains('unreachable') ||
        l.contains('network')) {
      return DownloadFailureKind.network;
    }
    if (l.contains('not media') ||
        l.contains('html') ||
        l.contains('content-type')) {
      return DownloadFailureKind.notMedia;
    }
    if (l.contains('incomplete') ||
        l.contains('truncated') ||
        l.contains('missing segment') ||
        l.contains('verification')) {
      return DownloadFailureKind.incomplete;
    }
    return DownloadFailureKind.unknown;
  }
}
