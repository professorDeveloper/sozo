import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/automation/data/automation_settings.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/download_request_builder.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

class _Candidate {
  const _Candidate({
    required this.id,
    required this.title,
    required this.episode,
    required this.isReader,
  });

  final String id;
  final DownloadTitle title;
  final EpisodeEntity episode;
  final bool isReader;
}

/// Downloads new episodes of followed titles by themselves, and cleans up
/// after them.
///
/// Fed by the library update check, so it runs when the app is open or comes
/// back to the foreground, like the check itself.
///
/// Episodes are resolved one at a time and only once the download queue has
/// nothing waiting: a signed stream URL resolved now and started an hour later,
/// when Wi-Fi or a free slot finally arrived, is a 403. Resolving one at a time
/// also keeps a provider from rate-limiting a burst of resolves.
class AutoDownloadService {
  AutoDownloadService({
    required this.settings,
    required this.downloads,
    required this.builder,
    required bool Function(String provider) isReader,
    required bool Function(DownloadItem item) isWatched,
    Future<bool> Function()? unmeteredNetwork,
    Future<void> Function(int queued)? notify,
    DateTime Function()? now,
    this.queueWait = const Duration(minutes: 30),
  }) : _isReader = isReader,
       _isWatched = isWatched,
       _unmetered = unmeteredNetwork ?? _onUnmeteredNetwork,
       _notify = notify,
       _now = now ?? DateTime.now;

  final AutomationSettings settings;
  final DownloadRepository downloads;
  final DownloadRequestBuilder builder;
  final Duration queueWait;
  final bool Function(String provider) _isReader;
  final bool Function(DownloadItem item) _isWatched;
  final Future<bool> Function() _unmetered;
  final Future<void> Function(int queued)? _notify;
  final DateTime Function() _now;

  final Map<String, _Candidate> _pending = {};
  Future<AutoDownloadStatus?>? _draining;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _pruneTimer;

  @visibleForTesting
  List<String> get pendingIds => _pending.keys.toList();

  /// Picks up a run that was holding for Wi-Fi as soon as Wi-Fi arrives.
  void start() {
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((result) {
        if (_pending.isEmpty || !_isUnmetered(result)) return;
        unawaited(drain());
      });
    } catch (e) {
      debugPrint('[auto-download] no connectivity stream: $e');
    }
  }

  void dispose() {
    _connectivity?.cancel();
    _pruneTimer?.cancel();
  }

  /// Notes what [title] should have on disk, given the [episodes] a check
  /// returned. Nothing is fetched until [drain].
  ///
  /// Only episodes the check actually returned: a source's list is capped at
  /// a hundred rows, so a new episode outside that page is announced but
  /// cannot be downloaded from here.
  void collect(FollowedTitle title, List<EpisodeEntity> episodes) {
    if (!settings.autoDownloadEnabled || !title.autoDownload) return;
    final floor = title.autoDownloadFrom;
    if (floor <= 0) return;

    final newest = <int, EpisodeEntity>{};
    for (final e in episodes) {
      if (e.episode <= floor || e.mediaRef.isEmpty) continue;
      newest.putIfAbsent(e.episode, () => e);
    }
    final wanted = newest.values.toList()
      ..sort((a, b) => b.episode.compareTo(a.episode));

    final reader = _isReader(title.provider);
    final target = DownloadTitle(
      contentUrl: title.contentUrl,
      provider: title.provider,
      title: title.title,
      thumbnail: title.thumbnail.isEmpty ? null : title.thumbnail,
    );
    final handled = {...settings.autoIds, ...settings.skippedIds};
    // Oldest first, so a run cut short by Wi-Fi or the cap keeps the order
    // the viewer will watch in.
    for (final e in wanted.take(settings.keepLast).toList().reversed) {
      final id = reader
          ? DownloadRequest.mangaChapterId(
              contentUrl: title.contentUrl,
              provider: title.provider,
              chapterRef: e.mediaRef,
            )
          : DownloadRequest.videoId(
              contentUrl: title.contentUrl,
              episodeNumber: e.episode,
            );
      if (handled.contains(id) || downloads.byId(id) != null) continue;
      _pending[id] = _Candidate(
        id: id,
        title: target,
        episode: e,
        isReader: reader,
      );
    }
  }

  /// Cleans up, then downloads what [collect] noted. Never throws.
  Future<void> afterCheck() async {
    try {
      await prune();
      await drain();
    } catch (e) {
      debugPrint('[auto-download] run failed: $e');
    }
  }

  /// Downloads what is pending. Calls while one is running join it.
  Future<AutoDownloadStatus?> drain() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  Future<AutoDownloadStatus?> _drain() async {
    if (_pending.isEmpty) return null;
    var queued = 0;
    var skipped = 0;
    var hold = AutoDownloadHold.none;

    while (_pending.isNotEmpty) {
      if (!settings.autoDownloadEnabled) {
        _pending.clear();
        break;
      }
      if (settings.autoDownloadWifiOnly && !await _unmetered()) {
        hold = AutoDownloadHold.wifi;
        break;
      }
      if (!await _waitForQueueRoom()) {
        hold = AutoDownloadHold.busy;
        break;
      }
      if (await _overCap()) {
        hold = AutoDownloadHold.storageCap;
        break;
      }

      final c = _pending.values.first;
      _pending.remove(c.id);
      if (downloads.byId(c.id) != null) continue;

      final built = c.isReader
          ? await builder.chapter(
              c.title,
              c.episode,
              // The run position the episode list would store, for a source
              // that numbers from 1.
              chapterIndex: c.episode.episode > 0
                  ? c.episode.episode - 1
                  : null,
            )
          : await builder.quietVideo(c.title, c.episode);
      final request = built.request;
      if (request == null) {
        // A failed resolve is tried again on the next check; an embed page
        // will be an embed page next time too.
        if (built.failure == DownloadBuildFailure.needsPlayback) {
          skipped++;
          await settings.rememberSkipped(c.id);
        }
        continue;
      }

      final outcome = await downloads.enqueue(request);
      switch (outcome) {
        case EnqueueOutcome.started:
          queued++;
          await settings.rememberAuto(c.id);
        case EnqueueOutcome.notDownloadable:
          skipped++;
          await settings.rememberSkipped(c.id);
        case EnqueueOutcome.noSpace:
          hold = AutoDownloadHold.storageCap;
        case EnqueueOutcome.alreadyPresent:
        case EnqueueOutcome.refused:
          break;
      }
      if (hold != AutoDownloadHold.none) break;
    }

    final status = AutoDownloadStatus(
      at: _now(),
      queued: queued,
      skipped: skipped,
      hold: hold,
    );
    await settings.setLastStatus(status);
    final notify = _notify;
    if (queued > 0 && notify != null) {
      try {
        await notify(queued);
      } catch (_) {}
    }
    return status;
  }

  Future<bool> _overCap() async {
    final cap = settings.maxBytes;
    if (cap <= 0) return false;
    try {
      return (await downloads.usage()).usedBytes >= cap;
    } catch (_) {
      return false;
    }
  }

  /// Waits until nothing in the queue is still waiting to start.
  Future<bool> _waitForQueueRoom() async {
    bool room() =>
        !downloads.items().any((i) => i.status == DownloadStatus.pending);
    if (room()) return true;
    final done = Completer<bool>();
    void listener() {
      if (room() && !done.isCompleted) done.complete(true);
    }

    downloads.revision.addListener(listener);
    try {
      return await done.future.timeout(queueWait, onTimeout: () => false);
    } finally {
      downloads.revision.removeListener(listener);
    }
  }

  /// Deletes automatic downloads that were watched (when asked to) and those
  /// beyond the newest [AutomationSettings.keepLast] of each title.
  ///
  /// Only ever touches what [drain] downloaded, and only finished files.
  Future<int> prune() async {
    final auto = settings.autoIds.toSet();
    if (auto.isEmpty) return 0;
    final mine = downloads
        .items()
        .where((i) => auto.contains(i.id) && i.status.isPlayable)
        .toList();
    if (mine.isEmpty) return 0;

    final remove = <String>{};
    if (settings.autoDeleteWatched) {
      for (final item in mine) {
        if (_isWatched(item)) remove.add(item.id);
      }
    }
    if (settings.autoDownloadEnabled) {
      final keep = settings.keepLast;
      final byTitle = <String, List<DownloadItem>>{};
      for (final item in mine) {
        if (remove.contains(item.id)) continue;
        byTitle.putIfAbsent(item.groupKey, () => []).add(item);
      }
      for (final items in byTitle.values) {
        items.sort(
          (a, b) => (b.episodeNumber ?? 0).compareTo(a.episodeNumber ?? 0),
        );
        for (final old in items.skip(keep)) {
          remove.add(old.id);
        }
      }
    }
    if (remove.isEmpty) return 0;
    await downloads.removeAll(remove);
    return remove.length;
  }

  /// A prune shortly after playback ends, once the history row is written.
  void pruneSoon() {
    if (!settings.autoDeleteWatched) return;
    _pruneTimer?.cancel();
    _pruneTimer = Timer(const Duration(seconds: 5), () {
      prune().catchError((Object e) {
        debugPrint('[auto-download] prune failed: $e');
        return 0;
      });
    });
  }

  static bool _isUnmetered(List<ConnectivityResult> result) =>
      result.contains(ConnectivityResult.wifi) ||
      result.contains(ConnectivityResult.ethernet);

  /// Unlike the download queue, an unknown answer is not Wi-Fi: this runs
  /// unasked, and data the viewer did not agree to spend is the worse mistake.
  static Future<bool> _onUnmeteredNetwork() async {
    try {
      return _isUnmetered(await Connectivity().checkConnectivity());
    } catch (_) {
      return false;
    }
  }
}
