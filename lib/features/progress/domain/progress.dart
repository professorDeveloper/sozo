/// XP, levels and cosmetics, as `/progress` describes them. Parsing is
/// lenient for the same reason as everywhere else: an old app keeps talking to
/// a newer server.
library;

import 'dart:math' as math;

/// Cumulative XP level [n] needs: 100·n^1.5, the server's own curve.
int xpForLevel(int n) => n <= 0 ? 0 : (100 * math.pow(n, 1.5)).floor();

/// The level [xp] cumulative XP reaches.
int levelFor(int xp) {
  if (xp <= 0) return 0;
  var n = math.pow(xp / 100, 2 / 3).floor();
  while (xpForLevel(n + 1) <= xp) {
    n++;
  }
  while (n > 0 && xpForLevel(n) > xp) {
    n--;
  }
  return n;
}

/// Where an XP total sits inside its level, for a ring or a bar.
class LevelProgress {
  const LevelProgress._(this.level, this.xp, this.floor, this.next);

  factory LevelProgress.of(int xp) {
    final x = math.max(0, xp);
    final level = levelFor(x);
    return LevelProgress._(level, x, xpForLevel(level), xpForLevel(level + 1));
  }

  final int level;
  final int xp;

  /// XP the current level started at.
  final int floor;

  /// XP the next level starts at.
  final int next;

  int get intoLevel => xp - floor;
  int get span => next - floor;
  int get toNext => next - xp;
  double get fraction =>
      span <= 0 ? 0 : (intoLevel / span).clamp(0.0, 1.0).toDouble();
}

int _int(Object? v) => v is num ? v.toInt() : 0;

String? _str(Object? v) {
  if (v is! String) return null;
  return v.isEmpty ? null : v;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

/// What others see beside a name. Null wherever the server sent no level,
/// which is also what a server without this feature sends.
class UserDecoration {
  const UserDecoration({
    required this.level,
    this.frame,
    this.title,
    this.nameColor,
  });

  final int level;
  final String? frame;
  final String? title;
  final String? nameColor;

  static UserDecoration? fromJson(Map<String, dynamic> json) {
    final level = json['level'];
    if (level is! num) return null;
    return UserDecoration(
      level: level.toInt(),
      frame: _str(json['frame']),
      title: _str(json['title']),
      nameColor: _str(json['nameColor']),
    );
  }
}

enum CosmeticSlot {
  frame,
  title,
  nameColor;

  static CosmeticSlot? parse(String raw) => switch (raw) {
    'frame' => frame,
    'title' => title,
    'nameColor' => nameColor,
    _ => null,
  };
}

/// One frame, title or colour, and what unlocks it.
class CosmeticItem {
  const CosmeticItem({
    required this.slot,
    required this.id,
    required this.unlocked,
    this.level,
    this.badge,
    this.tier = 1,
  });

  final CosmeticSlot slot;
  final String id;
  final bool unlocked;

  /// The level that unlocks it, or null when a badge does.
  final int? level;
  final String? badge;
  final int tier;

  factory CosmeticItem.fromJson(CosmeticSlot slot, Map<String, dynamic> json) {
    final unlock = _map(json['unlock']);
    return CosmeticItem(
      slot: slot,
      id: _str(json['id']) ?? '',
      unlocked: json['unlocked'] == true,
      level: unlock['level'] is num ? _int(unlock['level']) : null,
      badge: _str(unlock['badge']),
      tier: unlock['tier'] is num ? _int(unlock['tier']) : 1,
    );
  }
}

class XpGain {
  const XpGain({required this.reason, required this.xp, this.at});

  final String reason;
  final int xp;
  final DateTime? at;

  factory XpGain.fromJson(Map<String, dynamic> json) => XpGain(
    reason: _str(json['reason']) ?? '',
    xp: _int(json['xp']),
    at: json['at'] is String
        ? DateTime.tryParse(json['at'] as String)?.toLocal()
        : null,
  );
}

class ProgressView {
  const ProgressView({
    required this.xp,
    this.watchSeconds = 0,
    this.commentCount = 0,
    this.frame,
    this.title,
    this.nameColor,
    this.recent = const [],
    this.catalog = const [],
    this.watchXpToday = 0,
    this.watchCap = 300,
  });

  final int xp;
  final int watchSeconds;
  final int commentCount;
  final String? frame;
  final String? title;
  final String? nameColor;
  final List<XpGain> recent;
  final List<CosmeticItem> catalog;
  final int watchXpToday;
  final int watchCap;

  LevelProgress get progress => LevelProgress.of(xp);
  int get level => progress.level;

  UserDecoration get decoration => UserDecoration(
    level: level,
    frame: frame,
    title: title,
    nameColor: nameColor,
  );

  List<CosmeticItem> slot(CosmeticSlot s) =>
      catalog.where((c) => c.slot == s && c.id.isNotEmpty).toList();

  String? equipped(CosmeticSlot s) => switch (s) {
    CosmeticSlot.frame => frame,
    CosmeticSlot.title => title,
    CosmeticSlot.nameColor => nameColor,
  };

  factory ProgressView.fromJson(Map<String, dynamic> json) {
    final equipped = _map(json['equipped']);
    final today = _map(json['today']);
    final catalog = <CosmeticItem>[];
    for (final e in _map(json['catalog']).entries) {
      final slot = CosmeticSlot.parse(e.key);
      if (slot == null || e.value is! List) continue;
      for (final item in (e.value as List).whereType<Map>()) {
        catalog.add(CosmeticItem.fromJson(slot, item.cast<String, dynamic>()));
      }
    }
    return ProgressView(
      xp: _int(json['xp']),
      watchSeconds: _int(json['watchSeconds']),
      commentCount: _int(json['commentCount']),
      frame: _str(equipped['frame']),
      title: _str(equipped['title']),
      nameColor: _str(equipped['nameColor']),
      recent: [
        if (json['recent'] is List)
          for (final g in (json['recent'] as List).whereType<Map>())
            XpGain.fromJson(g.cast<String, dynamic>()),
      ],
      catalog: catalog,
      watchXpToday: _int(today['watchXp']),
      watchCap: today['watchCap'] is num ? _int(today['watchCap']) : 300,
    );
  }
}
