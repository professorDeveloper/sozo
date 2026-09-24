import 'package:easy_localization/easy_localization.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

/// Reminders for episodes about to air.
///
/// Local, not push. The phone already knows when every episode on your list
/// airs — the calendar fetched it — so routing that through a server, a token
/// and a delivery receipt would add three ways to fail to something that can
/// simply be scheduled. It also works with no signal.
///
/// Rescheduled wholesale rather than diffed: the schedule shifts constantly as
/// episodes are delayed and announced, and cancelling a window's worth before
/// laying it down again is both simpler and correct, where a diff has to be
/// right about what changed.
class AiringReminders {
  AiringReminders({
    required NotificationService notifications,
    required HiveService hive,
  }) : _notifications = notifications,
       _hive = hive;

  final NotificationService _notifications;
  final HiveService _hive;

  /// How long before the episode the heads-up fires.
  static const Duration lead = Duration(minutes: 10);

  /// How long after the airing time the "it is out" notification fires.
  ///
  /// Not on the dot: a source needs a few minutes to actually carry the episode,
  /// and a notification that arrives before anything is watchable is worse than
  /// one that arrives late.
  static const Duration releaseDelay = Duration(minutes: 5);

  /// Only the next few days are scheduled. The platform caps how many pending
  /// notifications an app may hold, and a reminder three weeks out is one the
  /// schedule will have changed under anyway.
  static const Duration horizon = Duration(days: 7);

  /// Ids live in their own block so cancelling ours never touches a
  /// notification some other part of the app scheduled.
  static const int _idBase = 900000;
  static const int _idSpan = 1000;

  bool get enabled => _hive.airingRemindersEnabled;

  Future<void> setEnabled(bool value) async {
    await _hive.setAiringRemindersEnabled(value);
    if (!value) await _cancelAll();
  }

  /// Lays down the next window of reminders for [entries].
  ///
  /// Silent on failure: this runs behind a screen the user is looking at, and a
  /// scheduling problem is not worth interrupting them for.
  Future<void> sync(Iterable<AnilistListEntry> entries) async {
    try {
      await _cancelAll();
      if (!enabled) return;

      final now = DateTime.now();
      final until = now.add(horizon);
      final due =
          <
            ({
              DateTime at,
              String title,
              int episode,
              bool released,
              String url,
            })
          >[];

      for (final entry in entries) {
        final airing = entry.media.nextAiring;
        if (airing == null) continue;
        if (airing.airsAt.isAfter(until)) continue;
        final title =
            entry.media.englishTitle ??
            entry.media.romajiTitle ??
            entry.media.nativeTitle ??
            '';
        if (title.isEmpty) continue;
        final url =
            entry.media.siteUrl ?? 'https://anilist.co/anime/${entry.media.id}';

        // Two moments matter, and only one of them was ever scheduled: the
        // heads-up before it airs, and the episode actually being out. The
        // second is the one people mean by "tell me when a new episode drops" —
        // a reminder ten minutes early is a promise, not the thing itself.
        final ahead = airing.airsAt.subtract(lead);
        if (ahead.isAfter(now)) {
          due.add((
            at: ahead,
            title: title,
            episode: airing.episode,
            released: false,
            url: url,
          ));
        }
        final out = airing.airsAt.add(releaseDelay);
        if (out.isAfter(now)) {
          due.add((
            at: out,
            title: title,
            episode: airing.episode,
            released: true,
            url: url,
          ));
        }
      }

      due.sort((a, b) => a.at.compareTo(b.at));

      var scheduled = 0;
      for (var i = 0; i < due.length && scheduled < _idSpan; i++) {
        final item = due[i];
        await _notifications.scheduleAt(
          id: _idBase + scheduled,
          when: item.at,
          title: item.title,
          body:
              (item.released
                      ? 'anilist.released_body'
                      : 'anilist.reminder_body')
                  .tr(namedArgs: {'episode': '${item.episode}'}),
          // Opens the title on that episode; without a payload the tap only
          // brought the app forward.
          payload: {
            'type': 'airing_reminder',
            'provider': 'cat:anilist',
            'contentUrl': item.url,
            'episodeNumber': item.episode,
          },
        );
        scheduled++;
      }
      await _hive.setAiringReminderCount(scheduled);
    } catch (_) {
      // Scheduling is best effort; the calendar itself still works.
    }
  }

  /// Cancels exactly what was laid down last time.
  ///
  /// The count is remembered rather than sweeping the whole id block: walking a
  /// thousand ids costs a platform call each, and cancelAll() would take out
  /// notifications this class never scheduled.
  Future<void> _cancelAll() async {
    final count = _hive.airingReminderCount;
    if (count <= 0) return;
    await _notifications.cancelAllScheduled([
      for (var i = 0; i < count; i++) _idBase + i,
    ]);
    await _hive.setAiringReminderCount(0);
  }
}
