import 'package:easy_localization/easy_localization.dart';

import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';

/// "EP 12", "EP 10–12", "CH 88".
String releaseEpisodeLabel(ReleaseEntry e) {
  final reading = e.isReading;
  if (e.newCount > 1) {
    return (reading ? 'release_notify.ch_range' : 'release_notify.ep_range')
        .tr(args: ['${e.fromEpisode}', '${e.episode}']);
  }
  final label = e.label?.trim();
  if (label != null && label.isNotEmpty && int.tryParse(label) == null) {
    return label;
  }
  return (reading ? 'release_notify.ch_one' : 'release_notify.ep_one')
      .tr(args: ['${e.episode}']);
}

/// "2 h ago", with the words the app already uses for history.
String releaseAgo(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'time.now'.tr();
  if (d.inHours < 1) return 'time.minutes'.tr(args: ['${d.inMinutes}']);
  if (d.inDays < 1) return 'time.hours'.tr(args: ['${d.inHours}']);
  return 'time.days'.tr(args: ['${d.inDays}']);
}

String releaseModeLabel(String mode) => switch (mode) {
  'manga' => 'release_notify.mode_manga'.tr(),
  'novel' => 'release_notify.mode_novel'.tr(),
  _ => 'release_notify.mode_video'.tr(),
};

/// "EP 13 · in 2 d" for a followed title the server knows the schedule of;
/// null when nothing is scheduled or it is already past.
String? nextAiringHint(FollowedTitle t, {bool reading = false, DateTime? now}) {
  final at = t.nextAiringAt;
  if (at == null) return null;
  final when = DateTime.fromMillisecondsSinceEpoch(at);
  final left = when.difference(now ?? DateTime.now());
  if (left.isNegative) return null;
  final inText = left.inHours < 1
      ? 'release_notify.soon'.tr()
      : left.inDays < 1
      ? 'release_notify.in_hours'.tr(args: ['${left.inHours}'])
      : 'release_notify.in_days'.tr(args: ['${left.inDays}']);
  final ep = t.nextAiringEpisode;
  if (ep == null) return inText;
  final epText = (reading ? 'release_notify.ch_one' : 'release_notify.ep_one')
      .tr(args: ['$ep']);
  return '$epText · $inText';
}
