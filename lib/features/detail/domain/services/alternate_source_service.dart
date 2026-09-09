import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

/// One other source that appears to carry the same title.
class AlternateSource {
  const AlternateSource({
    required this.provider,
    required this.item,
    required this.score,
  });

  final ProviderRef provider;
  final MovieEntity item;

  /// 0..1 title similarity. Ordering only — never a threshold on its own, see
  /// [AlternateSourceService.rank].
  final double score;
}

/// Finding the thing you are watching on a source that still works.
///
/// A provider going down is not an exceptional event here: sources move
/// domains, mint short-lived tokens and sit behind challenges that stop
/// clearing, and when one does the viewer's only recourse has been to leave the
/// player, change provider by hand, search the title again and find their
/// episode. Everything needed to do that automatically already exists — the
/// cross-search engine searches every provider at once, and the episodes use
/// case turns a result into something playable — so this is the wiring, not new
/// machinery.
///
/// Deliberately NOT an automatic switch. A different source is a different dub,
/// a different subtitle set and sometimes a different cut, so silently moving
/// someone mid-episode would be a worse surprise than the error it replaced.
/// The player offers; the viewer picks.
class AlternateSourceService {
  AlternateSourceService({
    required CrossSearchEngine engine,
    required GetProvidersUseCase providers,
    required GetEpisodesUseCase episodes,
  })  : _engine = engine,
        _providers = providers,
        _episodes = episodes;

  static const String _tag = '[alt-source]';

  final CrossSearchEngine _engine;
  final GetProvidersUseCase _providers;
  final GetEpisodesUseCase _episodes;

  /// Search every *other* provider in the same category for [title].
  ///
  /// Category matters more than it looks. Searching an anime title across the
  /// film providers returns near-misses that all have to be read and rejected
  /// by hand, and the viewer is already one failure deep — the list has to be
  /// short and plausible or it is just more work.
  Stream<AlternateSource> find({
    required String title,
    required String excludeProvider,
    required String category,
  }) async* {
    if (title.trim().isEmpty) return;

    final snapshot = (await _providers()).getOrNull();
    if (snapshot == null) return;
    final all = snapshot.providers;

    final targets = all.where((p) {
      if (p.id == excludeProvider) return false;
      if (p.browseOnly) return false;
      // An empty category on either side means "unknown", and excluding on
      // unknown would quietly shrink the list for providers the backend has
      // not classified.
      if (category.isNotEmpty &&
          p.category.isNotEmpty &&
          p.category != category) {
        return false;
      }
      return true;
    }).map(ProviderRef.fromEntity).toList();

    if (targets.isEmpty) return;
    debugPrint('$_tag searching ${targets.length} sources for "$title"');

    await for (final result in _engine.search(set: targets, query: title)) {
      if (!result.hasItems) continue;
      final best = rank(result.items, title);
      if (best == null) continue;
      yield AlternateSource(
        provider: result.provider,
        item: best.$1,
        score: best.$2,
      );
    }
  }

  /// Best match for [title] among [items], or null when none is close enough.
  ///
  /// A source that answers a search for "Naruto" with its ten most recent
  /// uploads is common, and taking `items.first` from one of those puts an
  /// unrelated show at the top of a list the viewer is being asked to trust.
  /// The floor is deliberately loose rather than strict: these are different
  /// sources' spellings of the same show — transliterations, season suffixes,
  /// an added "(Uzbek tilida)" — so demanding a close match would throw away
  /// the correct answer more often than it removes a wrong one.
  @visibleForTesting
  (MovieEntity, double)? rank(List<MovieEntity> items, String title) {
    final want = _normalise(title);
    if (want.isEmpty) return null;

    MovieEntity? best;
    var bestScore = 0.0;
    for (final it in items) {
      final score = _similarity(want, _normalise(it.title));
      if (score > bestScore) {
        bestScore = score;
        best = it;
      }
    }
    if (best == null || bestScore < 0.35) return null;
    return (best, bestScore);
  }

  /// Turn a chosen alternate into something the player can be handed.
  ///
  /// Works for both shapes because [GetEpisodesUseCase] answers with both: a
  /// serial comes back with an episode list, a film with its sources already
  /// resolved.
  ///
  /// [episodeNumber] is matched by NUMBER, not by index. Two sources rarely
  /// agree on where a season starts or whether recaps and specials are in the
  /// list, so index 12 is routinely a different episode on each — and landing
  /// someone on the wrong episode of the right show is worse than telling them
  /// this source cannot continue from here.
  Future<PlayerArgs?> buildArgs({
    required AlternateSource source,
    required int? episodeNumber,
    required Map<String, String> headers,
    Duration resumeAt = Duration.zero,
  }) async {
    final playback = (await _episodes(
      source.item.url,
      provider: source.provider.id,
    ))
        .getOrNull();
    if (playback == null) {
      debugPrint('$_tag episodes failed for ${source.provider.id}');
      return null;
    }
    final List<EpisodeEntity> episodes = playback.episodes;

    if (playback.isSerial || episodes.isNotEmpty) {
      if (episodes.isEmpty) return null;
      var index = 0;
      if (episodeNumber != null && episodeNumber > 0) {
        index = episodes.indexWhere((e) => e.episode == episodeNumber);
        if (index < 0) return null;
      }
      return PlayerArgs(
        title: source.item.title,
        provider: source.provider.id,
        headers: headers,
        contentUrl: source.item.url,
        thumbnail: source.item.thumbnail,
        episodes: episodes,
        initialEpisodeIndex: index,
        // Switching source mid-episode should not restart it. The new provider
        // is a different file behind the same minute of the same show, so the
        // position carries over — that is the whole point of switching rather
        // than going back and starting again.
        resumePosition: resumeAt,
      );
    }

    if (playback.videoSources.isEmpty) return null;
    return PlayerArgs(
      title: source.item.title,
      provider: source.provider.id,
      headers: headers,
      contentUrl: source.item.url,
      thumbnail: source.item.thumbnail,
      videoSources: List.of(playback.videoSources),
      movieUrl: playback.playerSrc,
      resumePosition: resumeAt,
    );
  }

  // --- title matching ------------------------------------------------------

  /// Lowercase, strip punctuation and the decoration sources bolt on.
  ///
  /// The noise words are what these particular catalogues add — quality tags,
  /// "barcha qismlar", dub markers — and removing them is what makes an Uzbek
  /// listing comparable to an English one at all.
  static String _normalise(String raw) {
    var s = raw.toLowerCase();
    for (final word in const [
      'barcha qismlar',
      'uzbek tilida',
      "o'zbekcha",
      'ozbekcha',
      'tarjima',
      'kino',
      'serial',
      'full hd',
      'season',
      'sezon',
      'fasl',
      'subbed',
      'dubbed',
      'sub',
      'dub',
    ]) {
      s = s.replaceAll(word, ' ');
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9Ѐ-ӿ ]+'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Token overlap, weighted toward the shorter title.
  ///
  /// Plain Jaccard punishes the correct answer here: one source lists
  /// "Naruto" and another "Naruto Shippuden Uzbek tilida barcha qismlar", and
  /// the union is dominated by words only one of them has. Dividing by the
  /// smaller token set asks the question that actually matters — is the shorter
  /// title contained in the longer one.
  static double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final ta = a.split(' ').where((t) => t.length > 1).toSet();
    final tb = b.split(' ').where((t) => t.length > 1).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final shared = ta.intersection(tb).length;
    if (shared == 0) return 0;
    return shared / (ta.length < tb.length ? ta.length : tb.length);
  }
}
