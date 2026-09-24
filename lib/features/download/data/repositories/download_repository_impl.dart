import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/download/data/subtitle_sidecar.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/network/external_dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/playback/wakelock_holds.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/data/datasources/download_local_data_source.dart';
import 'package:soplay/features/download/data/datasources/download_native_data_source.dart';
import 'package:soplay/features/download/data/datasources/download_transfer_data_source.dart';
import 'package:soplay/features/download/data/epub_builder.dart';
import 'package:soplay/features/download/data/models/download_item_model.dart';
import 'package:soplay/features/download/data/storage/download_storage.dart';
import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/storage_usage.dart';
import 'package:soplay/features/download/domain/offline_relink.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';

/// The offline library, assembled from a Hive box, a filesystem, and whichever
/// of the two transfer engines this platform uses.
///
/// ## The invariant everything here exists to hold
///
/// **A row that says `completed` has a file behind it.** The old code had no
/// such rule: the status lived in Hive, the bytes lived on disk under an
/// absolute path that stopped being valid the moment the app was restored or
/// opened under a second Android user, and nothing ever compared the two. What
/// a viewer saw was three rows marked "Downloaded" and a toast saying "File not
/// found" — with no retry offered, because none of them was `failed`.
///
/// The rule is held in three places, and it needs all three:
///
///  * paths are stored relative and resolved per launch ([DownloadLayout]),
///  * a transfer only reports success once its artefact is on disk and whole,
///  * [verifyAll] re-checks every row against the filesystem at startup and
///    demotes the ones that cannot be opened to [DownloadStatus.missing],
///    which renders as a re-download rather than a lie.
class DownloadRepositoryImpl implements DownloadRepository {
  DownloadRepositoryImpl({
    required DownloadLocalDataSource local,
    required DownloadStorage storage,
    required DownloadNativeDataSource native,
    required DownloadTransferDataSource transfer,
    required HiveService hive,
    SubtitleSidecar? subtitles,
  }) : _local = local,
       _storage = storage,
       _native = native,
       _transfer = transfer,
       _hive = hive,
       _subtitles = subtitles;

  /// The subtitle files kept with a video download, removed with it.
  final SubtitleSidecar? _subtitles;

  final DownloadLocalDataSource _local;
  final DownloadStorage _storage;
  final DownloadNativeDataSource _native;
  final DownloadTransferDataSource _transfer;
  final HiveService _hive;

  /// How many transfers run at once.
  ///
  /// Queueing ten episodes used to start ten transfers, which on a phone means
  /// ten streams fighting over one connection: everything crawls and the
  /// episode somebody actually wanted finishes last.
  static const int maxConcurrent = 2;

  final List<String> _queue = <String>[];
  final Set<String> _running = <String>{};
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};

  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _nativePoll;
  bool _waitingForWifi = false;
  int _wakelocks = 0;

  /// The one initialisation, shared by everyone who asks for it.
  ///
  /// A plain `bool _initialized` set before the awaits let a second caller
  /// through while the storage root was still being resolved — and every path
  /// below `absolutePathOf` then threw, on the first download of a cold start.
  Future<void>? _initializing;

  /// Ids the viewer has just paused or cancelled, held until the platform
  /// agrees.
  ///
  /// The Android transfer runs in a service that does not stop the instant it
  /// is told to — it finishes the buffer it is on. The poller runs every two
  /// seconds, so between the tap and the service noticing, a poll would read
  /// `downloading` with fresh progress and write it straight back over the
  /// `paused` the viewer had just asked for. The row flipped back, the bar
  /// carried on, and pausing looked like a button that did nothing.
  ///
  /// The intent is remembered here and honoured by [_syncNative] until the
  /// service reports the state it was asked for.
  final Map<String, DownloadStatus> _pendingIntent = <String, DownloadStatus>{};

  @override
  ValueListenable<int> get revision => _local.revision;

  @override
  bool get isWaitingForWifi => _waitingForWifi;

  bool get _useNative => DownloadNativeDataSource.isSupported;

  // --- lifecycle -----------------------------------------------------------

  @override
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    await _storage.initialize(preferredBase: _hive.getDownloadLocation());

    // A held queue has to start itself. Without these, turning the setting off
    // or walking back into Wi-Fi left downloads sitting there until something
    // else happened to pump the queue — which for most people is never.
    _hive.downloadWifiOnlyChanged.addListener(_pump);
    _connectivity = Connectivity().onConnectivityChanged.listen((_) => _pump());

    if (_useNative) {
      _nativePoll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_syncNative()),
      );
    }

    await verifyAll();
  }

  void dispose() {
    _connectivity?.cancel();
    _hive.downloadWifiOnlyChanged.removeListener(_pump);
    _nativePoll?.cancel();
    _cooldownTimer?.cancel();
    _transfer.dispose();
  }

  // --- reads ---------------------------------------------------------------

  @override
  List<DownloadItem> items() => _local.all();

  @override
  DownloadItem? byId(String id) => _local.get(id);

  @override
  String? absolutePathOf(DownloadItem item) {
    if (!_storage.isReady) return null;
    final path = _storage.absoluteOf(item.relativePath);
    if (path.isEmpty) return null;
    // Checked, not assumed. This is the call the "File not found" toast came
    // from, and it is the last place that can still answer honestly.
    final exists = item.artefactIsDirectory
        ? Directory(path).existsSync()
        : File(path).existsSync();
    return exists ? path : null;
  }

  @override
  String? thumbnailPathOf(DownloadItem item) {
    final relative = item.thumbnailRelativePath;
    if (relative == null || !_storage.isReady) return null;
    final path = _storage.absoluteOf(relative);
    return File(path).existsSync() ? path : null;
  }

  // --- enqueue -------------------------------------------------------------

  @override
  Future<EnqueueOutcome> enqueue(DownloadRequest request) async {
    await initialize();

    final existing = _local.get(request.id);
    if (existing != null &&
        (existing.status.isActive ||
            existing.status == DownloadStatus.completed) &&
        !_isStale(existing)) {
      return EnqueueOutcome.alreadyPresent;
    }
    if (_running.contains(request.id) || _queue.contains(request.id)) {
      return EnqueueOutcome.alreadyPresent;
    }

    final kind =
        request.kind ?? DownloadKind.fromLegacy('video', request.sourceUrl);

    if (kind != DownloadKind.manga && request.sourceUrl.trim().isEmpty) {
      return EnqueueOutcome.notDownloadable;
    }

    // Refuse before anything is written rather than after a gigabyte. The
    // margin is deliberate: finishing a download onto a device with nothing
    // left breaks the rest of the app, not just this feature.
    if (!await _hasHeadroom()) return EnqueueOutcome.noSpace;

    final item = DownloadItem(
      id: request.id,
      contentUrl: request.contentUrl,
      provider: request.provider,
      title: request.title,
      videoHeight: request.videoHeight,
      sourceUrl: request.sourceUrl,
      kind: kind,
      relativePath: DownloadLayout.artefactFor(
        request.id,
        kind: kind,
        extension: DownloadLayout.videoExtensionFor(request.sourceUrl),
      ),
      thumbnailUrl: request.thumbnailUrl,
      headers: request.headers,
      status: DownloadStatus.pending,
      unit: DownloadUnit.forKind(kind),
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      isSerial: request.isSerial,
      episodeNumber: request.episodeNumber,
      episodeLabel: request.episodeLabel,
      pageUrls: request.pageUrls,
      imageHeaders: request.imageHeaders,
      chapterRef: request.chapterRef,
      chapterIndex: request.chapterIndex,
    );

    // Persisted as pending BEFORE it starts, so it appears in the list the
    // moment it is accepted. A queued download that stays invisible until a
    // slot frees looks like a button that did nothing.
    await _local.put(item);
    _queue.add(item.id);
    _pump();
    return EnqueueOutcome.started;
  }

  /// A `completed` row whose file is gone is not a reason to refuse a new
  /// download of the same thing — it is the reason for one.
  bool _isStale(DownloadItem item) =>
      item.status == DownloadStatus.completed && absolutePathOf(item) == null;

  // --- controls ------------------------------------------------------------

  @override
  Future<void> pause(String id) async {
    _queue.remove(id);
    _tokens.remove(id)?.cancel('paused');
    // On Android the transfer does not run in this isolate at all — cancelling
    // the token above stops nothing there, which is why pausing used to write
    // `paused` into Hive while the notification carried on counting up.
    if (_useNative) {
      _pendingIntent[id] = DownloadStatus.paused;
      await _native.pause(id);
    }

    final item = _local.get(id);
    if (item == null || item.status == DownloadStatus.completed) return;
    await _local.put(_stamp(item.copyWith(status: DownloadStatus.paused)));
  }

  @override
  Future<void> resume(String id) async {
    final item = _local.get(id);
    if (item == null || item.status == DownloadStatus.completed) return;
    await _requeue(item, resetAttempts: false);
  }

  @override
  Future<void> retry(String id) async {
    final item = _local.get(id);
    if (item == null) return;
    await _requeue(item, resetAttempts: true);
  }

  Future<void> _requeue(
    DownloadItem item, {
    required bool resetAttempts,
  }) async {
    if (_running.contains(item.id) || _queue.contains(item.id)) return;
    // Whatever the viewer asked for a moment ago, they are asking for this now.
    _pendingIntent.remove(item.id);
    await _local.put(
      _stamp(
        item.copyWith(
          status: DownloadStatus.pending,
          failure: null,
          failureDetail: '',
          attempts: resetAttempts ? 0 : item.attempts,
        ),
      ),
    );
    _queue.add(item.id);
    _pump();
  }

  @override
  Future<void> cancel(String id) async {
    _queue.remove(id);
    _tokens.remove(id)?.cancel('cancelled');
    if (_useNative) {
      _pendingIntent[id] = DownloadStatus.failed;
      await _native.cancel(id);
    }
    final item = _local.get(id);
    if (item == null) return;
    await _storage.deleteItem(id);
    await _local.put(
      _stamp(
        item.copyWith(
          status: DownloadStatus.failed,
          failure: DownloadFailureKind.unknown,
          failureDetail: 'cancelled',
          completedUnits: 0,
          sizeBytes: 0,
        ),
      ),
    );
  }

  @override
  Future<void> remove(String id) async {
    _queue.remove(id);
    _tokens.remove(id)?.cancel('removed');
    if (_useNative) {
      await _native.cancel(id);
      await _native.forget(id);
    }
    await _storage.deleteItem(id);
    await _local.delete(id);
    await _subtitles?.delete(id);
  }

  @override
  Future<void> removeAll(Iterable<String> ids) async {
    final list = ids.toList();
    for (final id in list) {
      _queue.remove(id);
      _tokens.remove(id)?.cancel('removed');
      if (_useNative) {
        await _native.cancel(id);
        await _native.forget(id);
      }
      await _storage.deleteItem(id);
      await _subtitles?.delete(id);
    }
    await _local.deleteAll(list);
  }

  @override
  Future<void> clearAll() async {
    _queue.clear();
    for (final token in _tokens.values) {
      token.cancel('cleared');
    }
    _tokens.clear();
    if (_useNative) await _native.cancelAll();
    await _storage.deleteEverything();
    await _local.clear();
  }

  @override
  Future<void> resumeInterrupted() async {
    await initialize();
    for (final item in _local.all()) {
      // `pending` is included because the app can be killed with items still
      // queued, and those never started at all. `paused` is excluded on
      // purpose: that state was chosen by the viewer, and a restart is not
      // consent to resume.
      if (item.status.isActive) {
        await _requeue(item, resetAttempts: false);
      }
    }
  }

  // --- the queue -----------------------------------------------------------

  void _pump() {
    if (_hive.downloadWifiOnly) {
      unawaited(_pumpWhenAllowed());
      return;
    }
    if (_waitingForWifi) {
      _waitingForWifi = false;
      _local.touch();
    }
    _pumpNow();
  }

  Future<void> _pumpWhenAllowed() async {
    if (!await _networkAllows()) {
      // Held, not failed. The items stay queued and start on their own when
      // the setting changes or Wi-Fi comes back; reporting an error here would
      // mean starting each one again by hand.
      if (!_waitingForWifi) {
        _waitingForWifi = true;
        _local.touch();
      }
      return;
    }
    if (_waitingForWifi) {
      _waitingForWifi = false;
      _local.touch();
    }
    _pumpNow();
  }

  void _pumpNow() {
    // A gap between one file and the next, when one has been asked for.
    //
    // Some hosts count requests rather than bytes and hand a temporary block
    // to a client that opens six connections back to back — which looks, from
    // inside the app, like the source suddenly breaking. Zero is the default
    // and skips this entirely: the queue starts the next item the instant a
    // slot frees, which is what everybody who is not being rate-limited wants.
    final cooldown = _hive.downloadCooldownSeconds;
    if (cooldown > 0 && _cooldownUntil != null) {
      final left = _cooldownUntil!.difference(DateTime.now());
      if (!left.isNegative) {
        // Rescheduled rather than dropped: this is the only thing that will
        // restart the queue, since nothing else is going to fire.
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(left, _pump);
        return;
      }
      _cooldownUntil = null;
    }
    while (_running.length < maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final item = _local.get(id);
      if (item == null) continue;
      _running.add(id);
      unawaited(
        _start(item).whenComplete(() {
          _running.remove(id);
          // Measured from the finish, not the start: the point is the gap
          // between requests, and a long file has already provided one.
          final wait = _hive.downloadCooldownSeconds;
          if (wait > 0 && _queue.isNotEmpty) {
            _cooldownUntil = DateTime.now().add(Duration(seconds: wait));
          }
          // Draining from here rather than from a timer means the next item
          // starts the instant a slot frees.
          _pump();
        }),
      );
    }
  }

  /// When the queue may start another file. Null when nothing is waiting.
  DateTime? _cooldownUntil;
  Timer? _cooldownTimer;

  Future<bool> _networkAllows() async {
    if (!_hive.downloadWifiOnly) return true;
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet) ||
          result.contains(ConnectivityResult.vpn);
    } catch (e) {
      // An unknown answer counts as allowed. The plugin fails to report on
      // some devices, and refusing on that basis is a queue that silently
      // never starts — far worse than a download somebody did not expect,
      // because nothing on screen explains it.
      debugPrint('[downloads] could not read connectivity: $e');
      return true;
    }
  }

  // --- running one download ------------------------------------------------

  Future<void> _start(DownloadItem item) async {
    var current = _stamp(item.copyWith(status: DownloadStatus.downloading));
    current = await _resolveMangaPages(current);
    current = await _cacheThumbnail(current);
    await _local.put(current, notify: true);

    // A novel chapter stays in-process even on Android.
    //
    // The native downloader takes a url or a list of page urls and knows
    // nothing about prose — a chapter would reach it with an empty page list
    // and fail. Teaching it the shape would be a foreground service, a progress
    // notification and a second HTML rewriter, for a document and a handful of
    // pictures that finish in about as long as the notification takes to
    // appear. The in-process transfer already does exactly this.
    if (_useNative && !current.isProse) {
      await _startNative(current);
      return;
    }
    await _startInProcess(current);
  }

  Future<void> _startNative(DownloadItem item) async {
    // Asked for, not required. Declining the Android 13 prompt used to stop
    // the download entirely, with nothing on screen saying why.
    unawaited(_native.requestNotificationPermission());

    await _storage.ensureDir(item.id);
    final started = await _native.start(
      id: item.id,
      title: item.title,
      url: item.sourceUrl,
      artefactPath: _storage.absoluteOf(item.relativePath),
      headers: item.headers,
      kind: item.kind.id,
      pageUrls: item.pageUrls,
      imageHeaders: item.imageHeaders,
      wifiOnly: _hive.downloadWifiOnly,
    );
    if (!started) {
      await _fail(
        item,
        DownloadFailureKind.unknown,
        'the system refused to start the download',
      );
      return;
    }
    await _syncNative();
  }

  Future<void> _startInProcess(DownloadItem item) async {
    final cancel = CancelToken();
    _tokens[item.id] = cancel;
    await _acquireWakelock();

    var latest = item;
    // The transfer reports every received chunk — dozens a second on a fast
    // link — and each report used to be a JSON encode of the whole row and a
    // Hive write. Twice a second is as often as anyone can read a percentage;
    // the final figures are written by _complete / _fail regardless.
    final sincePersist = Stopwatch()..start();
    try {
      final dir = await _storage.ensureDir(item.id);
      final result = await _transfer.run(
        id: item.id,
        dirPath: dir.path,
        kind: item.kind,
        sourceUrl: item.sourceUrl,
        headers: item.headers,
        pageUrls: item.pageUrls,
        chapterHtml: item.chapterHtml,
        imageHeaders: item.imageHeaders,
        cancel: cancel,
        onProgress: (p) {
          latest = latest.copyWith(
            completedUnits: p.completedUnits,
            totalUnits: p.totalUnits,
            sizeBytes: p.sizeBytes,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          final done = p.totalUnits > 0 && p.completedUnits >= p.totalUnits;
          if (!done && sincePersist.elapsedMilliseconds < 500) return;
          sincePersist.reset();
          unawaited(_local.put(latest, notify: true));
        },
      );

      if (cancel.isCancelled) return;

      if (!result.ok) {
        await _fail(latest, result.failure!, result.detail);
        return;
      }
      await _complete(
        latest,
        artefactPath: result.artefactPath,
        completedUnits: result.completedUnits,
        totalUnits: result.totalUnits,
        sizeBytes: result.sizeBytes,
      );
    } catch (e) {
      if (!cancel.isCancelled) {
        await _fail(latest, DownloadFailureKind.classify('$e'), '$e');
      }
    } finally {
      _tokens.remove(item.id);
      await _releaseWakelock();
    }
  }

  /// Writes the finished row — but only after checking the artefact is there.
  ///
  /// The check is the whole point. Every earlier version wrote `completed` on
  /// the strength of the transfer having returned, and a transfer can return
  /// from a dozen places without a file behind it.
  Future<void> _complete(
    DownloadItem item, {
    required String artefactPath,
    required int completedUnits,
    required int totalUnits,
    required int sizeBytes,
  }) async {
    final relative = _relativeOf(artefactPath, item);
    final verified = item.copyWith(
      relativePath: relative,
      completedUnits: completedUnits,
      totalUnits: totalUnits,
      sizeBytes: sizeBytes > 0 ? sizeBytes : await _storage.sizeOf(item.id),
    );

    if (!await _storage.artefactExists(verified)) {
      await _fail(
        verified,
        DownloadFailureKind.incomplete,
        'the download finished with nothing on disk',
      );
      return;
    }

    final done = _stamp(
      verified.copyWith(
        status: DownloadStatus.completed,
        failure: null,
        failureDetail: '',
      ),
    );
    await _local.put(done);
    await _writeSidecar(done);
  }

  Future<void> _writeSidecar(DownloadItem item) =>
      _storage.writeSidecar(item.id, DownloadItemModel.toSidecar(item));

  Future<void> _fail(
    DownloadItem item,
    DownloadFailureKind kind,
    String detail,
  ) async {
    final failed = _stamp(
      item.copyWith(
        status: DownloadStatus.failed,
        failure: kind,
        failureDetail: detail,
        attempts: item.attempts + 1,
      ),
    );
    await _local.put(failed);
    debugPrint('[downloads] ${item.id} failed: ${kind.id} — $detail');

    // A network blip should not cost the episode. A refused or missing link
    // fails identically every time, so those are not retried at all.
    if (failed.canAutoRetry) {
      final delay = Duration(seconds: 5 * (1 << (failed.attempts - 1)));
      Timer(delay, () {
        final still = _local.get(failed.id);
        if (still?.status == DownloadStatus.failed) {
          unawaited(_requeue(still!, resetAttempts: false));
        }
      });
    }
  }

  // --- native reconciliation ----------------------------------------------

  Future<void> _syncNative() async {
    if (!_useNative || !_storage.isReady) return;
    final states = await _native.states();
    if (states.isEmpty) return;

    final updates = <DownloadItem>[];
    for (final state in states) {
      final item = _local.get(state.id);
      if (item == null) continue;

      final reported = switch (state.status) {
        'completed' => DownloadStatus.completed,
        'failed' => DownloadStatus.failed,
        'cancelled' => DownloadStatus.failed,
        'downloading' => DownloadStatus.downloading,
        // The service holds a queue of its own now, so a submitted download is
        // `pending` there until a worker picks it up.
        'pending' => DownloadStatus.pending,
        'paused' => DownloadStatus.paused,
        _ => item.status,
      };

      // A pause the service has not caught up with yet. Its `downloading` is
      // stale by up to one poll, and applying it would undo the tap.
      final intent = _pendingIntent[state.id];
      if (intent != null) {
        if (reported == DownloadStatus.downloading ||
            reported == DownloadStatus.pending) {
          continue;
        }
        // It has stopped; the intent is spent.
        _pendingIntent.remove(state.id);
      }
      final status = reported;

      var next = item.copyWith(
        relativePath: state.artefactPath.isEmpty
            ? item.relativePath
            : _relativeOf(state.artefactPath, item),
        completedUnits: state.completedUnits,
        totalUnits: state.totalUnits,
        sizeBytes: state.sizeBytes > 0 ? state.sizeBytes : item.sizeBytes,
      );

      if (status == DownloadStatus.completed) {
        // The service says it finished. Believe the filesystem instead: a
        // completion that cannot be opened is the exact failure this whole
        // change is about, and it is cheaper to catch here than to let a
        // viewer find it on a plane.
        if (await _storage.artefactExists(next)) {
          next = next.copyWith(
            status: DownloadStatus.completed,
            failure: null,
            failureDetail: '',
            sizeBytes: next.sizeBytes > 0
                ? next.sizeBytes
                : await _storage.sizeOf(next.id),
          );
        } else {
          // `missing`, not `failed`, and the same answer [verifyAll] gives —
          // the two paths must agree or they overwrite each other every two
          // seconds. "The file is gone" is also the truer sentence: nothing
          // failed, the bytes were simply removed from under the row.
          next = next.copyWith(
            status: DownloadStatus.missing,
            failure: DownloadFailureKind.incomplete,
            failureDetail: 'the file is no longer on the device',
          );
          // Drop the service's own record too. Left in place it keeps
          // asserting `completed` on every poll, against a row that has
          // already been corrected.
          unawaited(_native.forget(state.id));
        }
      } else if (status == DownloadStatus.failed) {
        next = next.copyWith(
          status: DownloadStatus.failed,
          failure: DownloadFailureKind.classify(state.error),
          failureDetail: state.error,
        );
      } else {
        next = next.copyWith(status: status);
      }

      if (_differs(item, next)) updates.add(_stamp(next));
    }
    if (updates.isNotEmpty) {
      await _local.putAll(updates);
      for (final item in updates) {
        if (item.status == DownloadStatus.completed) {
          await _writeSidecar(item);
        }
      }
    }
  }

  bool _differs(DownloadItem a, DownloadItem b) =>
      a.status != b.status ||
      a.relativePath != b.relativePath ||
      a.completedUnits != b.completedUnits ||
      a.totalUnits != b.totalUnits ||
      a.sizeBytes != b.sizeBytes ||
      a.failure != b.failure;

  // --- integrity -----------------------------------------------------------

  @override
  Future<void> verifyAll() async {
    if (!_storage.isReady) await _storage.initialize();

    final updates = <DownloadItem>[];
    for (final item in _local.all()) {
      final repaired = await _verify(item);
      if (repaired != null) updates.add(repaired);
    }
    if (updates.isNotEmpty) await _local.putAll(updates);
  }

  /// One row, checked against the filesystem. Returns the corrected row, or
  /// null when nothing needed changing.
  Future<DownloadItem?> _verify(DownloadItem item) async {
    // A transfer in flight owns its own row; checking it mid-write would
    // report a file that is deliberately incomplete.
    if (_running.contains(item.id) ||
        item.status == DownloadStatus.downloading) {
      return null;
    }

    var next = item;
    var changed = false;

    // The migration's loose end: a row whose path came from an older build may
    // name an extension the host never served. The folder knows better.
    if (!await _storage.artefactExists(next)) {
      final repaired = await _storage.repairArtefactPath(next);
      if (repaired != null && repaired != next.relativePath) {
        next = next.copyWith(relativePath: repaired);
        changed = true;
      }
    }

    final onDisk = await _storage.artefactExists(next);
    final whole = onDisk && await _isWhole(next);

    if (item.status == DownloadStatus.completed && !whole) {
      // The row this whole change exists for. Demoted rather than deleted:
      // the title, the poster and the episode are still worth showing, and
      // "missing" renders as one tap to get it back.
      next = next.copyWith(
        status: DownloadStatus.missing,
        failure: DownloadFailureKind.incomplete,
        failureDetail: onDisk
            ? 'the download is incomplete'
            : 'the file is no longer on the device',
      );
      changed = true;
    } else if (item.status == DownloadStatus.missing && whole) {
      // It came back — a restore finished, or an SD card was remounted.
      next = next.copyWith(
        status: DownloadStatus.completed,
        failure: null,
        failureDetail: '',
      );
      changed = true;
    }

    if (next.status == DownloadStatus.completed) {
      final size = await _storage.sizeOf(next.id);
      if (size > 0 && size != next.sizeBytes) {
        next = next.copyWith(sizeBytes: size);
        changed = true;
      }
    }

    final thumb = next.thumbnailRelativePath;
    if (thumb != null && !File(_storage.absoluteOf(thumb)).existsSync()) {
      next = next.copyWith(thumbnailRelativePath: '');
      changed = true;
    }

    return changed ? _stamp(next) : null;
  }

  /// Whether every part of a multi-part download is present.
  ///
  /// Single files are whole by existing and being non-empty — the transfer
  /// only renames the `.part` once the byte count matches. A playlist or a
  /// chapter is whole when the manifest's part count matches what is there;
  /// with no manifest (a download made by an older build) the artefact's
  /// presence is all there is to go on, which is what the old code assumed for
  /// everything.
  Future<bool> _isWhole(DownloadItem item) async {
    if (!item.kind.isMultiPart) return true;

    final manifest = File(
      '${_storage.dirOf(item.id)}/'
      '${DownloadLayout.manifestName}',
    );
    if (!await manifest.exists()) return true;

    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map) return true;
      final expected = (decoded['parts'] as num?)?.toInt() ?? 0;
      if (expected <= 0) return true;

      final prefix = item.kind == DownloadKind.hls ? 'seg_' : 'p_';
      var found = 0;
      await for (final entity in Directory(
        _storage.dirOf(item.id),
      ).list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        if (await entity.length() <= 0) continue;
        found++;
      }
      return found >= expected;
    } catch (e) {
      debugPrint('[downloads] manifest unreadable for ${item.id}: $e');
      return true;
    }
  }

  // --- relink --------------------------------------------------------------

  @override
  Future<int> relink(List<RelinkMove> moves) async {
    if (!_storage.isReady) {
      await _storage.initialize(preferredBase: _hive.getDownloadLocation());
    }
    var moved = 0;
    for (final move in moves) {
      final from = _local.get(move.from.id);
      if (from == null || _local.get(move.to.id) != null) continue;
      if (_running.contains(from.id) ||
          _queue.contains(from.id) ||
          from.status.isActive) {
        continue;
      }
      // Row first, folder second, old row last: a crash in between leaves a
      // duplicate the verifier marks missing, never a folder no row claims.
      final to = _stamp(
        move.to.copyWith(
          status: from.status,
          sizeBytes: from.sizeBytes,
          relativePath: DownloadLayout.rekeyed(
            from.relativePath,
            from.id,
            move.to.id,
          ),
        ),
      );
      await _local.put(to, notify: false);
      final hadFolder = await Directory(_storage.dirOf(from.id)).exists();
      if (hadFolder && !await _storage.rekey(from.id, to.id)) {
        await _local.delete(to.id);
        continue;
      }
      await _local.delete(from.id);
      if (_useNative) unawaited(_native.forget(from.id));
      if (to.status == DownloadStatus.completed) await _writeSidecar(to);
      moved++;
    }
    _local.touch();
    return moved;
  }

  // --- storage -------------------------------------------------------------

  @override
  Future<StorageUsage> usage() async {
    if (!_storage.isReady) await _storage.initialize();
    final rows = _local.all();
    final known = {for (final r in rows) r.id};
    final orphans = await _storage.orphanIds(known);

    var orphanBytes = 0;
    for (final id in orphans) {
      orphanBytes += await _storage.sizeOf(id);
    }

    return StorageUsage(
      usedBytes: await _storage.totalSize(),
      freeBytes: await _storage.freeBytes(
        () => _native.freeBytes(path: _storage.base),
      ),
      itemCount: rows.length,
      orphanBytes: orphanBytes,
    );
  }

  @override
  Future<int> sweepOrphans() async {
    if (!_storage.isReady) await _storage.initialize();
    final known = {for (final r in _local.all()) r.id};
    final orphans = await _storage.orphanIds(known);
    for (final id in orphans) {
      await _storage.deleteItem(id);
    }
    if (orphans.isNotEmpty) _local.touch();
    return orphans.length;
  }

  /// Refuses to start when the device is nearly full.
  ///
  /// The margin is a flat 300 MB rather than a fraction of the download: the
  /// size is usually unknown before the first response, and filling a phone
  /// completely breaks far more than this feature.
  static const int _headroomBytes = 300 * 1024 * 1024;

  Future<bool> _hasHeadroom() async {
    // The volume the library is ON, not the phone's internal one. With the
    // downloads moved to an SD card, asking about internal storage is asking
    // about the wrong disk.
    final free = await _storage.freeBytes(
      () => _native.freeBytes(path: _storage.base),
    );
    // Zero means the platform did not answer, and refusing on an unknown is a
    // download that never starts with nothing on screen explaining it.
    if (free <= 0) return true;
    return free > _headroomBytes;
  }

  // --- where the library lives ---------------------------------------------

  @override
  Future<List<DownloadLocation>> locations() async {
    if (!_storage.isReady) {
      await _storage.initialize(preferredBase: _hive.getDownloadLocation());
    }
    final fallback = await _storage.defaultBase();

    final raw = await _native.volumes();
    if (raw.isEmpty) {
      // Not Android, or the host has no such method: one place, no choice.
      return [
        DownloadLocation(
          id: 'app',
          path: fallback,
          label: 'app',
          freeBytes: await _storage.freeBytes(
            () => _native.freeBytes(path: fallback),
          ),
          totalBytes: 0,
          isDefault: true,
        ),
      ];
    }
    return [for (final entry in raw) DownloadLocation.fromJson(entry)];
  }

  @override
  Future<MoveLocationOutcome> moveTo(DownloadLocation location) async {
    if (!_storage.isReady) {
      await _storage.initialize(preferredBase: _hive.getDownloadLocation());
    }
    if (location.path == _storage.base) return MoveLocationOutcome.unchanged;

    // Refuse before copying rather than half way through. A move that runs the
    // destination out of space leaves two partial libraries and no way to tell
    // which is which.
    final needed = await _storage.totalSize();
    if (location.freeBytes > 0 &&
        location.freeBytes < needed + _headroomBytes) {
      return MoveLocationOutcome.noSpace;
    }

    // Nothing may be writing while the files move — and everything that was
    // writing has to come back afterwards. Stopping them without remembering
    // them is how a move silently cancelled the season somebody was part-way
    // through.
    final interrupted = <String>{..._queue, ..._running, ..._tokens.keys};
    for (final token in _tokens.values) {
      token.cancel('moving');
    }
    _tokens.clear();
    if (_useNative) await _native.cancelAll();
    _queue.clear();

    final moved = await _storage.moveTo(location.path);
    if (!moved) {
      // The old root is untouched, so the library still plays.
      return MoveLocationOutcome.failed;
    }
    await _hive.setDownloadLocation(location.path);

    // Paths are relative, so nothing in Hive has to change — that is the whole
    // reason this move is a file copy and not a migration.
    await verifyAll();
    for (final id in interrupted) {
      final item = _local.get(id);
      // A finished download that happened to be in the set — the verify above
      // may have completed it — is left alone.
      if (item != null && item.status != DownloadStatus.completed) {
        await _requeue(item, resetAttempts: false);
      }
    }
    _local.touch();
    return MoveLocationOutcome.moved;
  }

  @override
  Future<String?> exportToPublicDownloads(
    String id, {
    void Function(int done, int total)? onProgress,
  }) async {
    final item = _local.get(id);
    if (item == null || item.status != DownloadStatus.completed) return null;
    // A downloaded novel lived in the app and nowhere else — no way to put it
    // on an e-reader, send it to anyone, or keep it once the app is gone. A
    // chapter of prose, unlike an episode of video, is exactly the sort of
    // thing people expect to be able to take with them.
    if (item.isProse) return _exportEpub(item, onProgress: onProgress);
    // A comic chapter is still a folder of pictures, and what to do with that
    // is a different question with a different answer.
    if (item.artefactIsDirectory) return null;
    final path = absolutePathOf(item);
    if (path == null) return null;
    return _native.exportToDownloads(path: path, name: _exportName(item, path));
  }

  /// Every downloaded chapter of [item]'s title, as one book.
  ///
  /// The whole title rather than the one row that was tapped: an EPUB of a
  /// single chapter is a strange object, and somebody who downloaded thirty
  /// chapters and asked to export wants the thirty. They are ordered by chapter
  /// number, which is the only ordering that survives a source re-keying its
  /// list — see [ChapterReadStore] for the same reasoning.
  Future<String?> _exportEpub(
    DownloadItem item, {
    void Function(int done, int total)? onProgress,
  }) async {
    final siblings =
        _local
            .all()
            .where(
              (d) =>
                  d.isProse &&
                  d.status == DownloadStatus.completed &&
                  d.contentUrl == item.contentUrl &&
                  d.provider == item.provider,
            )
            .toList()
          ..sort(
            (a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0),
          );
    if (siblings.isEmpty) return null;

    final chapters = <EpubChapter>[];
    onProgress?.call(0, siblings.length);
    for (final (i, chapter) in siblings.indexed) {
      onProgress?.call(i, siblings.length);
      final dir = Directory(_storage.dirOf(chapter.id));
      final file = File('${dir.path}/${DownloadLayout.chapterHtmlName}');
      if (!await file.exists()) continue;
      final images = <String, Uint8List>{};
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (!name.startsWith('p_')) continue;
          images[name] = await entity.readAsBytes();
        }
      }
      chapters.add(
        EpubChapter(
          title:
              chapter.episodeLabel ??
              'Chapter ${chapter.episodeNumber ?? chapters.length + 1}',
          // Straight off disk: the `src` attributes already name the files
          // beside it, which is exactly what they have to be inside the book.
          html: await file.readAsString(),
          images: images,
        ),
      );
    }
    if (chapters.isEmpty) return null;
    onProgress?.call(siblings.length, siblings.length);

    // Off the UI isolate: zipping a few hundred chapters with their images
    // froze the app for the seconds it took.
    final title = item.title;
    final identifier = 'sozo:${item.provider}:${item.contentUrl}';
    final bytes = await Isolate.run(
      () => EpubBuilder.build(
        title: title,
        chapters: chapters,
        identifier: identifier,
      ),
    );
    // Written into the app's own space first. The exporter copies a path out;
    // it has no way to be handed bytes, and inventing one for this would mean a
    // second platform channel doing what this one already does.
    final staged = File(
      '${(await _storage.ensureDir(item.id)).path}/export.epub',
    );
    await staged.writeAsBytes(bytes, flush: true);
    try {
      return await _native.exportToDownloads(
        path: staged.path,
        name: '${item.title}.epub',
      );
    } finally {
      try {
        await staged.delete();
      } catch (_) {}
    }
  }

  /// `<title>.<ext>`, with the extension taken from what was actually written
  /// — the container is routinely mkv while the source called it mp4.
  String _exportName(DownloadItem item, String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot > 0 && path.length - dot <= 5
        ? path.substring(dot + 1)
        : 'mp4';
    final episode = item.episodeNumber;
    final base = episode == null ? item.title : '${item.title} - E$episode';
    return '$base.$ext';
  }

  @override
  Future<String?> localChapterHtml(String id) async {
    final item = _local.get(id);
    if (item == null ||
        !item.isManga ||
        item.status != DownloadStatus.completed) {
      return null;
    }
    final file = File(
      '${_storage.dirOf(id)}/${DownloadLayout.chapterHtmlName}',
    );
    if (!await file.exists()) return null;
    try {
      final html = await file.readAsString();
      // The `src` attributes were rewritten to bare file names beside the
      // document; the reader is handed a string, not a directory, so they are
      // made absolute here — the one place that knows where the folder is.
      return DownloadTransferDataSource.rewriteImageSources(html, {
        for (final entity in Directory(_storage.dirOf(id)).listSync())
          if (entity is File) entity.uri.pathSegments.last: entity.path,
      });
    } catch (e) {
      debugPrint('[downloads] could not read chapter html for $id: $e');
      return null;
    }
  }

  @override
  Future<List<MangaPageEntity>> localMangaPages(String id) async {
    final item = _local.get(id);
    if (item == null ||
        !item.isManga ||
        item.status != DownloadStatus.completed) {
      return const [];
    }
    final dir = Directory(_storage.dirOf(id));
    if (!await dir.exists()) return const [];

    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.uri.pathSegments.last.startsWith('p_')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return [
      for (var i = 0; i < files.length; i++)
        MangaPageEntity(index: i, imageUrl: files[i].path),
    ];
  }

  // --- helpers -------------------------------------------------------------

  /// Resolves a chapter's pages before the transfer needs them.
  ///
  /// Queued from the episode list, a chapter carries only its ref — the page
  /// urls come from the provider and expire, so they are fetched at the last
  /// possible moment rather than at queue time.
  Future<DownloadItem> _resolveMangaPages(DownloadItem item) async {
    if (!item.isManga) return item;
    if (item.pageUrls.isNotEmpty) return item;
    if ((item.chapterHtml ?? '').isNotEmpty) return item;
    final ref = item.chapterRef;
    if (ref == null || ref.isEmpty) return item;
    try {
      final result = await getIt<GetPagesUseCase>()(
        ref: ref,
        provider: item.provider,
      );
      if (result is Success<MangaPagesEntity>) {
        // A novel chapter is one document rather than a list of images. It used
        // to arrive here as zero pages, and the transfer failed the whole
        // download with "the chapter has no pages" — so a novel could not be
        // saved for offline at all, on a shelf the app has a reader for.
        if (result.value.isText) {
          return item.copyWith(
            chapterHtml: result.value.html,
            headers: result.value.headers.isEmpty
                ? item.headers
                : result.value.headers,
          );
        }
        return item.copyWith(
          pageUrls: result.value.pages.map((p) => p.imageUrl).toList(),
          imageHeaders: result.value.pages
              .map(
                (p) => <String, String>{
                  ...p.headers,
                  if (p.cookie != null) 'Cookie': p.cookie!,
                },
              )
              .toList(),
          headers: result.value.headers.isEmpty
              ? item.headers
              : result.value.headers,
        );
      }
    } catch (e) {
      debugPrint('[downloads] could not resolve pages for ${item.id}: $e');
    }
    return item;
  }

  /// Keeps the poster so the list still draws with no connection.
  ///
  /// Best-effort by design: a missing thumbnail costs a grey rectangle, and
  /// failing the download over one would be absurd.
  Future<DownloadItem> _cacheThumbnail(DownloadItem item) async {
    final url = item.thumbnailUrl?.trim();
    if (url == null || url.isEmpty) return item;
    if (thumbnailPathOf(item) != null) return item;

    final extension = DownloadLayout.imageExtensionFor(url);
    final relative = DownloadLayout.thumbnailFor(item.id, extension);
    final absolute = _storage.absoluteOf(relative);
    try {
      await _storage.ensureDir(item.id);
      // The video's headers — a Referer, often a cookie or a token — belong to
      // the video's host. A poster usually sits on a different CDN, and handing
      // it the stream's credentials is a leak with nothing gained.
      final sameHost =
          Uri.tryParse(url)?.host.toLowerCase() ==
          Uri.tryParse(item.sourceUrl)?.host.toLowerCase();
      final response = await ExternalDio.instance.get<List<int>>(
        url,
        options: Options(
          headers: sameHost && item.headers.isNotEmpty ? item.headers : null,
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return item;
      await File(absolute).writeAsBytes(bytes, flush: true);
      return item.copyWith(thumbnailRelativePath: relative);
    } catch (e) {
      debugPrint('[downloads] thumbnail not cached for ${item.id}: $e');
      return item;
    }
  }

  /// Turns whatever a transfer engine handed back into something storable.
  ///
  /// An absolute path from the platform describes this launch, not this
  /// download, so it never reaches Hive.
  String _relativeOf(String absolutePath, DownloadItem item) =>
      DownloadLayout.relativeFromLegacy(absolutePath) ?? item.relativePath;

  DownloadItem _stamp(DownloadItem item) =>
      item.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);

  /// Counts transfers, and holds ONE shared wakelock for all of them.
  ///
  /// It used to switch WakelockPlus off when the last transfer ended, which
  /// also switched off the player's — the screen then slept under a video
  /// because a download finished. See [WakelockHolds].
  Future<void> _acquireWakelock() async {
    _wakelocks++;
    if (_wakelocks == 1) await WakelockHolds.acquire(this);
  }

  Future<void> _releaseWakelock() async {
    _wakelocks--;
    if (_wakelocks <= 0) {
      _wakelocks = 0;
      await WakelockHolds.release(this);
    }
  }
}
