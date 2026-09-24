import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/tracker/data/tracker_link_store.dart';

/// One local title tied to one Trakt film or show.
///
/// Richer than an AniList link by two things Trakt needs: whether it is a
/// film or a show, and — for a show — which season the source's episode
/// numbers count within. A source page for "Season 2" numbers its episodes
/// from 1; Trakt wants season 2, episode 1, not episode 1 of the show.
class TraktLink {
  const TraktLink({
    required this.provider,
    required this.contentUrl,
    required this.traktId,
    required this.kind,
    required this.title,
    this.season,
    this.year,
    this.auto = false,
    this.updatedAt = 0,
  });

  final String provider;
  final String contentUrl;
  final int traktId;

  /// `movie` or `show`.
  final String kind;
  final String title;

  /// For a show: the season the source's numbering is within, or null when
  /// the source numbers the whole show absolutely (common for anime).
  final int? season;
  final int? year;

  /// Matched by the app rather than chosen: shown as a guess, never trusted
  /// over a choice.
  final bool auto;
  final int updatedAt;

  bool get isMovie => kind == 'movie';

  String get key => TrackerLinkStore.keyFor(provider, contentUrl);

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'contentUrl': contentUrl,
    'traktId': traktId,
    'kind': kind,
    'title': title,
    'season': ?season,
    'year': ?year,
    'auto': auto,
    'updatedAt': updatedAt,
  };

  static TraktLink? fromJson(Map<String, dynamic> j) {
    final id = (j['traktId'] as num?)?.toInt();
    final kind = j['kind'];
    if (id == null || id <= 0 || (kind != 'movie' && kind != 'show')) {
      return null;
    }
    return TraktLink(
      provider: (j['provider'] ?? '').toString(),
      contentUrl: (j['contentUrl'] ?? '').toString(),
      traktId: id,
      kind: kind as String,
      title: (j['title'] ?? '').toString(),
      season: (j['season'] as num?)?.toInt(),
      year: (j['year'] as num?)?.toInt(),
      auto: j['auto'] as bool? ?? false,
      updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// As the account sync stores it: the shared link row, with Trakt's id in
  /// `mediaId`.
  Map<String, dynamic> toSync() => {
    'key': key,
    'provider': provider,
    'contentId': contentUrl,
    'mediaId': traktId,
    'title': title,
    'kind': kind,
    'season': ?season,
    'auto': auto,
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(
      updatedAt,
    ).toIso8601String(),
  };
}

/// The title → Trakt map, on the device and synced to the account.
class TraktLinkStore {
  TraktLinkStore({Box? box}) : _override = box;

  final Box? _override;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  static const _linksKey = 'trakt_links';
  static const _tombsKey = 'trakt_link_tombstones';

  Map<String, TraktLink> _read() {
    final raw = _box.get(_linksKey);
    if (raw is! String || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: ?TraktLink.fromJson((e.value as Map).cast<String, dynamic>()),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, TraktLink> links) => _box.put(
    _linksKey,
    jsonEncode({for (final e in links.entries) e.key: e.value.toJson()}),
  );

  Map<String, int> _tombs() {
    final raw = _box.get(_tombsKey);
    if (raw is! String || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  TraktLink? get(String provider, String contentUrl) =>
      _read()[TrackerLinkStore.keyFor(provider, contentUrl)];

  List<TraktLink> all() => _read().values.toList();

  /// A user's choice always replaces a guess; a guess never replaces a choice.
  Future<void> save(TraktLink link) async {
    final links = _read();
    final existing = links[link.key];
    if (link.auto && existing != null && !existing.auto) return;
    links[link.key] = TraktLink(
      provider: link.provider,
      contentUrl: link.contentUrl,
      traktId: link.traktId,
      kind: link.kind,
      title: link.title,
      season: link.season,
      year: link.year,
      auto: link.auto,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _write(links);
    final tombs = _tombs()..remove(link.key);
    await _box.put(_tombsKey, jsonEncode(tombs));
  }

  Future<void> remove(String provider, String contentUrl) async {
    final key = TrackerLinkStore.keyFor(provider, contentUrl);
    final links = _read()..remove(key);
    await _write(links);
    final tombs = _tombs()..[key] = DateTime.now().millisecondsSinceEpoch;
    await _box.put(_tombsKey, jsonEncode(tombs));
  }

  /// Everything local, for the account to merge: links and removals.
  List<Map<String, dynamic>> pendingChanges() => [
    for (final l in _read().values) l.toSync(),
    for (final e in _tombs().entries)
      {
        'key': e.key,
        'deletedAt': DateTime.fromMillisecondsSinceEpoch(
          e.value,
        ).toIso8601String(),
      },
  ];

  /// The account's merged list replaces the local one.
  Future<void> applyRemote(List<dynamic> items) async {
    final links = <String, TraktLink>{};
    for (final raw in items) {
      if (raw is! Map || raw['deletedAt'] != null) continue;
      final key = (raw['key'] ?? '').toString();
      final contentUrl = (raw['contentId'] ?? '').toString();
      final l = TraktLink.fromJson({
        'provider': raw['provider'],
        'contentUrl': contentUrl,
        'traktId': raw['mediaId'],
        'kind': raw['kind'],
        'title': raw['title'],
        'season': raw['season'],
        'auto': raw['auto'],
        'updatedAt': DateTime.tryParse(
          '${raw['updatedAt']}',
        )?.millisecondsSinceEpoch,
      });
      if (l != null && key.isNotEmpty) links[key] = l;
    }
    await _write(links);
    await _box.delete(_tombsKey);
  }

  Future<void> clear() async {
    await _box.delete(_linksKey);
    await _box.delete(_tombsKey);
  }
}
