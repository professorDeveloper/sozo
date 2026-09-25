import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// The kinds of notification someone can switch off one by one.
enum NotificationCategory { releases, airing, friends, streak, announcements }

/// Which switch a push or local notification answers to, by its `type`.
///
/// Null means it belongs to none of them and only the master switch applies —
/// a ban notice is not something to be muted by accident.
NotificationCategory? categoryOf(String? type) => switch (type ?? '') {
  'new_release' || 'library_update' || 'auto_download' =>
    NotificationCategory.releases,
  'airing_reminder' => NotificationCategory.airing,
  'friend_request' ||
  'friend_accept' ||
  'system_comment_reply' ||
  'system_comment_like' => NotificationCategory.friends,
  'streak_risk' => NotificationCategory.streak,
  'admin_broadcast' || 'admin_direct' => NotificationCategory.announcements,
  _ => null,
};

/// A nightly window in which nothing makes a sound.
///
/// Minutes after midnight, local time. [from] after [to] wraps past midnight,
/// which is the usual case (23:00–07:00); equal means the whole day.
class QuietHours {
  const QuietHours({this.enabled = false, this.from = 23 * 60, this.to = 7 * 60});

  final bool enabled;
  final int from;
  final int to;

  bool contains(DateTime t) {
    if (!enabled) return false;
    final m = t.hour * 60 + t.minute;
    if (from == to) return true;
    if (from < to) return m >= from && m < to;
    return m >= from || m < to;
  }

  QuietHours copyWith({bool? enabled, int? from, int? to}) => QuietHours(
    enabled: enabled ?? this.enabled,
    from: from ?? this.from,
    to: to ?? this.to,
  );

  Map<String, dynamic> toJson() => {'on': enabled, 'from': from, 'to': to};

  factory QuietHours.fromJson(Object? raw) {
    if (raw is! Map) return const QuietHours();
    int minutes(Object? v, int fallback) {
      final n = v is num ? v.toInt() : fallback;
      return n.clamp(0, 24 * 60 - 1);
    }

    return QuietHours(
      enabled: raw['on'] == true,
      from: minutes(raw['from'], 23 * 60),
      to: minutes(raw['to'], 7 * 60),
    );
  }
}

class NotificationPrefs {
  const NotificationPrefs({
    this.master = true,
    this.disabled = const {},
    this.quiet = const QuietHours(),
  });

  final bool master;
  final Set<NotificationCategory> disabled;
  final QuietHours quiet;

  bool isOn(NotificationCategory c) => master && !disabled.contains(c);

  /// Whether a notification of [type] may be shown at all.
  bool allows(String? type) {
    if (!master) return false;
    final c = categoryOf(type);
    return c == null || !disabled.contains(c);
  }

  NotificationPrefs copyWith({
    bool? master,
    Set<NotificationCategory>? disabled,
    QuietHours? quiet,
  }) => NotificationPrefs(
    master: master ?? this.master,
    disabled: disabled ?? this.disabled,
    quiet: quiet ?? this.quiet,
  );

  NotificationPrefs withCategory(NotificationCategory c, bool on) {
    final next = {...disabled};
    on ? next.remove(c) : next.add(c);
    return copyWith(disabled: next);
  }

  Map<String, dynamic> toJson() => {
    'master': master,
    'off': [for (final c in disabled) c.name],
    'quiet': quiet.toJson(),
  };

  factory NotificationPrefs.fromJson(Object? raw) {
    if (raw is! Map) return const NotificationPrefs();
    final off = raw['off'];
    return NotificationPrefs(
      master: raw['master'] != false,
      disabled: {
        if (off is List)
          for (final name in off)
            for (final c in NotificationCategory.values)
              if (c.name == name) c,
      },
      quiet: QuietHours.fromJson(raw['quiet']),
    );
  }
}

/// Device-wide, like the OS permission it sits under.
class NotificationPrefsStore {
  NotificationPrefsStore({Box? box}) : _override = box;

  final Box? _override;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  static const String storageKey = 'notification_prefs';

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  NotificationPrefs read() {
    final raw = _box.get(storageKey);
    if (raw is! String || raw.isEmpty) return const NotificationPrefs();
    try {
      return NotificationPrefs.fromJson(jsonDecode(raw));
    } catch (_) {
      return const NotificationPrefs();
    }
  }

  Future<void> write(NotificationPrefs prefs) async {
    await _box.put(storageKey, jsonEncode(prefs.toJson()));
    revision.value++;
  }
}
