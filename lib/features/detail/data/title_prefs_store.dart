import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';

/// What the viewer chose last time they watched a particular title.
///
/// ## The problem
///
/// Audio language is stored once, for the whole app. That is right for the
/// first episode of something new and wrong for everything after: people watch
/// one show dubbed and the next subbed, and a single global preference means
/// every switch silently re-points the other show too. Whichever they picked
/// most recently wins, and the other one fights them on every episode.
///
/// The same is true of the server: a title that only plays on the third mirror
/// makes you pick the third mirror again every episode, forever.
///
/// ## The rule
///
/// A per-title choice beats the global one; the global one is the default for a
/// title nothing is remembered about. So switching to dub on one show is
/// remembered *for that show*, and also updates what a brand-new show starts
/// on — which is almost always what someone means by changing it.
///
/// ## Bounded on purpose
///
/// One entry per title watched grows without limit over years, in a settings
/// box that is read at startup. [maxEntries] keeps it to the titles somebody is
/// actually watching; the oldest choice is the one least likely to be missed.
///
/// Every operation is best-effort: playback must keep working when the box is
/// unavailable, which is every widget test and the moments before Hive opens.
class TitlePrefsStore {
  /// Beyond this the least recently used title is dropped.
  ///
  /// Three hundred is far more than anyone is part-way through and small enough
  /// that the map stays trivial to read and write.
  static const int maxEntries = 300;

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  /// Provider and content url together, because the same show on two sources is
  /// two different sets of servers and languages.
  String _key(String provider, String contentUrl) => '$provider::$contentUrl';

  Map<String, dynamic> _load() {
    final raw = _box?.get(AppConstants.titlePrefsKey);
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  Map<String, dynamic>? _entry(String provider, String contentUrl) {
    if (contentUrl.isEmpty) return null;
    final row = _load()[_key(provider, contentUrl)];
    return row is Map ? row.map((k, v) => MapEntry(k.toString(), v)) : null;
  }

  /// The audio language last chosen for this title, or null.
  String? langFor(String provider, String contentUrl) {
    final value = _entry(provider, contentUrl)?['lang'];
    return (value is String && value.isNotEmpty) ? value : null;
  }

  /// The quality or server label last chosen for this title, or null.
  String? qualityFor(String provider, String contentUrl) {
    final value = _entry(provider, contentUrl)?['quality'];
    return (value is String && value.isNotEmpty) ? value : null;
  }

  Future<void> rememberLang(
    String provider,
    String contentUrl,
    String lang,
  ) =>
      _write(provider, contentUrl, 'lang', lang);

  Future<void> rememberQuality(
    String provider,
    String contentUrl,
    String quality,
  ) =>
      _write(provider, contentUrl, 'quality', quality);

  Future<void> _write(
    String provider,
    String contentUrl,
    String field,
    String value,
  ) async {
    if (contentUrl.isEmpty || value.isEmpty) return;
    final key = _key(provider, contentUrl);
    final map = Map<String, dynamic>.of(_load());
    final existing = map[key];
    final row = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    row[field] = value;
    row['at'] = DateTime.now().millisecondsSinceEpoch;

    // Re-inserted at the end so the eviction below drops the least recently
    // TOUCHED title rather than whichever happens to sort first.
    map.remove(key);
    map[key] = row;

    if (map.length > maxEntries) {
      final ordered = map.entries.toList()
        ..sort((a, b) => _at(a.value).compareTo(_at(b.value)));
      for (final e in ordered.take(map.length - maxEntries)) {
        map.remove(e.key);
      }
    }

    try {
      await _box?.put(AppConstants.titlePrefsKey, map);
    } catch (_) {}
  }

  static int _at(Object? row) =>
      (row is Map && row['at'] is int) ? row['at'] as int : 0;

  Future<void> clear() async {
    try {
      await _box?.delete(AppConstants.titlePrefsKey);
    } catch (_) {}
  }
}
