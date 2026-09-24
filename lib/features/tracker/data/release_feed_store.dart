import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';

/// The profile's New releases feed.
class ReleaseFeedStore {
  ReleaseFeedStore({Box? box, DateTime Function()? now})
    : _override = box,
      _now = now ?? DateTime.now;

  final Box? _override;
  final DateTime Function() _now;

  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  static const String storageKey = 'release_feed';
  static const int maxEntries = 60;
  static const Duration keepFor = Duration(days: 30);

  /// Bumped on every write, and on a profile switch.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String _key(String? scope) => scope == null
      ? ProfileScope.key(storageKey)
      : ProfileScope.keyFor(storageKey, scope.isEmpty ? null : scope);

  /// [scope] reads another profile's feed by namespace ('' is the default
  /// profile); null is the active one.
  List<ReleaseEntry> entries({String? scope}) {
    final raw = _box.get(_key(scope));
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final out = <ReleaseEntry>[
        for (final e in list)
          if (e is Map) ?ReleaseEntry.fromJson(e.cast<String, dynamic>()),
      ]..sort((a, b) => b.at.compareTo(a.at));
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<ReleaseEntry> unseen() => [
    for (final e in entries())
      if (!e.seen) e,
  ];

  int get unseenCount => unseen().length;

  /// The unseen release for [contentUrl], which is what a NEW badge means.
  ReleaseEntry? unseenFor(String contentUrl) {
    for (final e in entries()) {
      if (!e.seen && e.contentUrl == contentUrl) return e;
    }
    return null;
  }

  /// Records [entry], folding it into the title's existing row. Returns
  /// whether anything changed.
  Future<bool> add(ReleaseEntry entry, {String? scope}) async {
    final all = entries(scope: scope).toList();
    final i = all.indexWhere((e) => e.key == entry.key);
    if (i < 0) {
      all.add(entry);
    } else {
      final merged = all[i].absorb(entry);
      if (identical(merged, all[i])) return false;
      all[i] = merged;
    }
    await _write(all, scope: scope);
    return true;
  }

  Future<void> markSeen(String key) => _update(
    (e) => e.key == key && !e.seen ? e.copyWith(seen: true) : e,
  );

  Future<void> markTitleSeen(String contentUrl) => _update(
    (e) => e.contentUrl == contentUrl && !e.seen ? e.copyWith(seen: true) : e,
  );

  Future<void> markAllSeen() =>
      _update((e) => e.seen ? e : e.copyWith(seen: true));

  Future<void> dismiss(String key) async {
    final all = entries().where((e) => e.key != key).toList();
    await _write(all);
  }

  /// Puts back a row the user just dismissed, for Undo.
  Future<void> restore(ReleaseEntry entry) async {
    final all = entries().where((e) => e.key != entry.key).toList()
      ..add(entry);
    await _write(all);
  }

  Future<void> _update(ReleaseEntry Function(ReleaseEntry) f) async {
    final all = entries();
    var changed = false;
    final next = [
      for (final e in all)
        () {
          final n = f(e);
          if (!identical(n, e)) changed = true;
          return n;
        }(),
    ];
    if (changed) await _write(next);
  }

  Future<void> _write(List<ReleaseEntry> all, {String? scope}) async {
    final cutoff = _now().subtract(keepFor).millisecondsSinceEpoch;
    final kept = all.where((e) => e.at >= cutoff).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final trimmed = kept.length > maxEntries
        ? kept.sublist(0, maxEntries)
        : kept;
    await _box.put(
      _key(scope),
      jsonEncode([for (final e in trimmed) e.toJson()]),
    );
    revision.value++;
  }
}
