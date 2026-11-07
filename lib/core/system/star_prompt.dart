import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// Where the GitHub star prompt stands: episodes finished, the count at which
/// it may show next, and whether the viewer has answered for good.
@immutable
class StarPromptState {
  const StarPromptState({
    this.completed = 0,
    this.nextAt = StarPromptRules.firstAt,
    this.done = false,
  });

  final int completed;
  final int nextAt;
  final bool done;

  factory StarPromptState.fromMap(Object? raw) {
    if (raw is! Map) return const StarPromptState();
    int asInt(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return StarPromptState(
      completed: asInt(raw['completed'], 0),
      nextAt: asInt(raw['nextAt'], StarPromptRules.firstAt),
      done: raw['done'] == true,
    );
  }

  Map<String, Object> toMap() => {
    'completed': completed,
    'nextAt': nextAt,
    'done': done,
  };

  StarPromptState copyWith({int? completed, int? nextAt, bool? done}) =>
      StarPromptState(
        completed: completed ?? this.completed,
        nextAt: nextAt ?? this.nextAt,
        done: done ?? this.done,
      );

  @override
  bool operator ==(Object other) =>
      other is StarPromptState &&
      other.completed == completed &&
      other.nextAt == nextAt &&
      other.done == done;

  @override
  int get hashCode => Object.hash(completed, nextAt, done);
}

/// The decisions, with no storage and no clock.
abstract final class StarPromptRules {
  static const int firstAt = 7;
  static const int snoozeEpisodes = 20;

  static bool shouldShow(StarPromptState s) =>
      !s.done && s.completed >= s.nextAt;

  static StarPromptState episodeCompleted(StarPromptState s) =>
      s.copyWith(completed: s.completed + 1);

  /// Showing it counts as "Later" until the viewer says otherwise, so a
  /// banner scrolled past or left behind does not come back on every screen.
  static StarPromptState shown(StarPromptState s) =>
      s.copyWith(nextAt: s.completed + snoozeEpisodes);

  static StarPromptState later(StarPromptState s) => shown(s);

  /// Starred, or "Don't ask again": either way, never again.
  static StarPromptState answered(StarPromptState s) => s.copyWith(done: true);
}

/// [StarPromptRules] over the settings box. App-wide, not per profile: it is
/// a question about the app, asked of whoever holds the device.
abstract final class StarPrompt {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  static StarPromptState get state =>
      StarPromptState.fromMap(_box?.get(AppConstants.starPromptKey));

  static bool get shouldShow => StarPromptRules.shouldShow(state);

  static Future<void> _apply(
    StarPromptState Function(StarPromptState) change,
  ) async {
    final box = _box;
    if (box == null) return;
    final before = state;
    final after = change(before);
    if (after == before) return;
    try {
      await box.put(AppConstants.starPromptKey, after.toMap());
    } catch (_) {}
    revision.value++;
  }

  static Future<void> episodeCompleted() =>
      _apply(StarPromptRules.episodeCompleted);

  static Future<void> markShown() => _apply(StarPromptRules.shown);

  static Future<void> later() => _apply(StarPromptRules.later);

  static Future<void> answered() => _apply(StarPromptRules.answered);
}
