import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// Why the last automatic download run stopped short, if it did.
enum AutoDownloadHold { none, wifi, storageCap, busy }

/// What the last automatic download run did, for the settings page.
class AutoDownloadStatus {
  const AutoDownloadStatus({
    required this.at,
    this.queued = 0,
    this.skipped = 0,
    this.hold = AutoDownloadHold.none,
  });

  final DateTime at;
  final int queued;

  /// Episodes that can only be saved after playing them once.
  final int skipped;
  final AutoDownloadHold hold;

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'queued': queued,
    'skipped': skipped,
    'hold': hold.name,
  };

  static AutoDownloadStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! int) return null;
    return AutoDownloadStatus(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      queued: (raw['queued'] as num?)?.toInt() ?? 0,
      skipped: (raw['skipped'] as num?)?.toInt() ?? 0,
      hold: AutoDownloadHold.values.firstWhere(
        (h) => h.name == raw['hold'],
        orElse: () => AutoDownloadHold.none,
      ),
    );
  }
}

/// Device-level switches for everything the app does by itself: downloading
/// followed titles, cleaning up after them, and preparing what comes next.
class AutomationSettings {
  AutomationSettings({Box? box}) : _override = box;

  final Box? _override;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  /// Ticks on every change, so open screens and the player can follow.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const List<int> keepLastChoices = [1, 2, 3, 5, 10];
  static const int defaultKeepLast = 3;

  static const int _gb = 1024 * 1024 * 1024;

  /// 0 is no cap.
  static const List<int> maxBytesChoices = [
    0,
    2 * _gb,
    5 * _gb,
    10 * _gb,
    20 * _gb,
  ];
  static const int defaultMaxBytes = 5 * _gb;

  /// 0 hides the prompt; auto-advance still happens at the end.
  static const List<int> upNextChoices = [0, 5, 10, 15, 20];
  static const int defaultUpNextSeconds = 10;

  /// Ids are remembered so a download the viewer deleted is not fetched again,
  /// but not forever.
  static const int _maxRemembered = 1000;

  bool _bool(String key, bool fallback) {
    final v = _box.get(key);
    return v is bool ? v : fallback;
  }

  int _choice(String key, List<int> choices, int fallback) {
    final v = _box.get(key);
    return v is int && choices.contains(v) ? v : fallback;
  }

  Future<void> _put(String key, Object value) async {
    await _box.put(key, value);
    revision.value++;
  }

  bool get autoDownloadEnabled =>
      _bool(AppConstants.autoDownloadEnabledKey, false);
  Future<void> setAutoDownloadEnabled(bool v) =>
      _put(AppConstants.autoDownloadEnabledKey, v);

  bool get autoDownloadWifiOnly =>
      _bool(AppConstants.autoDownloadWifiOnlyKey, true);
  Future<void> setAutoDownloadWifiOnly(bool v) =>
      _put(AppConstants.autoDownloadWifiOnlyKey, v);

  int get keepLast => _choice(
    AppConstants.autoDownloadKeepLastKey,
    keepLastChoices,
    defaultKeepLast,
  );
  Future<void> setKeepLast(int v) =>
      _put(AppConstants.autoDownloadKeepLastKey, v);

  int get maxBytes => _choice(
    AppConstants.autoDownloadMaxBytesKey,
    maxBytesChoices,
    defaultMaxBytes,
  );
  Future<void> setMaxBytes(int v) =>
      _put(AppConstants.autoDownloadMaxBytesKey, v);

  bool get autoDeleteWatched => _bool(AppConstants.autoDeleteWatchedKey, false);
  Future<void> setAutoDeleteWatched(bool v) =>
      _put(AppConstants.autoDeleteWatchedKey, v);

  bool get prefetchNextEpisode =>
      _bool(AppConstants.prefetchNextEpisodeKey, true);
  Future<void> setPrefetchNextEpisode(bool v) =>
      _put(AppConstants.prefetchNextEpisodeKey, v);

  bool get prefetchNextChapter =>
      _bool(AppConstants.prefetchNextChapterKey, true);
  Future<void> setPrefetchNextChapter(bool v) =>
      _put(AppConstants.prefetchNextChapterKey, v);

  int get upNextSeconds => _choice(
    AppConstants.upNextSecondsKey,
    upNextChoices,
    defaultUpNextSeconds,
  );
  Future<void> setUpNextSeconds(int v) =>
      _put(AppConstants.upNextSecondsKey, v);

  /// Downloads the automation started. Only these are ever cleaned up by it;
  /// anything the viewer saved by hand is theirs.
  List<String> get autoIds => _ids(AppConstants.autoDownloadIdsKey);

  /// Episodes that could not be downloaded without playing them first, so
  /// every run does not resolve them again.
  List<String> get skippedIds => _ids(AppConstants.autoDownloadSkippedKey);

  Future<void> rememberAuto(String id) =>
      _remember(AppConstants.autoDownloadIdsKey, id);
  Future<void> rememberSkipped(String id) =>
      _remember(AppConstants.autoDownloadSkippedKey, id);

  List<String> _ids(String key) {
    final raw = _box.get(key);
    return raw is List ? raw.whereType<String>().toList() : <String>[];
  }

  Future<void> _remember(String key, String id) async {
    final ids = _ids(key)
      ..remove(id)
      ..add(id);
    final trimmed = ids.length > _maxRemembered
        ? ids.sublist(ids.length - _maxRemembered)
        : ids;
    await _box.put(key, trimmed);
  }

  AutoDownloadStatus? get lastStatus =>
      AutoDownloadStatus.fromJson(_box.get(AppConstants.autoDownloadStatusKey));
  Future<void> setLastStatus(AutoDownloadStatus status) =>
      _put(AppConstants.autoDownloadStatusKey, status.toJson());
}
