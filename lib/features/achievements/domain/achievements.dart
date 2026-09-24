import 'package:flutter/material.dart';

/// The four tiers a family climbs, plus the look of something not yet earned.
///
/// Singles are earned once and wear the tier of their rarity, so a single and
/// a family tier of the same colour read as equally hard to get.
enum MedalTier {
  locked,
  bronze,
  silver,
  gold,
  ember;

  /// The tier a family's 1-based [tier] number stands for.
  static MedalTier ofLevel(int tier) => switch (tier) {
    1 => bronze,
    2 => silver,
    3 => gold,
    >= 4 => ember,
    _ => locked,
  };

  static MedalTier ofRarity(String? rarity) => switch (rarity) {
    'bronze' => bronze,
    'silver' => silver,
    'gold' => gold,
    'ember' => ember,
    _ => silver,
  };

  String get labelKey => 'achievements.tier_$name';

  /// The text colour a tier's name is written in beside its medal.
  Color get labelColor => switch (this) {
    locked => const Color(0xFF7A7A7A),
    bronze => const Color(0xFFE0A06A),
    silver => const Color(0xFFD3D8DE),
    gold => const Color(0xFFF4C443),
    ember => const Color(0xFFFFA94D),
  };
}

/// How one achievement is drawn and named. The server knows ids and numbers;
/// the words and pictures live here, in every language the app speaks.
@immutable
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.icon,
    this.isSingle = false,
    this.rarity = MedalTier.gold,
  });

  final String id;
  final IconData icon;
  final bool isSingle;

  /// A single's colour; the server says the same, this is for places that
  /// only have the id (a feed card, a celebration before the numbers land).
  final MedalTier rarity;

  String get nameKey => 'achievements.name_$id';

  /// A family: "{} episodes" and the like. A single: what earns it.
  String get unitKey =>
      isSingle ? 'achievements.rule_$id' : 'achievements.unit_$id';

  static const Map<String, AchievementDef> _all = {
    'streak': AchievementDef(
      id: 'streak',
      icon: Icons.local_fire_department_rounded,
    ),
    'episodes': AchievementDef(id: 'episodes', icon: Icons.play_arrow_rounded),
    'series_done': AchievementDef(
      id: 'series_done',
      icon: Icons.task_alt_rounded,
    ),
    'movies': AchievementDef(id: 'movies', icon: Icons.movie_rounded),
    'chapters': AchievementDef(
      id: 'chapters',
      icon: Icons.auto_stories_rounded,
    ),
    'manga_done': AchievementDef(
      id: 'manga_done',
      icon: Icons.library_books_rounded,
    ),
    'novel_chapters': AchievementDef(
      id: 'novel_chapters',
      icon: Icons.history_edu_rounded,
    ),
    'active_days': AchievementDef(
      id: 'active_days',
      icon: Icons.calendar_month_rounded,
    ),
    'iron_will': AchievementDef(
      id: 'iron_will',
      icon: Icons.shield_rounded,
      isSingle: true,
      rarity: MedalTier.ember,
    ),
    'binge': AchievementDef(
      id: 'binge',
      icon: Icons.bolt_rounded,
      isSingle: true,
      rarity: MedalTier.ember,
    ),
    'night_owl': AchievementDef(
      id: 'night_owl',
      icon: Icons.nightlight_round,
      isSingle: true,
    ),
    'party_host': AchievementDef(
      id: 'party_host',
      icon: Icons.celebration_rounded,
      isSingle: true,
    ),
    'explorer': AchievementDef(
      id: 'explorer',
      icon: Icons.explore_rounded,
      isSingle: true,
      rarity: MedalTier.silver,
    ),
    'friendly': AchievementDef(
      id: 'friendly',
      icon: Icons.group_rounded,
      isSingle: true,
      rarity: MedalTier.silver,
    ),
  };

  /// [id]'s look; an id this build does not know yet still gets a medal.
  static AchievementDef of(String id) =>
      _all[id] ?? AchievementDef(id: id, icon: Icons.emoji_events_rounded);

  static bool isKnown(String id) => _all.containsKey(id);
}

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

/// A family: its thresholds, how far along it is, and when each tier came.
@immutable
class AchievementFamily {
  const AchievementFamily({
    required this.id,
    required this.tiers,
    required this.tier,
    this.value,
    this.next,
    this.unlockedAt = const [],
  });

  final String id;
  final List<int> tiers;

  /// Tiers earned, 0 to [tiers].length.
  final int tier;

  /// The running count; null where it is not shown (someone else's profile).
  final int? value;
  final int? next;
  final List<DateTime?> unlockedAt;

  MedalTier get medal => MedalTier.ofLevel(tier);
  bool get isMaxed => tier >= tiers.length;

  /// Progress from the tier held to the next, 0..1.
  double get progress {
    final v = value;
    if (v == null) return tier > 0 ? 1 : 0;
    if (isMaxed) return 1;
    final from = tier == 0 ? 0 : tiers[tier - 1];
    final to = tiers[tier];
    if (to <= from) return 1;
    return ((v - from) / (to - from)).clamp(0.0, 1.0);
  }

  factory AchievementFamily.fromJson(Map<String, dynamic> json) {
    final tiers = [
      for (final t in (json['tiers'] as List? ?? const [])) _int(t),
    ];
    return AchievementFamily(
      id: '${json['id'] ?? ''}',
      tiers: tiers,
      tier: _int(json['tier']),
      value: json['value'] is num ? (json['value'] as num).toInt() : null,
      next: json['next'] is num ? (json['next'] as num).toInt() : null,
      unlockedAt: [
        for (final d in (json['unlockedAt'] as List? ?? const [])) _date(d),
      ],
    );
  }
}

@immutable
class AchievementSingle {
  const AchievementSingle({
    required this.id,
    required this.rarity,
    required this.unlocked,
    this.need = 1,
    this.value,
    this.at,
  });

  final String id;
  final MedalTier rarity;
  final bool unlocked;
  final int need;
  final int? value;
  final DateTime? at;

  MedalTier get medal => unlocked ? rarity : MedalTier.locked;

  factory AchievementSingle.fromJson(Map<String, dynamic> json) =>
      AchievementSingle(
        id: '${json['id'] ?? ''}',
        rarity: MedalTier.ofRarity(json['rarity'] as String?),
        // A friend's list carries earned singles only, without the flag.
        unlocked: json['unlocked'] != false,
        need: json['need'] is num ? (json['need'] as num).toInt() : 1,
        value: json['value'] is num ? (json['value'] as num).toInt() : null,
        at: _date(json['at']),
      );
}

/// One badge earned: a family tier, or a single (tier 1).
@immutable
class AchievementUnlock {
  const AchievementUnlock({required this.id, required this.tier, this.at});

  final String id;
  final int tier;
  final DateTime? at;

  bool get isSingle => AchievementDef.of(id).isSingle;

  factory AchievementUnlock.fromJson(Map<String, dynamic> json) =>
      AchievementUnlock(
        id: '${json['id'] ?? ''}',
        tier: _int(json['tier']),
        at: _date(json['at']),
      );

  static List<AchievementUnlock> listOf(Object? raw) => [
    if (raw is List)
      for (final e in raw)
        if (e is Map) AchievementUnlock.fromJson(e.cast<String, dynamic>()),
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'tier': tier,
    if (at != null) 'at': at!.toUtc().toIso8601String(),
  };
}

/// A profile's achievements, as the server tells them.
@immutable
class AchievementsView {
  const AchievementsView({
    required this.total,
    required this.unlockedCount,
    required this.families,
    required this.singles,
    required this.showcase,
    this.recent = const [],
  });

  final int total;
  final int unlockedCount;
  final List<AchievementFamily> families;
  final List<AchievementSingle> singles;

  /// Up to three ids, as the profile chose them.
  final List<String> showcase;
  final List<AchievementUnlock> recent;

  static const AchievementsView empty = AchievementsView(
    total: 0,
    unlockedCount: 0,
    families: [],
    singles: [],
    showcase: [],
  );

  AchievementFamily? family(String id) {
    for (final f in families) {
      if (f.id == id) return f;
    }
    return null;
  }

  AchievementSingle? single(String id) {
    for (final s in singles) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// How [id] looks at its best on this profile.
  MedalTier medalOf(String id) =>
      family(id)?.medal ?? single(id)?.medal ?? MedalTier.locked;

  bool isEarned(String id) => medalOf(id) != MedalTier.locked;

  /// Everything earned, the hardest-won first — what a showcase is picked from.
  List<String> get earnedIds {
    final out = <(String, int)>[
      for (final f in families)
        if (f.tier > 0) (f.id, f.tier),
      for (final s in singles)
        if (s.unlocked) (s.id, s.rarity.index),
    ];
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in out) e.$1];
  }

  factory AchievementsView.fromJson(Map<String, dynamic> json) =>
      AchievementsView(
        total: _int(json['total']),
        unlockedCount: _int(json['unlockedCount']),
        families: [
          for (final f in (json['families'] as List? ?? const []))
            if (f is Map) AchievementFamily.fromJson(f.cast<String, dynamic>()),
        ],
        singles: [
          for (final s in (json['singles'] as List? ?? const []))
            if (s is Map) AchievementSingle.fromJson(s.cast<String, dynamic>()),
        ],
        showcase: [
          for (final s in (json['showcase'] as List? ?? const []))
            if (s is String)
              s
            else if (s is Map && s['id'] is String)
              s['id'] as String,
        ],
        recent: AchievementUnlock.listOf(json['recent']),
      );

  /// A friend's public card: showcase entries come with their tier.
  static List<AchievementUnlock> showcaseOf(Object? raw) => [
    if (raw is List)
      for (final s in raw)
        if (s is Map) AchievementUnlock.fromJson(s.cast<String, dynamic>()),
  ];
}
