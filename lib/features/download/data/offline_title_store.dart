import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/download/data/models/offline_title_model.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';
import 'package:soplay/features/download/domain/repositories/offline_title_repository.dart';

/// Snapshots in Hive, one JSON string per title, keyed by content url.
///
/// A snapshot is written when a title's first download completes and kept
/// fresh whenever its page or list loads online; it goes when the title's
/// last download is deleted.
class OfflineTitleStore implements OfflineTitleRepository {
  OfflineTitleStore({Box<dynamic>? box}) : _injectedBox = box;

  final Box<dynamic>? _injectedBox;

  List<DownloadItem> Function() _rows = () => const [];
  Set<String> _lastGroups = const {};

  /// Titles seen online in this session that have no download yet. Bounded:
  /// only the last few pages visited can be the one a download starts from.
  final Map<String, OfflineTitle> _seen = {};
  static const int _seenCap = 24;

  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get revision => _revision;

  Box<dynamic>? get _box {
    final injected = _injectedBox;
    if (injected != null) return injected;
    try {
      return Hive.box(AppConstants.offlineTitlesBox);
    } catch (_) {
      return null;
    }
  }

  /// Follows the download rows: snapshots appear as downloads complete and
  /// go with the last one.
  void attach({
    required List<DownloadItem> Function() rows,
    required ValueListenable<int> revision,
  }) {
    _rows = rows;
    _lastGroups = _groups().keys.toSet();
    revision.addListener(_onRowsChanged);
    _onRowsChanged();
  }

  Map<String, List<DownloadItem>> _groups() {
    final out = <String, List<DownloadItem>>{};
    for (final item in _rows()) {
      if (item.contentUrl.isEmpty) continue;
      out.putIfAbsent(item.groupKey, () => []).add(item);
    }
    return out;
  }

  bool _tracked(String key) =>
      _rows().any((i) => i.groupKey == key) || _box?.containsKey(key) == true;

  // One pass at a time: the rows tick faster than a pass writes, and two
  // overlapping passes could bring back a copy the other just removed.
  Future<void> _syncing = Future.value();

  @visibleForTesting
  Future<void> syncWithRows() => _syncing = _syncing
      .then((_) => _sync())
      .catchError((Object e) => debugPrint('[offline] sync failed: $e'));

  void _onRowsChanged() => syncWithRows();

  Future<void> _sync() async {
    final groups = _groups();
    for (final entry in groups.entries) {
      if (!entry.value.any((i) => i.status == DownloadStatus.completed)) {
        continue;
      }
      final saved = get(entry.key);
      final fallback = OfflineTitle.fromItems(entry.value);
      if (saved == null) {
        await _put(_seen[entry.key] ?? fallback);
      } else if (saved.episodes.isEmpty && fallback.episodes.isNotEmpty) {
        await _put(
          saved.withPlayback(fallback.toPlayback(), now: saved.savedAt),
        );
      }
    }
    final gone = _lastGroups.difference(groups.keys.toSet());
    for (final key in gone) {
      if (_box?.containsKey(key) == true) await remove(key);
    }
    _lastGroups = groups.keys.toSet();
  }

  @override
  OfflineTitle? get(String contentUrl) {
    final raw = _box?.get(contentUrl);
    return raw is String ? _decode(contentUrl, raw) : null;
  }

  @override
  List<OfflineTitle> all() {
    final box = _box;
    if (box == null) return const [];
    return [
      for (final key in box.keys)
        if (box.get(key) case final String raw)
          if (_decode(key as Object, raw) case final OfflineTitle t) t,
    ];
  }

  @override
  Future<void> noteDetail(DetailEntity detail) async {
    final key = detail.contentUrl;
    if (key.isEmpty || Catalogue.isId(detail.provider)) return;
    final base =
        get(key) ??
        _seen[key] ??
        OfflineTitle(
          contentUrl: key,
          provider: detail.provider,
          title: detail.title,
          savedAt: 0,
        );
    await _note(base.withDetail(detail));
  }

  @override
  Future<void> noteEpisodes(
    PlaybackEntity playback, {
    String? contentUrl,
  }) async {
    final key = playback.contentUrl.isNotEmpty
        ? playback.contentUrl
        : (contentUrl ?? '');
    if (key.isEmpty || Catalogue.isId(playback.provider)) return;
    if (playback.episodes.isEmpty) return;
    final base =
        get(key) ??
        _seen[key] ??
        OfflineTitle(
          contentUrl: key,
          provider: playback.provider,
          title: '',
          savedAt: 0,
        );
    await _note(base.withPlayback(playback));
  }

  Future<void> _note(OfflineTitle title) async {
    _seen.remove(title.contentUrl);
    _seen[title.contentUrl] = title;
    while (_seen.length > _seenCap) {
      _seen.remove(_seen.keys.first);
    }
    if (_tracked(title.contentUrl)) await _put(title);
  }

  @override
  Future<void> save(OfflineTitle title) => _put(title);

  Future<void> _put(OfflineTitle title) async {
    final box = _box;
    if (box == null) return;
    // A title learnt from its list alone has no name yet; the rows have one.
    var named = title;
    if (named.title.isEmpty) {
      for (final item in _rows()) {
        if (item.groupKey == title.contentUrl && item.title.isNotEmpty) {
          named = OfflineTitle.fromItems([
            item,
          ]).withPlayback(title.toPlayback(), now: title.savedAt);
          break;
        }
      }
    }
    try {
      await box.put(
        named.contentUrl,
        jsonEncode(OfflineTitleModel.toJson(named)),
      );
      _revision.value++;
    } catch (e) {
      debugPrint('[offline] could not save ${named.contentUrl}: $e');
    }
  }

  @override
  Future<void> remove(String contentUrl) async {
    _seen.remove(contentUrl);
    final box = _box;
    if (box == null || !box.containsKey(contentUrl)) return;
    await box.delete(contentUrl);
    _decoded.remove(contentUrl);
    _revision.value++;
  }

  // Hive hands back the same String until a key is rewritten, and the rows
  // tick twice a second while anything downloads.
  final Map<Object, (String, OfflineTitle?)> _decoded = {};

  OfflineTitle? _decode(Object key, String raw) {
    final hit = _decoded[key];
    if (hit != null && identical(hit.$1, raw)) return hit.$2;
    final value = _parse(raw);
    _decoded[key] = (raw, value);
    return value;
  }

  OfflineTitle? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OfflineTitleModel.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}
