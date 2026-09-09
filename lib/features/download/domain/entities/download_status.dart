/// Where a download is in its life.
///
/// ## Why `missing` exists
///
/// A row used to be able to say "Downloaded" for a file that was no longer on
/// disk: the status lived in Hive, the bytes lived on the filesystem, and
/// nothing ever compared the two. Tapping such a row produced "File not found"
/// with no way forward — the row was not `failed`, so no retry was offered, and
/// it stayed broken for the life of the install.
///
/// [missing] is that state named. It is never written by a transfer; it is
/// derived by the integrity sweep when a completed item's artefact has gone,
/// and it renders as a one-tap re-download.
enum DownloadStatus {
  /// Accepted and waiting for a slot. Also what a queue holding for Wi-Fi
  /// looks like.
  pending,

  downloading,

  /// Stopped by the viewer. The partial file is kept and the next start
  /// resumes from it.
  paused,

  /// Finished AND verified against the filesystem.
  completed,

  /// The transfer gave up. Retrying is meaningful.
  failed,

  /// Recorded as finished, but the file is gone. Re-downloading is the only
  /// answer, and the row says so instead of lying.
  missing;

  /// Stable wire value. Persisted by name rather than by index so inserting a
  /// value can never repoint an existing install's rows — the old format
  /// stored the index, and a five-value enum read back through a hard-coded
  /// ceiling of 3 turned `failed` into `completed`.
  String get id => name;

  static DownloadStatus fromId(String? id) {
    for (final s in DownloadStatus.values) {
      if (s.name == id) return s;
    }
    return DownloadStatus.pending;
  }

  /// Legacy rows stored `status` as an enum index over
  /// `{pending, downloading, paused, completed, failed}`. `missing` was added
  /// after that and is never an index, so the mapping is exact.
  static DownloadStatus fromLegacyIndex(int index) {
    const legacy = [
      DownloadStatus.pending,
      DownloadStatus.downloading,
      DownloadStatus.paused,
      DownloadStatus.completed,
      DownloadStatus.failed,
    ];
    return legacy[index.clamp(0, legacy.length - 1)];
  }

  /// Bytes are moving, or about to be.
  bool get isActive =>
      this == DownloadStatus.pending || this == DownloadStatus.downloading;

  /// Nothing more will happen without the viewer asking.
  bool get isTerminal =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.missing;

  /// Whether starting it again is the right offer.
  bool get canRetry =>
      this == DownloadStatus.failed || this == DownloadStatus.missing;

  /// Whether the item can be opened.
  bool get isPlayable => this == DownloadStatus.completed;
}
