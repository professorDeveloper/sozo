/// What the torrent server is doing with a torrent right now.
///
/// Codes come from TorrServer's `torr/state/state.go`. The server also sends a
/// human string alongside them, which is kept as [label] so an unrecognised
/// code from a future build still displays something truthful.
enum TorrentState {
  /// Accepted, nothing started yet.
  added,

  /// Fetching metadata from the swarm. For a magnet this is the wait before
  /// the file list even exists — the phase users read as "nothing happening".
  gettingInfo,

  /// Buffering the head of the file before playback starts.
  preloading,

  /// Downloading and serving.
  working,

  closed,

  /// Known to the server but not active.
  inDatabase,

  unknown;

  static TorrentState fromCode(int? code) => switch (code) {
        0 => TorrentState.added,
        1 => TorrentState.gettingInfo,
        2 => TorrentState.preloading,
        3 => TorrentState.working,
        4 => TorrentState.closed,
        5 => TorrentState.inDatabase,
        _ => TorrentState.unknown,
      };

  /// Whether the stream URL can be opened yet.
  bool get isReady => this == TorrentState.working || this == TorrentState.preloading;

  /// Whether the app should keep waiting rather than surface an error.
  bool get isTransient =>
      this == TorrentState.added || this == TorrentState.gettingInfo;
}

/// One file inside a torrent.
class TorrentFileEntry {
  const TorrentFileEntry({
    required this.id,
    required this.path,
    required this.lengthBytes,
  });

  /// The server's own index for this file. This is what `/stream` takes as
  /// `index`, and it is 1-based — file 0 is not a thing.
  final int id;

  /// Path inside the torrent, e.g. `Season 1/Episode 01.mkv`.
  final String path;

  final int lengthBytes;

  /// Just the file name, for display.
  String get name {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Containers the app's players can actually open.
  static const _videoExtensions = {
    'mkv', 'mp4', 'avi', 'webm', 'mov', 'm4v', 'ts', 'm2ts', 'flv', 'wmv', 'ogv',
  };

  static const _subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub'};

  bool get isVideo => _videoExtensions.contains(extension);
  bool get isSubtitle => _subtitleExtensions.contains(extension);

  /// Sample and extras folders that torrents carry alongside the episode.
  /// Picking one of these automatically is the classic "why is my episode 40
  /// seconds long" bug.
  bool get isSample {
    final lower = path.toLowerCase();
    return lower.contains('/sample') ||
        lower.startsWith('sample') ||
        lower.contains('sample.') ||
        lengthBytes < 20 * 1024 * 1024 && isVideo;
  }

  static TorrentFileEntry? fromJson(Map<String, dynamic> json) {
    final path = json['path']?.toString();
    if (path == null || path.isEmpty) return null;
    return TorrentFileEntry(
      id: _int(json['id']) ?? 1,
      path: path,
      lengthBytes: _int(json['length']) ?? 0,
    );
  }

  static int? _int(Object? raw) => switch (raw) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value.trim()),
        _ => null,
      };
}

/// A snapshot of one torrent, as the server reports it.
class TorrentStatus {
  const TorrentStatus({
    required this.hash,
    required this.state,
    required this.label,
    this.name,
    this.files = const [],
    this.totalBytes,
    this.downloadedBytes,
    this.preloadedBytes,
    this.preloadTargetBytes,
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.activePeers,
    this.totalPeers,
    this.connectedSeeders,
  });

  final String hash;
  final TorrentState state;

  /// The server's own description of [state], shown when there is nothing
  /// better to say.
  final String label;

  final String? name;

  /// Empty until metadata has been fetched from the swarm — which for a magnet
  /// is not immediate. [hasMetadata] is the flag worth waiting on.
  final List<TorrentFileEntry> files;

  final int? totalBytes;
  final int? downloadedBytes;

  /// How much of the pre-buffer is filled, and how much it is aiming for.
  /// These are what a "starting stream…" progress bar should show; the overall
  /// download is irrelevant to whether playback can begin.
  final int? preloadedBytes;
  final int? preloadTargetBytes;

  /// Bytes per second.
  final double downloadSpeed;
  final double uploadSpeed;

  final int? activePeers;
  final int? totalPeers;
  final int? connectedSeeders;

  bool get hasMetadata => files.isNotEmpty;

  /// Playable files, biggest first, with samples and extras dropped.
  ///
  /// Sorting by size is what makes the top entry right for a single-episode
  /// torrent that also ships a creditless OP, a sample and a `.nfo`.
  List<TorrentFileEntry> get videoFiles {
    final videos = files.where((f) => f.isVideo && !f.isSample).toList()
      ..sort((a, b) => b.lengthBytes.compareTo(a.lengthBytes));
    if (videos.isNotEmpty) return videos;
    // Everything looked like a sample — better to offer the small files than
    // to claim the torrent has no video at all.
    return files.where((f) => f.isVideo).toList()
      ..sort((a, b) => b.lengthBytes.compareTo(a.lengthBytes));
  }

  List<TorrentFileEntry> get subtitleFiles =>
      files.where((f) => f.isSubtitle).toList();

  /// True when the torrent holds several episodes and the user should be asked
  /// which one to play rather than being dropped into whichever came first.
  bool get needsFileChoice => videoFiles.length > 1;

  /// Fraction of the pre-buffer that is filled, or null when the server has
  /// not said what it is aiming for yet.
  double? get preloadProgress {
    final target = preloadTargetBytes;
    final done = preloadedBytes;
    if (target == null || done == null || target <= 0) return null;
    return (done / target).clamp(0.0, 1.0);
  }

  static TorrentStatus? fromJson(Map<String, dynamic> json) {
    final hash = json['hash']?.toString();
    if (hash == null || hash.isEmpty) return null;

    final rawFiles = json['file_stats'];
    return TorrentStatus(
      hash: hash,
      state: TorrentState.fromCode(_int(json['stat'])),
      label: json['stat_string']?.toString() ?? '',
      name: json['name']?.toString(),
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map((f) => TorrentFileEntry.fromJson(Map<String, dynamic>.from(f)))
              .whereType<TorrentFileEntry>()
              .toList()
          : const [],
      totalBytes: _int(json['torrent_size']),
      downloadedBytes: _int(json['loaded_size']) ?? _int(json['bytes_read_data']),
      preloadedBytes: _int(json['preloaded_bytes']),
      preloadTargetBytes: _int(json['preload_size']),
      downloadSpeed: _double(json['download_speed']) ?? 0,
      uploadSpeed: _double(json['upload_speed']) ?? 0,
      activePeers: _int(json['active_peers']),
      totalPeers: _int(json['total_peers']),
      connectedSeeders: _int(json['connected_seeders']),
    );
  }

  static int? _int(Object? raw) => switch (raw) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value.trim()),
        _ => null,
      };

  static double? _double(Object? raw) => switch (raw) {
        num value => value.toDouble(),
        String value => double.tryParse(value.trim()),
        _ => null,
      };
}
