import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/follow_sync_service.dart';
import 'package:soplay/features/tracker/data/release_feed_store.dart';
import 'package:soplay/features/tracker/data/release_inbox.dart';
import 'package:soplay/features/tracker/data/release_worker.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/tracker/domain/follow_coverage.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';

/// Everything about new releases that lives in the app's own isolate.
///
/// It is where a release ends up however it was found — the foreground
/// check, the background worker, a push — and it decides who announces what
/// (FollowCoverage), keeps the feed, and tells the background worker what to
/// watch by writing its snapshot.
class ReleaseWatch with WidgetsBindingObserver {
  ReleaseWatch({
    required this.follows,
    required this.sync,
    required this.feed,
    required this.notifications,
    required bool Function() isSignedIn,
    required int Function() intervalHours,
    required bool Function() adult,
    String? Function(String profileId)? namespaceOf,
    Future<ReleaseInbox> Function()? inbox,
  }) : _isSignedIn = isSignedIn,
       _intervalHours = intervalHours,
       _adult = adult,
       _namespaceOf = namespaceOf,
       _openInbox = inbox ?? ReleaseInbox.open;

  final FollowService follows;
  final FollowSyncService sync;
  final ReleaseFeedStore feed;
  final NotificationService notifications;
  final bool Function() _isSignedIn;
  final int Function() _intervalHours;
  final bool Function() _adult;
  final String? Function(String profileId)? _namespaceOf;
  final Future<ReleaseInbox> Function() _openInbox;

  ReleaseInbox? _inbox;
  Timer? _snapshotDebounce;
  bool _workmanagerReady = false;

  Future<ReleaseInbox> get _box async => _inbox ??= await _openInbox();

  void start() {
    WidgetsBinding.instance.addObserver(this);
    follows.revision.addListener(_scheduleSnapshot);
    sync.revision.addListener(_scheduleSnapshot);
    notifications.prefsStore.revision.addListener(_scheduleSnapshot);
    notifications.onReleasePush = recordPush;
    notifications.onSeenAction = (data) => unawaited(
      markSeen('${data['provider'] ?? ''}', '${data['contentUrl'] ?? ''}'),
    );
    unawaited(drain().then((_) => writeSnapshot()));
    unawaited(scheduleBackground());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(drain());
    if (state == AppLifecycleState.paused) {
      _snapshotDebounce?.cancel();
      unawaited(writeSnapshot());
    }
  }

  // ─── who announces ────────────────────────────────────────────────────────

  bool get signedIn => _isSignedIn();

  /// Whether this device raises the notification for [t].
  bool deviceAnnounces(FollowedTitle t) => FollowCoverage.deviceNotifies(
    t,
    signedIn: signedIn,
    serverLive: sync.serverLive,
    pendingUpload: sync.isPending(t.key),
  );

  // ─── the foreground check ────────────────────────────────────────────────

  Future<int>? _checking;

  /// Checks every followed title now; the Following page's pull-to-refresh
  /// and the foreground scheduler both come here. Calls while one is running
  /// join it.
  Future<int> checkNow({
    void Function(FollowedTitle, List<EpisodeEntity>)? onChecked,
  }) {
    return _checking ??= () async {
      try {
        await drain();
        return await follows.checkForUpdates(
          announce: deviceAnnounces,
          onGrown: recordGrowth,
          onChecked: onChecked,
        );
      } finally {
        unawaited(writeSnapshot());
      }
    }().whenComplete(() => _checking = null);
  }

  Future<void> recordGrowth(FollowGrowth g) async {
    final t = g.title;
    await feed.add(
      ReleaseEntry(
        provider: t.provider,
        contentUrl: t.contentUrl,
        title: t.title,
        thumbnail: t.thumbnail,
        mode: t.mode,
        episode: g.episode,
        fromEpisode: g.fromEpisode,
        label: g.label,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!g.announce) return;
    await notifications.showRelease(
      ReleaseAlert(
        provider: t.provider,
        contentUrl: t.contentUrl,
        title: t.title,
        thumbnail: t.thumbnail,
        mode: t.mode,
        episodeNumber: g.episode,
        episodeLabel: g.label,
        count: g.episode - g.fromEpisode + 1,
      ),
    );
  }

  /// A release push that reached the running app.
  Future<void> recordPush(ReleaseAlert alert, {String? profileId}) =>
      _apply([ReleaseEvent.fromAlert(alert, profileId: profileId)]);

  // ─── the inbox ────────────────────────────────────────────────────────────

  Future<void>? _draining;

  /// Folds in what the background worker and the push handler left behind.
  Future<void> drain() => _draining ??= () async {
    try {
      final inbox = await _box;
      final events = inbox.drain();
      if (events.isNotEmpty) await _apply(events);
    } catch (e) {
      debugPrint('[release-watch] drain failed: $e');
    }
  }().whenComplete(() => _draining = null);

  /// The profile namespace an event belongs to, or null when that profile is
  /// not on this device.
  String? _targetScope(ReleaseEvent e) {
    final scope = e.scope;
    if (scope != null) return scope;
    final id = e.profileId;
    if (id == null || id.isEmpty) return '';
    if (id == ProfileScope.remoteId) return ProfileScope.namespace ?? '';
    return _namespaceOf?.call(id);
  }

  Future<void> _apply(List<ReleaseEvent> events) async {
    final active = ProfileScope.namespace ?? '';
    final counts = <String, ({int count, String? label})>{};
    for (final e in events) {
      // A seen mark comes from a notification on this screen, which is the
      // active profile's.
      if (e.kind == ReleaseEventKind.seen) {
        await markSeen(e.provider, e.contentUrl);
        continue;
      }
      final scope = _targetScope(e);
      if (scope == null) continue;
      if (e.episode <= 0) continue;
      if (scope == active) {
        final prev = counts[e.key];
        if (prev == null || e.episode > prev.count) {
          counts[e.key] = (count: e.episode, label: e.label);
        }
      }
      if (e.seedOnly) continue;
      final known = scope == active ? follows.get(e.contentUrl) : null;
      await feed.add(
        ReleaseEntry(
          provider: e.provider,
          contentUrl: e.contentUrl,
          title: e.title.isNotEmpty ? e.title : (known?.title ?? ''),
          thumbnail: e.thumbnail.isNotEmpty ? e.thumbnail : (known?.thumbnail ?? ''),
          mode: e.mode,
          episode: e.episode,
          fromEpisode: e.fromEpisode > 0 ? e.fromEpisode : e.episode,
          label: e.label,
          at: e.at > 0 ? e.at : DateTime.now().millisecondsSinceEpoch,
        ),
        scope: scope == active ? null : scope,
      );
    }
    // The server already knows what it pushed, and the worker's finds are
    // told to it by the check that follows; neither needs a PATCH of its own.
    await follows.raiseCounts(counts, tellServer: false);
  }

  // ─── seen ─────────────────────────────────────────────────────────────────

  /// The title was opened, or "Mark seen" was pressed.
  ///
  /// The count the user has now seen goes to the server, so it does not push
  /// the same episodes again from another device's point of view.
  Future<void> markSeen(String provider, String contentUrl) async {
    final key = FollowedTitle.keyOf(provider, contentUrl);
    final entry = feed.entries().where((e) => e.key == key).firstOrNull;
    await feed.markSeen(key);
    await notifications.clearRelease(provider, contentUrl);
    final t = follows.get(contentUrl);
    if (t != null && entry != null && entry.episode > t.lastEpisodeCount) {
      await follows.raiseCounts({key: (count: entry.episode, label: entry.label)});
    } else if (t != null && t.lastEpisodeCount > 0 && entry != null && !entry.seen) {
      sync.patched(t, lastEpisodeCount: t.lastEpisodeCount);
    }
  }

  Future<void> markOpened(String contentUrl) async {
    final unseen = feed.unseenFor(contentUrl);
    if (unseen == null) return;
    await markSeen(unseen.provider, unseen.contentUrl);
  }

  // ─── the background worker ────────────────────────────────────────────────

  void _scheduleSnapshot() {
    _snapshotDebounce?.cancel();
    _snapshotDebounce = Timer(const Duration(seconds: 2), () => unawaited(writeSnapshot()));
  }

  /// Rewrites what the background worker checks. Called after any change to
  /// follows, switches, the account or the language.
  Future<void> writeSnapshot() async {
    try {
      final signed = signedIn;
      final live = sync.serverLive;
      final titles = [
        for (final t in follows.list())
          if (FollowCoverage.deviceChecks(t, signedIn: signed, serverLive: live))
            WatchedTitle.of(t, notify: deviceAnnounces(t)),
      ];
      final inbox = await _box;
      await inbox.writeSnapshot(
        ReleaseWatchSnapshot(
          titles: titles,
          prefs: notifications.prefs,
          labels: notifications.labels(),
          adult: _adult(),
          writtenAt: DateTime.now().millisecondsSinceEpoch,
          scope: ProfileScope.namespace ?? '',
        ),
      );
    } catch (e) {
      debugPrint('[release-watch] snapshot failed: $e');
    }
  }

  /// Registers — or, when the check is switched off, cancels — the periodic
  /// background check. Android only: iOS has no equivalent that runs this
  /// often, and gets the foreground check and pushes.
  Future<void> scheduleBackground() async {
    if (!Platform.isAndroid) return;
    try {
      final wm = Workmanager();
      if (!_workmanagerReady) {
        await wm.initialize(releaseWatchDispatcher);
        _workmanagerReady = true;
      }
      final hours = _intervalHours();
      if (hours <= 0) {
        await wm.cancelByUniqueName(releaseWatchTask);
        return;
      }
      await wm.registerPeriodicTask(
        releaseWatchTask,
        releaseWatchTask,
        frequency: Duration(hours: math.max(4, hours)),
        initialDelay: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      debugPrint('[release-watch] schedule failed: $e');
    }
  }

  /// A profile switch: the feed and the snapshot now mean another person.
  void onProfileChanged() {
    feed.revision.value++;
    _scheduleSnapshot();
  }
}
