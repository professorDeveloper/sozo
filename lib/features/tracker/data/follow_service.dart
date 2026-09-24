import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/tracker/domain/follow_coverage.dart';

/// Where follow changes go besides this device — the account, when there is
/// one. See FollowSyncService.
abstract class FollowChangeSink {
  void followed(FollowedTitle title);
  void unfollowed(FollowedTitle title);
  void patched(FollowedTitle title, {bool? notify, int? lastEpisodeCount});
}

/// A title the check found grown, from [fromEpisode] to [episode].
typedef FollowGrowth = ({
  FollowedTitle title,
  int fromEpisode,
  int episode,
  String? label,
  bool announce,
});

/// Follow serials and detect new episodes. The update check reuses the same
/// freeze-proof pattern as cross-search: bounded concurrency + per-title
/// timeout, so it never hangs no matter how many titles are followed.
class FollowService {
  FollowService({
    required this.hive,
    required this.getEpisodes,
    required this.notifications,
  });

  final HiveService hive;
  final GetEpisodesUseCase getEpisodes;
  final NotificationService notifications;

  FollowChangeSink? sink;

  /// Bumped on every write, so lists and buttons can follow along.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<FollowedTitle> list() =>
      hive.getFollowedRaw().map(FollowedTitle.fromJson).toList();

  bool isFollowed(String contentUrl) =>
      hive.getFollowedRaw().any((e) => e['contentUrl'] == contentUrl);

  FollowedTitle? get(String contentUrl) {
    for (final e in hive.getFollowedRaw()) {
      if (e['contentUrl'] == contentUrl) return FollowedTitle.fromJson(e);
    }
    return null;
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    await hive.setFollowedRaw(items);
    revision.value++;
  }

  Future<void> follow(FollowedTitle title) async {
    final items = hive.getFollowedRaw();
    if (items.any((e) => e['contentUrl'] == title.contentUrl)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stamped = title.copyWith(updatedAt: now);
    items.insert(0, stamped.toJson());
    await _save(items);
    sink?.followed(stamped);
  }

  Future<void> unfollow(String contentUrl) async {
    final items = hive.getFollowedRaw();
    final gone = [
      for (final e in items)
        if (e['contentUrl'] == contentUrl) FollowedTitle.fromJson(e),
    ];
    items.removeWhere((e) => e['contentUrl'] == contentUrl);
    await _save(items);
    for (final t in gone) {
      sink?.unfollowed(t);
    }
  }

  /// Mutes or unmutes one title. It stays followed either way.
  Future<void> setNotify(String contentUrl, bool on) async {
    final items = hive.getFollowedRaw();
    FollowedTitle? changed;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in items) {
      if (e['contentUrl'] != contentUrl) continue;
      on ? e.remove('notify') : e['notify'] = false;
      e['updatedAt'] = now;
      changed = FollowedTitle.fromJson(e);
    }
    if (changed == null) return;
    await _save(items);
    sink?.patched(changed, notify: on);
  }

  /// Turns automatic downloads on or off for one title.
  Future<void> setAutoDownload(String contentUrl, bool on) async {
    final items = hive.getFollowedRaw();
    for (final e in items) {
      if (e['contentUrl'] != contentUrl) continue;
      if (on) {
        e['autoDownload'] = true;
        final from = (e['autoDownloadFrom'] as num?)?.toInt() ?? 0;
        final last = (e['lastEpisodeCount'] as num?)?.toInt() ?? 0;
        if (from <= 0 && last > 0) e['autoDownloadFrom'] = last;
      } else {
        e.remove('autoDownload');
        e.remove('autoDownloadFrom');
      }
    }
    await _save(items);
  }

  /// Raises known counts from elsewhere — a push, the background check.
  ///
  /// Never lowers one: a count going down is a source re-listing, not news,
  /// and lowering it would announce the same episodes again later.
  Future<void> raiseCounts(
    Map<String, ({int count, String? label})> byKey, {
    bool tellServer = true,
  }) async {
    if (byKey.isEmpty) return;
    final items = hive.getFollowedRaw();
    final raised = <FollowedTitle>[];
    for (final e in items) {
      final t = FollowedTitle.fromJson(e);
      final next = byKey[t.key];
      if (next == null || next.count <= t.lastEpisodeCount) continue;
      e['lastEpisodeCount'] = next.count;
      if (next.label != null) e['lastEpisodeLabel'] = next.label;
      raised.add(FollowedTitle.fromJson(e));
    }
    if (raised.isEmpty) return;
    await _save(items);
    if (!tellServer) return;
    for (final t in raised) {
      sink?.patched(t, lastEpisodeCount: t.lastEpisodeCount);
    }
  }

  /// The account's merged list, taken as this profile's follows.
  ///
  /// What only this device keeps — automatic downloads, the last check — is
  /// carried over, and a count is never lowered by the merge. Follows added
  /// while the sync was in flight ([keepAddedAfter]) survive it.
  Future<void> adoptRemote(
    List<FollowedTitle> remote, {
    int keepAddedAfter = 0,
  }) async {
    final local = {for (final t in list()) t.key: t};
    final merged = <FollowedTitle>[];
    final seen = <String>{};
    for (final r in remote) {
      if (!seen.add(r.key)) continue;
      final l = local[r.key];
      merged.add(
        l == null
            ? r
            : r.copyWith(
                lastEpisodeCount: r.lastEpisodeCount > l.lastEpisodeCount
                    ? r.lastEpisodeCount
                    : l.lastEpisodeCount,
                lastEpisodeLabel: r.lastEpisodeCount >= l.lastEpisodeCount
                    ? r.lastEpisodeLabel
                    : l.lastEpisodeLabel,
                lastCheckedAt: l.lastCheckedAt,
                autoDownload: l.autoDownload,
                autoDownloadFrom: l.autoDownloadFrom,
                thumbnail: r.thumbnail.isEmpty ? l.thumbnail : null,
                anilistId: r.anilistId ?? l.anilistId,
                malId: r.malId ?? l.malId,
                tmdbId: r.tmdbId ?? l.tmdbId,
                tmdbKind: r.tmdbKind ?? l.tmdbKind,
              ),
      );
    }
    for (final l in local.values) {
      if (!seen.contains(l.key) && l.addedAt > keepAddedAfter) merged.add(l);
    }
    merged.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await _save([for (final t in merged) t.toJson()]);
  }

  /// Re-check every followed serial for new episodes. Returns how many grew.
  ///
  /// [announce] decides per title whether this device raises the notification
  /// (the server raises its own for what it covers — see FollowCoverage); a
  /// title it declines is still counted, silently. [onGrown] sees every title
  /// that grew. Without it, the old plain notification is shown.
  ///
  /// [onChecked] sees every title that answered, with the episodes it
  /// returned, which is how automatic downloads find what to fetch.
  ///
  /// Freeze-proof: at most [concurrency] checks run at once, each capped at
  /// [timeout]; counts are persisted in a single write at the end (no races).
  Future<int> checkForUpdates({
    int concurrency = 3,
    Duration timeout = const Duration(seconds: 12),
    bool notify = true,
    bool Function(FollowedTitle title)? announce,
    Future<void> Function(FollowGrowth growth)? onGrown,
    void Function(FollowedTitle title, List<EpisodeEntity> episodes)? onChecked,
  }) async {
    final items = list().where(FollowCoverage.deviceCanCheck).toList();
    if (items.isEmpty) return 0;

    final newCounts = <String, int>{};
    final newLabels = <String, String>{};
    final autoFloors = <String, int>{};
    var index = 0;
    var grown = 0;

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= items.length) return;
        final t = items[i];
        try {
          final res = await getEpisodes(
            t.contentUrl,
            provider: t.provider,
          ).timeout(timeout);
          if (!res.isSuccess) continue;
          final pb = res.getOrNull();
          if (pb == null) continue;
          // The highest number seen, not the number of rows.
          //
          // `pb.total` is 0 for every extension source — `cs:`, `an:`, `mn:`
          // and `my:` all come back through a platform channel that does not
          // fill it — so this fell through to `episodes.length`, and the
          // request is capped at 100 rows. A four-hundred-chapter manga
          // therefore reported 100, every check, forever: it could never grow,
          // so it could never be announced. Worse, a source that starts
          // paginating differently changes the row count without a single new
          // chapter existing, which announces one.
          //
          // The largest chapter number is the thing that only moves when there
          // is genuinely something new. It survives a capped page, an inserted
          // extra, and a source re-keying its list.
          final newest = newestOf(pb.episodes);
          final count = newest?.episode ?? 0;
          if (count <= 0) continue;
          newCounts[t.contentUrl] = count;
          final label = newest?.label.trim();
          if (label != null && label.isNotEmpty) newLabels[t.contentUrl] = label;
          var checked = t;
          if (t.autoDownload && t.autoDownloadFrom <= 0) {
            final floor = t.lastEpisodeCount > 0 ? t.lastEpisodeCount : count;
            autoFloors[t.contentUrl] = floor;
            checked = t.copyWith(autoDownloadFrom: floor);
          }
          if (onChecked != null) {
            try {
              onChecked(checked, pb.episodes);
            } catch (_) {}
          }
          if (t.lastEpisodeCount > 0 && count > t.lastEpisodeCount) {
            final delta = pb.episodes
                .where((e) => e.episode > t.lastEpisodeCount)
                .length;
            grown++;
            final shout = notify && t.notify && (announce?.call(t) ?? true);
            if (onGrown != null) {
              await onGrown((
                title: t,
                fromEpisode: t.lastEpisodeCount + 1,
                episode: count,
                label: newLabels[t.contentUrl],
                announce: shout,
              ));
            } else if (shout) {
              await notifications.showLocalNotification(
                id: t.contentUrl.hashCode & 0x7fffffff,
                title: t.title,
                body: delta > 1
                    ? 'tracker.new_episodes_n'.tr(args: ['$delta', '$count'])
                    : 'tracker.new_episode_one'.tr(args: ['$count']),
                // `contentUrl`, which is the key the router reads. It was
                // `url`, so `openNotification` found nothing, fell through to
                // its default arm and opened the notifications list — every
                // one of these taps, since the feature shipped.
                data: {
                  'type': 'library_update',
                  'contentUrl': t.contentUrl,
                  'provider': t.provider,
                  'episodeNumber': t.lastEpisodeCount + 1,
                },
              );
            }
          }
        } catch (_) {
          // timeout / network / provider error — skip this title, keep going.
        }
      }
    }

    await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);

    // Single merged write — re-read in case the follow list changed mid-check.
    if (newCounts.isNotEmpty) {
      final raw = hive.getFollowedRaw();
      final now = DateTime.now().millisecondsSinceEpoch;
      final raisedForServer = <FollowedTitle>[];
      for (final e in raw) {
        final url = e['contentUrl'];
        if (url is String && newCounts.containsKey(url)) {
          final before = (e['lastEpisodeCount'] as num?)?.toInt() ?? 0;
          final after = newCounts[url]!;
          // Never lowered: a push may have raised it while this ran.
          if (after > before) {
            e['lastEpisodeCount'] = after;
            final label = newLabels[url];
            if (label != null) e['lastEpisodeLabel'] = label;
            raisedForServer.add(FollowedTitle.fromJson(e));
          }
          e['lastCheckedAt'] = now;
          final floor = autoFloors[url];
          if (floor != null && e['autoDownload'] == true) {
            e['autoDownloadFrom'] = floor;
          }
        }
      }
      await _save(raw);
      for (final t in raisedForServer) {
        sink?.patched(t, lastEpisodeCount: t.lastEpisodeCount);
      }
    }
    return grown;
  }

  /// The episode with the largest number in [episodes], or null for an empty
  /// list.
  ///
  /// Not `episodes.last`: a list can arrive newest-first, oldest-first, or in
  /// whatever order a source's page happened to be in.
  /// `EpisodeEntity.episode` is an int, so a source that numbers a chapter
  /// 104.5 has already lost the half by the time it reaches here — a real
  /// limitation, but one that predates this and is the same for both sides of
  /// the comparison, so it cannot produce a false announcement.
  static EpisodeEntity? newestOf(List<EpisodeEntity> episodes) {
    EpisodeEntity? newest;
    for (final e in episodes) {
      if (newest == null || e.episode > newest.episode) newest = e;
    }
    return newest;
  }
}
