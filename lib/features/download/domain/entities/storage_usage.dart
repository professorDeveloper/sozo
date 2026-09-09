/// What the offline library costs, and what is left to spend.
///
/// Downloads were the one thing in the app that could fill a phone and the one
/// screen that never said how much they had taken. "Clear all" was the only
/// control, which is not a decision anybody can make without a number.
class StorageUsage {
  const StorageUsage({
    required this.usedBytes,
    required this.freeBytes,
    required this.itemCount,
    this.orphanBytes = 0,
  });

  static const StorageUsage empty =
      StorageUsage(usedBytes: 0, freeBytes: 0, itemCount: 0);

  /// Bytes the downloads folder actually occupies — measured, not summed from
  /// the rows, so a partial file left behind by a killed transfer is counted.
  final int usedBytes;

  /// Free space on the volume the downloads live on. Zero when it could not be
  /// read, and the UI then omits it rather than showing a wrong number.
  final int freeBytes;

  final int itemCount;

  /// Bytes under folders no row points at any more.
  ///
  /// A cancelled download used to leave its part files behind, and nothing
  /// ever swept them: the folder grew for the life of the install with no
  /// screen able to name the space or reclaim it.
  final int orphanBytes;

  bool get hasOrphans => orphanBytes > 0;
}
