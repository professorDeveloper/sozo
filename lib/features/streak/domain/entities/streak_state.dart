import 'package:soplay/features/achievements/domain/achievements.dart';

class StreakMilestone {
  final int value;
  final bool reached;

  const StreakMilestone({required this.value, required this.reached});

  factory StreakMilestone.fromJson(Map<String, dynamic> json) => StreakMilestone(
        value: (json['value'] as num?)?.toInt() ?? 0,
        reached: json['reached'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'value': value, 'reached': reached};
}

class StreakFreezes {
  final int available;
  final int max;

  const StreakFreezes({this.available = 0, this.max = 0});

  factory StreakFreezes.fromJson(Map<String, dynamic> json) => StreakFreezes(
        available: (json['available'] as num?)?.toInt() ?? 0,
        max: (json['max'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'available': available, 'max': max};
}

class StreakDay {
  final String date;
  final bool active;

  const StreakDay({required this.date, required this.active});

  factory StreakDay.fromJson(Map<String, dynamic> json) => StreakDay(
        date: json['date'] as String? ?? '',
        active: json['active'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'date': date, 'active': active};
}

List<StreakDay> _parseDays(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => StreakDay.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
  return const [];
}

List<StreakMilestone> _parseMilestones(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => StreakMilestone.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
  return const [];
}

StreakFreezes _parseFreezes(dynamic raw) {
  if (raw is Map) {
    return StreakFreezes.fromJson(Map<String, dynamic>.from(raw));
  }
  return const StreakFreezes();
}

class StreakState {
  final int current;
  final int longest;
  final String? lastActiveDate;
  final bool pingedToday;
  final bool isAtRisk;

  final int? nextMilestone;
  final int? daysToNextMilestone;
  final List<StreakMilestone> milestones;
  final int totalDays;
  final StreakFreezes freezes;
  final List<StreakDay> weeklyActivity;
  final List<StreakDay> calendar;
  final int thisWeekCount;

  const StreakState({
    required this.current,
    required this.longest,
    this.lastActiveDate,
    this.pingedToday = false,
    this.isAtRisk = false,
    this.nextMilestone,
    this.daysToNextMilestone,
    this.milestones = const [],
    this.totalDays = 0,
    this.freezes = const StreakFreezes(),
    this.weeklyActivity = const [],
    this.calendar = const [],
    this.thisWeekCount = 0,
  });

  static const empty = StreakState(current: 0, longest: 0);

  StreakState copyWith({
    int? current,
    int? longest,
    String? lastActiveDate,
    bool? pingedToday,
    bool? isAtRisk,
    int? nextMilestone,
    int? daysToNextMilestone,
    List<StreakMilestone>? milestones,
    int? totalDays,
    StreakFreezes? freezes,
    List<StreakDay>? weeklyActivity,
    List<StreakDay>? calendar,
    int? thisWeekCount,
  }) =>
      StreakState(
        current: current ?? this.current,
        longest: longest ?? this.longest,
        lastActiveDate: lastActiveDate ?? this.lastActiveDate,
        pingedToday: pingedToday ?? this.pingedToday,
        isAtRisk: isAtRisk ?? this.isAtRisk,
        nextMilestone: nextMilestone ?? this.nextMilestone,
        daysToNextMilestone: daysToNextMilestone ?? this.daysToNextMilestone,
        milestones: milestones ?? this.milestones,
        totalDays: totalDays ?? this.totalDays,
        freezes: freezes ?? this.freezes,
        weeklyActivity: weeklyActivity ?? this.weeklyActivity,
        calendar: calendar ?? this.calendar,
        thisWeekCount: thisWeekCount ?? this.thisWeekCount,
      );

  Map<String, dynamic> toJson() => {
        'current': current,
        'longest': longest,
        'lastActiveDate': lastActiveDate,
        'pingedToday': pingedToday,
        'isAtRisk': isAtRisk,
        'nextMilestone': nextMilestone,
        'daysToNextMilestone': daysToNextMilestone,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'totalDays': totalDays,
        'freezes': freezes.toJson(),
        'weeklyActivity': weeklyActivity.map((d) => d.toJson()).toList(),
        'calendar': calendar.map((d) => d.toJson()).toList(),
        'thisWeekCount': thisWeekCount,
      };

  factory StreakState.fromJson(Map<String, dynamic> json) => StreakState(
        current: (json['current'] as num?)?.toInt() ?? 0,
        longest: (json['longest'] as num?)?.toInt() ?? 0,
        lastActiveDate: json['lastActiveDate'] as String?,
        pingedToday: json['pingedToday'] as bool? ?? false,
        isAtRisk: json['isAtRisk'] as bool? ?? false,
        nextMilestone: (json['nextMilestone'] as num?)?.toInt(),
        daysToNextMilestone: (json['daysToNextMilestone'] as num?)?.toInt(),
        milestones: _parseMilestones(json['milestones']),
        totalDays: (json['totalDays'] as num?)?.toInt() ?? 0,
        freezes: _parseFreezes(json['freezes']),
        weeklyActivity: _parseDays(json['weeklyActivity']),
        calendar: _parseDays(json['calendar']),
        thisWeekCount: (json['thisWeekCount'] as num?)?.toInt() ?? 0,
      );
}

class StreakPingResult {
  final StreakState state;
  final int? newMilestone;
  final bool freezeSaved;
  final bool freezeAwarded;

  /// Badges this streak day earned.
  final List<AchievementUnlock> achievements;

  const StreakPingResult({
    required this.state,
    this.newMilestone,
    this.freezeSaved = false,
    this.freezeAwarded = false,
    this.achievements = const [],
  });

  /// The streak badge's tier this day reached, when it reached one — the
  /// milestone dialog shows it rather than a second dialog saying the same.
  int? get streakBadgeTier {
    int? best;
    for (final a in achievements) {
      if (a.id == 'streak' && (best == null || a.tier > best)) best = a.tier;
    }
    return best;
  }

  factory StreakPingResult.fromJson(Map<String, dynamic> json) {
    final ms = json['isNewMilestone'];
    return StreakPingResult(
      state: StreakState.fromJson(json),
      newMilestone: ms is num ? ms.toInt() : null,
      freezeSaved: json['freezeSaved'] as bool? ?? false,
      freezeAwarded: json['freezeAwarded'] as bool? ?? false,
      achievements: AchievementUnlock.listOf(json['achievements']),
    );
  }
}
