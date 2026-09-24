import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';

/// The signed-in Jellyfin servers, in their own encrypted box.
///
/// Not in `auth_box`: signing out of Sozo clears that, and a media server on
/// the home network has nothing to do with the Sozo account.
class JellyfinServerStore {
  JellyfinServerStore({Box<dynamic>? Function()? box}) : _box = box ?? _openBox;

  static const String boxName = 'jellyfin_box';
  static const String _serversKey = 'servers';
  static const String _deviceKey = 'device_id';

  static Box<dynamic>? _openBox() =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  final Box<dynamic>? Function() _box;

  /// Used when the box could not be opened, so the session still works.
  final Map<String, Object?> _memory = {};

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Object? _read(String key) {
    final box = _box();
    return box == null ? _memory[key] : box.get(key);
  }

  Future<void> _write(String key, Object? value) async {
    final box = _box();
    if (box == null) {
      _memory[key] = value;
    } else {
      await box.put(key, value);
    }
  }

  List<JellyfinServer> servers() {
    final raw = _read(_serversKey);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final e in list) ?JellyfinServer.fromJson(e)];
    } catch (_) {
      return const [];
    }
  }

  JellyfinServer? byId(String id) {
    for (final s in servers()) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> save(JellyfinServer server) async {
    final list = servers().where((s) => s.id != server.id).toList()
      ..add(server);
    await _persist(list);
  }

  Future<void> remove(String id) async {
    await _persist(servers().where((s) => s.id != id).toList());
  }

  Future<void> _persist(List<JellyfinServer> list) async {
    await _write(_serversKey, jsonEncode([for (final s in list) s.toJson()]));
    revision.value++;
  }

  /// One per install, as Jellyfin expects: the server keys sessions and
  /// transcodes on it, so a fresh id per launch would pile up devices.
  String get deviceId {
    final existing = _read(_deviceKey);
    if (existing is String && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final id = List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _write(_deviceKey, id);
    return id;
  }
}
