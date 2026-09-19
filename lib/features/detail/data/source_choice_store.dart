import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/matching/title_match.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

/// One title, on one source, as the viewer said it should be.
///
/// [subject] is the title we were looking FOR — the catalogue's spelling, the
/// one shown in the player — and [url] is the entry on [providerId] that the
/// viewer picked for it. Everything else is what the row needs to be drawn and
/// opened again without searching.
@immutable
class SourceChoice {
  const SourceChoice({
    required this.subject,
    required this.providerId,
    required this.providerName,
    required this.url,
    required this.title,
    this.thumbnail,
    this.at = 0,
  });

  final String subject;
  final String providerId;
  final String providerName;

  /// The entry's address on the source. This is the whole value of the record:
  /// nothing else here can be turned back into something playable.
  final String url;

  /// The source's own spelling, so the corrected row still shows what this
  /// source calls the show rather than what the catalogue calls it.
  final String title;

  final String? thumbnail;

  /// When it was chosen, milliseconds since epoch — the eviction order, and
  /// nothing else. See [SourceChoiceStore.maxEntries].
  final int at;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'provider': providerId,
    'providerName': providerName,
    'url': url,
    'title': title,
    if (thumbnail != null) 'thumbnail': thumbnail,
    'at': at,
  };

  static SourceChoice? fromJson(Map<String, dynamic> j) {
    final provider = (j['provider'] ?? '').toString();
    final url = (j['url'] ?? '').toString();
    if (provider.isEmpty || url.isEmpty) return null;
    return SourceChoice(
      subject: (j['subject'] ?? '').toString(),
      providerId: provider,
      providerName: (j['providerName'] ?? provider).toString(),
      url: url,
      title: (j['title'] ?? '').toString(),
      thumbnail: j['thumbnail'] as String?,
      at: (j['at'] as num?)?.toInt() ?? 0,
    );
  }

  /// The stored entry as the search result it stands in for.
  ///
  /// The rest of the detail feature moves [MovieEntity] around, and a corrected
  /// row has to be openable by exactly the same code as a row the matcher
  /// found — anything else would give the viewer's own choice a second,
  /// less-travelled path to playback.
  MovieEntity asItem() => MovieEntity(
    externalId: url,
    title: title,
    description: '',
    slug: url,
    url: url,
    provider: providerId,
    thumbnail: thumbnail,
    year: null,
    rating: null,
    qualities: null,
    category: '',
  );
}

/// Which entry on a source the viewer said was the right one.
///
/// ## Why this exists
///
/// Matching a catalogue title to a source's listing of it is guesswork, and
/// guesswork is wrong sometimes however good it gets: sources carry a show
/// under its romaji, its dub's name, a season-split title or a misspelling, and
/// no amount of scoring recovers a name that simply is not the same name. The
/// only thing that always works is the person who can see both titles saying
/// which is which — and that correction is worth nothing if it has to be made
/// again on the next episode.
///
/// ## Why it is a third store and not a fourth mechanism
///
/// [TrackerLinkStore] already answers "which entry on AniList is this local
/// title", and [CatalogueResolver] already answers "which source has this
/// catalogue title". This is the third edge of the same triangle — which entry
/// on a SOURCE is this title — and it is stored the way both of those are: a
/// JSON map in the settings box, keyed by the two things that identify the
/// association and nothing else.
///
/// It is deliberately NOT folded into the catalogue link. That one is keyed by
/// catalogue id, holds exactly one source per title, and is overwritten every
/// time the resolver runs; corrections are per SOURCE and there can be several
/// for one title, because the viewer may fix the row for two different sources
/// before picking one to play.
///
/// ## Bounded, and best-effort
///
/// The map is read whenever the source switcher opens, so it is capped at
/// [maxEntries] with the least recently chosen entry dropped first. Every
/// operation swallows storage failures: the switcher must open when Hive has
/// not finished opening, which is every widget test and the first frames after
/// launch. A correction that cannot be saved costs one re-pick; a switcher that
/// throws costs the whole feature.
class SourceChoiceStore {
  SourceChoiceStore({Box? box}) : _override = box;

  final Box? _override;

  /// Where the map lives inside the settings box.
  ///
  /// A literal rather than an [AppConstants] member because this store is owned
  /// by the detail feature and nothing outside it reads the map; if a second
  /// feature ever needs it, that is the moment it earns a shared constant.
  static const String storeKey = 'source_choices';

  /// Beyond this the least recently chosen correction is dropped.
  ///
  /// Matches [TitlePrefsStore]'s ceiling for the same reason: this map is read
  /// on a user-facing open, and the titles somebody is actually part-way
  /// through number in the tens, not the thousands.
  static const int maxEntries = 300;

  Box? get _box {
    if (_override != null) return _override;
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  /// The identity of a correction: the title being looked for, and the source
  /// it was corrected on.
  ///
  /// The title goes through [TitleMatch.normalise] so that the same show asked
  /// for as "Naruto Shippuden" and "Naruto: Shippuuden" is one subject rather
  /// than two — the caller's spelling varies with which catalogue opened the
  /// player, and a correction that only applies to one spelling of the question
  /// is a correction the viewer has to make twice.
  static String keyFor(String subject, String providerId) {
    final normalised = TitleMatch.normalise(subject);
    final key = normalised.isEmpty ? subject.trim().toLowerCase() : normalised;
    return '$key|${providerId.trim().toLowerCase()}';
  }

  Map<String, dynamic> _load() {
    final raw = _box?.get(storeKey);
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Corrupt value — one lost map is better than a switcher that cannot
      // open.
    }
    return const {};
  }

  SourceChoice? _decode(Object? raw) => raw is Map
      ? SourceChoice.fromJson(raw.cast<String, dynamic>())
      : null;

  /// What the viewer chose for [subject] on [providerId], or null.
  SourceChoice? get(String subject, String providerId) {
    if (subject.trim().isEmpty || providerId.isEmpty) return null;
    return _decode(_load()[keyFor(subject, providerId)]);
  }

  /// Every correction made for [subject], newest first.
  ///
  /// The switcher needs all of them at once: a corrected source must appear in
  /// the list even when this run's automatic search did not find it at all,
  /// which is the usual case — the reason it was corrected is that the matcher
  /// could not see the connection.
  List<SourceChoice> forSubject(String subject) {
    if (subject.trim().isEmpty) return const [];
    final suffix = TitleMatch.normalise(subject);
    final want = suffix.isEmpty ? subject.trim().toLowerCase() : suffix;
    final out = <SourceChoice>[];
    for (final entry in _load().entries) {
      final cut = entry.key.lastIndexOf('|');
      if (cut < 0 || entry.key.substring(0, cut) != want) continue;
      final choice = _decode(entry.value);
      if (choice != null) out.add(choice);
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  Future<void> remember(SourceChoice choice) async {
    if (choice.url.trim().isEmpty || choice.providerId.trim().isEmpty) return;
    if (choice.subject.trim().isEmpty) return;
    final key = keyFor(choice.subject, choice.providerId);
    final map = Map<String, dynamic>.of(_load());
    // Re-inserted at the end so eviction drops the least recently TOUCHED
    // correction rather than whichever happens to sort first.
    map.remove(key);
    map[key] = SourceChoice(
      subject: choice.subject,
      providerId: choice.providerId,
      providerName: choice.providerName,
      url: choice.url,
      title: choice.title,
      thumbnail: choice.thumbnail,
      at: choice.at > 0 ? choice.at : DateTime.now().millisecondsSinceEpoch,
    ).toJson();

    if (map.length > maxEntries) {
      final ordered = map.entries.toList()
        ..sort((a, b) => _at(a.value).compareTo(_at(b.value)));
      for (final e in ordered.take(map.length - maxEntries)) {
        map.remove(e.key);
      }
    }
    await _put(map);
  }

  Future<void> forget(String subject, String providerId) async {
    final map = Map<String, dynamic>.of(_load())
      ..remove(keyFor(subject, providerId));
    await _put(map);
  }

  Future<void> clear() async {
    try {
      await _box?.delete(storeKey);
    } catch (_) {}
  }

  Future<void> _put(Map<String, dynamic> map) async {
    try {
      await _box?.put(storeKey, jsonEncode(map));
    } catch (_) {}
  }

  static int _at(Object? row) =>
      (row is Map && row['at'] is int) ? row['at'] as int : 0;
}
