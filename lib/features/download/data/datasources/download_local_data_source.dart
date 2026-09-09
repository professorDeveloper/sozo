import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/download/data/models/download_item_model.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';

/// The download rows, in Hive.
///
/// Nothing here knows about transfers, paths on this device or the network. It
/// reads and writes rows, and it is the one place that decides how often the
/// rest of the app is told something changed.
class DownloadLocalDataSource {
  DownloadLocalDataSource();

  Box get _box => Hive.box(AppConstants.downloadBox);

  /// Bumped on every change the UI should redraw for.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  int _lastNotifyMs = 0;

  /// A transfer writes progress several times a second. Coalescing the
  /// notification — but never the WRITE — keeps a list of twenty rows from
  /// rebuilding on every buffer while still surviving a kill.
  static const int _notifyIntervalMs = 400;

  List<DownloadItem> all() {
    final items = <DownloadItem>[];
    for (final key in _box.keys) {
      final item = _decode(_box.get(key));
      if (item != null) items.add(item);
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  DownloadItem? get(String id) => _decode(_box.get(id));

  Future<void> put(DownloadItem item, {bool notify = true}) async {
    await _box.put(item.id, jsonEncode(DownloadItemModel.toJson(item)));
    if (notify) _notify(force: item.status.isTerminal);
  }

  /// One write per row, one notification for the batch. The verification sweep
  /// touches every row at startup, and notifying per row made the Downloads
  /// screen rebuild once per download before it had drawn anything.
  Future<void> putAll(Iterable<DownloadItem> items) async {
    for (final item in items) {
      await _box.put(item.id, jsonEncode(DownloadItemModel.toJson(item)));
    }
    _notify(force: true);
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    _notify(force: true);
  }

  Future<void> deleteAll(Iterable<String> ids) async {
    await _box.deleteAll(ids);
    _notify(force: true);
  }

  Future<void> clear() async {
    await _box.clear();
    _notify(force: true);
  }

  void _notify({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastNotifyMs < _notifyIntervalMs) return;
    _lastNotifyMs = now;
    revision.value++;
  }

  /// Forces a redraw without writing anything — for a change that lives
  /// outside the rows, like the queue starting to hold for Wi-Fi.
  void touch() => _notify(force: true);

  DownloadItem? _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return DownloadItemModel.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('[downloads] unreadable row dropped: $e');
      return null;
    }
  }

  void dispose() => revision.dispose();
}
