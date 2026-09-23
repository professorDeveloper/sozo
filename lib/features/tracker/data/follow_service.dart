import 'dart:async';

import 'package:easy_localization/easy_localization.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

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

  List<FollowedTitle> list() =>
      hive.getFollowedRaw().map(FollowedTitle.fromJson).toList();

  bool isFollowed(String contentUrl) =>
      hive.getFollowedRaw().any((e) => e['contentUrl'] == contentUrl);

  Future<void> follow(FollowedTitle title) async {
    final items = hive.getFollowedRaw();
    if (items.any((e) => e['contentUrl'] == title.contentUrl)) return;
    items.insert(0, title.toJson());
    await hive.setFollowedRaw(items);
  }

  Future<void> unfollow(String contentUrl) async {
    final items = hive.getFollowedRaw()
      ..removeWhere((e) => e['contentUrl'] == contentUrl);
    await hive.setFollowedRaw(items);
  }

  /// Re-check every followed serial for new episodes. Returns how many grew.
  /// Fires one local notification per grown title (when [notify] is true).
  ///
  /// Freeze-proof: at most [concurrency] checks run at once, each capped at
  /// [timeout]; counts are persisted in a single write at the end (no races).
  Future<int> checkForUpdates({
    int concurrency = 3,
    Duration timeout = const Duration(seconds: 12),
    bool notify = true,
  }) async {
    final items = list();
    if (items.isEmpty) return 0;

    final newCounts = <String, int>{};
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
          final count = _highestNumber(pb.episodes);
          if (count <= 0) continue;
          newCounts[t.contentUrl] = count;
          if (t.lastEpisodeCount > 0 && count > t.lastEpisodeCount) {
            final delta = pb.episodes
                .where((e) => e.episode > t.lastEpisodeCount)
                .length;
            grown++;
            if (notify) {
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
      for (final e in raw) {
        final url = e['contentUrl'];
        if (url is String && newCounts.containsKey(url)) {
          e['lastEpisodeCount'] = newCounts[url];
          e['lastCheckedAt'] = now;
        }
      }
      await hive.setFollowedRaw(raw);
    }
    return grown;
  }

  /// The largest episode/chapter number in [episodes], or 0 for an empty list.
  ///
  /// Not `episodes.last.episode`: a list can arrive newest-first, oldest-first,
  /// or in whatever order a source's page happened to be in.
  /// `EpisodeEntity.episode` is an int, so a source that numbers a chapter
  /// 104.5 has already lost the half by the time it reaches here — a real
  /// limitation, but one that predates this and is the same for both sides of
  /// the comparison, so it cannot produce a false announcement.
  static int _highestNumber(List<EpisodeEntity> episodes) {
    var highest = 0;
    for (final e in episodes) {
      if (e.episode > highest) highest = e.episode;
    }
    return highest;
  }
}
