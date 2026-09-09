/// A place downloads can live.
///
/// ## Why this is a short list and not a folder picker
///
/// Since Android 10 an app cannot write to an arbitrary folder with a plain
/// path — scoped storage forbids it, and the supported route (SAF) hands back
/// a `content://` tree that a `File`-based downloader, a `File`-based player
/// and libmpv all cannot open. A picker that produced a folder nothing could
/// then read would be a setting that breaks playback.
///
/// What an app CAN write to without any permission at all is its own directory
/// on each storage volume — internal, and the SD card when there is one. That
/// is also the choice people actually want: the phone is full, the card is not.
/// So the list is the volumes, not the filesystem.
class DownloadLocation {
  const DownloadLocation({
    required this.id,
    required this.path,
    required this.label,
    required this.freeBytes,
    required this.totalBytes,
    this.isRemovable = false,
    this.isDefault = false,
  });

  /// Stable across launches, so a stored choice survives the paths moving.
  /// The absolute path itself is NOT stable — an SD card's mount point carries
  /// a volume uuid that changes when it is re-inserted on some devices.
  final String id;

  /// Where the `downloads` folder is created. Absolute, and resolved fresh
  /// every launch — nothing persisted ever holds it.
  final String path;

  final String label;
  final int freeBytes;
  final int totalBytes;

  /// An SD card. Worth saying out loud: a removable volume can be pulled, and
  /// downloads on it then read as missing rather than as broken.
  final bool isRemovable;

  /// The app's own directory, used when nothing has been chosen.
  final bool isDefault;

  factory DownloadLocation.fromJson(Map<String, dynamic> json) =>
      DownloadLocation(
        id: json['id']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        freeBytes: (json['freeBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
        isRemovable: json['removable'] == true,
        isDefault: json['isDefault'] == true,
      );
}

/// What happened when a move was asked for.
enum MoveLocationOutcome {
  moved,

  /// Already there.
  unchanged,

  /// The destination cannot hold what is already downloaded.
  noSpace,

  /// The copy failed part-way. Nothing was lost — the old location is kept.
  failed,
}
