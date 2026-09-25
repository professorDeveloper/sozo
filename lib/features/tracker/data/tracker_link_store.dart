import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// Remembers which entry on a tracker a locally-watched title corresponds to.
///
/// This mapping is the whole reason tracking works for sources a tracker has
/// never heard of. A CloudStream or Aniyomi extension gives us a title string
/// and a URL; the tracker wants a numeric media id. Nothing in either can derive
/// the other, so the association is stored once — by the user, or by an exact
/// title match — and reused for every episode after that.
///
/// Keyed by provider AND url: the same show carried by two sources is two
/// separate links, because the episode numbering often differs between them.
///
/// Subclassed rather than parameterised so each tracker names its own storage
/// while the merge, tombstone and wire rules stay in exactly one place — every
/// decision in them is invisible when wrong.
abstract class TrackerLinkStore {
  TrackerLinkStore({Box? box}) : _override = box;

  final Box? _override;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  /// Where this tracker's map lives. Two trackers must never share a key: each
  /// one's links die with that tracker's connection, and a shared map would
  /// take the other's associations down with it.
  String get linksKey;

  /// Where this tracker's pending unlinks live.
  String get tombstonesKey;

  Map<String, dynamic> _read() {
    final raw = _box.get(linksKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        // Corrupt value — treat as empty rather than crashing every lookup.
      }
    }
    return <String, dynamic>{};
  }

  Future<void> _write(Map<String, dynamic> map) =>
      _box.put(linksKey, jsonEncode(map));

  /// Keys unlinked here but not yet accepted by the server.
  ///
  /// Removing a row locally leaves nothing to upload, so without recording the
  /// removal the next sync would see the account's copy as new and put the link
  /// straight back.
  Map<String, dynamic> _readTombstones() {
    final raw = _box.get(tombstonesKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Future<void> _writeTombstones(Map<String, dynamic> map) =>
      _box.put(tombstonesKey, jsonEncode(map));

  /// The identity of a local title. Trimmed and lowercased so a URL that
  /// differs only in case does not create a second, unlinked entry.
  static String keyFor(String provider, String contentUrl) =>
      '${provider.trim().toLowerCase()}|${contentUrl.trim().toLowerCase()}';

  TrackerLink? get(String provider, String contentUrl) {
    if (contentUrl.trim().isEmpty) return null;
    final raw = _read()[keyFor(provider, contentUrl)];
    if (raw is Map) return TrackerLink.fromJson(raw.cast<String, dynamic>());
    return null;
  }

  int? mediaIdFor(String provider, String contentUrl) =>
      get(provider, contentUrl)?.mediaId;

  Future<void> save(TrackerLink link) async {
    if (link.contentUrl.trim().isEmpty || link.mediaId <= 0) return;
    final key = keyFor(link.provider, link.contentUrl);
    final map = _read()..[key] = link.toJson();
    await _write(map);
    // A re-link supersedes any pending unlink of the same title.
    final tombstones = _readTombstones()..remove(key);
    await _writeTombstones(tombstones);
  }

  Future<void> remove(String provider, String contentUrl) async {
    final key = keyFor(provider, contentUrl);
    final map = _read()..remove(key);
    await _write(map);
    final tombstones = _readTombstones()
      ..[key] = DateTime.now().toUtc().toIso8601String();
    await _writeTombstones(tombstones);
  }

  /// Everything this device has to tell the account: its links, and its unlinks.
  List<Map<String, dynamic>> pendingChanges() => [
    for (final raw in _read().values)
      if (raw is Map) _toWire(raw.cast<String, dynamic>()),
    for (final entry in _readTombstones().entries)
      {'key': entry.key, 'deletedAt': entry.value, 'updatedAt': entry.value},
  ];

  /// Replaces the local map with the account's merged answer.
  ///
  /// Tombstones are dropped only here — they must survive until a sync has
  /// actually accepted them, or an unlink made offline would be forgotten.
  Future<void> applyRemote(List<dynamic> items) async {
    final map = <String, dynamic>{};
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      final key = (item['key'] as String?)?.trim().toLowerCase();
      if (key == null || key.isEmpty) continue;
      // A tombstone is an instruction to forget, not a row to store.
      if (item['deletedAt'] != null) continue;
      map[key] = _fromWire(item);
    }
    await _write(map);
    await _writeTombstones(<String, dynamic>{});
  }

  Map<String, dynamic> _toWire(Map<String, dynamic> json) => {
    ...json,
    'key': keyFor(
      (json['provider'] ?? '').toString(),
      (json['contentUrl'] ?? '').toString(),
    ),
    'contentId': json['contentUrl'],
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(
      (json['linkedAt'] as num?)?.toInt() ?? 0,
    ).toUtc().toIso8601String(),
  };

  /// The server speaks `contentId`; this store is keyed by the URL it was built
  /// from. Named differently because on the TV the same field really is an id.
  Map<String, dynamic> _fromWire(Map<String, dynamic> item) => {
    'provider': item['provider'] ?? '',
    'contentUrl': item['contentId'] ?? '',
    'mediaId': item['mediaId'] ?? 0,
    'title': item['title'] ?? '',
    'coverImage': item['coverImage'],
    'totalEpisodes': item['totalEpisodes'],
    'linkedAt':
        DateTime.tryParse('${item['updatedAt']}')?.millisecondsSinceEpoch ?? 0,
    'auto': item['auto'] ?? false,
  };

  /// Every link, newest first — for a "linked titles" screen and for deciding
  /// whether an auto-match has already been attempted.
  List<TrackerLink> all() {
    final out = [
      for (final raw in _read().values)
        if (raw is Map) TrackerLink.fromJson(raw.cast<String, dynamic>()),
    ];
    out.sort((a, b) => b.linkedAt.compareTo(a.linkedAt));
    return out;
  }

  /// Drops every link.
  ///
  /// Called on sign-out: these describe what one account watches and where, and
  /// leaving them behind would attribute the next person's viewing to a
  /// stranger's list.
  Future<void> clear() async {
    await _box.delete(linksKey);
    await _box.delete(tombstonesKey);
  }
}

/// One local title tied to one AniList media id.
class TrackerLink {
  const TrackerLink({
    required this.provider,
    required this.contentUrl,
    required this.mediaId,
    required this.title,
    this.coverImage,
    this.totalEpisodes,
    this.linkedAt = 0,
    this.auto = false,
  });

  final String provider;
  final String contentUrl;
  final int mediaId;
  final String title;
  final String? coverImage;
  final int? totalEpisodes;
  final int linkedAt;

  /// True when the match was made by title rather than chosen by the user.
  /// Surfaced in the UI so a wrong automatic guess is visibly a guess.
  final bool auto;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'contentUrl': contentUrl,
    'mediaId': mediaId,
    'title': title,
    'coverImage': ?coverImage,
    'totalEpisodes': ?totalEpisodes,
    'linkedAt': linkedAt,
    'auto': auto,
  };

  factory TrackerLink.fromJson(Map<String, dynamic> j) => TrackerLink(
    provider: (j['provider'] ?? '').toString(),
    contentUrl: (j['contentUrl'] ?? '').toString(),
    mediaId: (j['mediaId'] as num?)?.toInt() ?? 0,
    title: (j['title'] ?? '').toString(),
    coverImage: j['coverImage'] as String?,
    totalEpisodes: (j['totalEpisodes'] as num?)?.toInt(),
    linkedAt: (j['linkedAt'] as num?)?.toInt() ?? 0,
    auto: j['auto'] as bool? ?? false,
  );
}
