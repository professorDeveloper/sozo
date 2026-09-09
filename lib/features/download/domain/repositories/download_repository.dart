import 'package:flutter/foundation.dart';

import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/storage_usage.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';

/// Why an enqueue was refused.
///
/// The old `startDownload` returned a bare `bool`, so "already downloading",
/// "no permission" and "the disk is full" were one answer and the caller
/// showed one message for all three.
enum EnqueueOutcome {
  started,

  /// Already queued, running or finished. Not an error.
  alreadyPresent,

  /// The device does not have room for it.
  noSpace,

  /// The url is an embed page rather than a stream, so saving it would produce
  /// an HTML file under a video's name.
  notDownloadable,

  /// The platform refused to start the transfer at all.
  refused,
}

/// The offline library.
///
/// Everything above this line is domain: entities, use cases and the widgets
/// that render them. Everything below is one of two transfer engines, a Hive
/// box and a platform channel — none of which the rest of the app knows about.
abstract class DownloadRepository {
  /// Resolves storage and reconciles what is on disk with what is recorded.
  /// Called once at startup, before anything reads a download.
  Future<void> initialize();

  /// Ticks whenever any row changes. Coarse on purpose: the list rebuilds from
  /// [items], and a per-item stream would mean a subscription per row.
  ValueListenable<int> get revision;

  /// True while the queue is holding for Wi-Fi, so the UI can say so rather
  /// than showing downloads that appear stuck.
  bool get isWaitingForWifi;

  List<DownloadItem> items();

  DownloadItem? byId(String id);

  /// An openable path for [item], or null when the artefact is not on disk.
  ///
  /// The one place a relative path becomes an absolute one. Synchronous
  /// because every call site is a build method or a tap handler, which is why
  /// the root is resolved in [initialize].
  String? absolutePathOf(DownloadItem item);

  /// The cached poster, or null. Same rule as [absolutePathOf].
  String? thumbnailPathOf(DownloadItem item);

  Future<EnqueueOutcome> enqueue(DownloadRequest request);

  /// Stop, but keep what has been written. The next start resumes.
  Future<void> pause(String id);

  Future<void> resume(String id);

  /// Clear the failure and start again, whatever the retry budget says.
  Future<void> retry(String id);

  /// Stop and forget, deleting the partial file.
  Future<void> cancel(String id);

  Future<void> remove(String id);

  Future<void> removeAll(Iterable<String> ids);

  Future<void> clearAll();

  /// Restart everything that was running when the app was last killed.
  Future<void> resumeInterrupted();

  /// Re-reads the filesystem for every row and repairs what it finds.
  ///
  /// This is what turns a "Downloaded" row whose file has gone into a
  /// [DownloadStatus.missing] row with a re-download button, instead of a lie
  /// that ends in "File not found".
  Future<void> verifyAll();

  /// Measured usage, free space, and how much is owed to orphaned folders.
  Future<StorageUsage> usage();

  /// Deletes folders no row points at.
  Future<int> sweepOrphans();

  /// Every volume the library can be kept on, current one flagged.
  ///
  /// One entry off Android, where there is no choice to offer.
  Future<List<DownloadLocation>> locations();

  /// Moves the whole library to [location].
  Future<MoveLocationOutcome> moveTo(DownloadLocation location);

  /// Copies a finished download into the device's shared Downloads folder.
  /// Returns the user-visible location, or null when it could not be done.
  Future<String?> exportToPublicDownloads(String id);

  /// The pages of a finished manga chapter, as local file paths.
  Future<List<MangaPageEntity>> localMangaPages(String id);
}
