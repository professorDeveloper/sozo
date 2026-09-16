import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/core/matching/title_match.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

/// One other source that appears to carry the same title.
class AlternateSource {
  const AlternateSource({
    required this.provider,
    required this.item,
    required this.match,
  });

  final ProviderRef provider;
  final MovieEntity item;

  /// How the source's spelling of the title compares to the one asked for.
  final TitleMatch match;

  /// 0..1 title similarity. Ordering only — never a threshold on its own.
  double get score => match.score;

  /// Which of the three bands this row is in.
  ///
  /// Carried rather than re-derived from [score] because the sheet has to
  /// render it and, before this, it rendered nothing: every row looked equally
  /// certain, so a guess and a match were the same card and the viewer had no
  /// way to tell which was which except by opening it.
  TitleConfidence get confidence => match.confidence;

  /// Whether this is good enough to pick for someone rather than offer them.
  bool get isTrustworthy => match.isTrustworthy;
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
/// How a search for other sources ended, beyond what it found.
///
/// The sheet used to render "no other source has this" for three different
/// situations: nothing matched, every source timed out, and the provider list
/// could not be loaded at all. They need different words.
class AlternateSearchOutcome {
  const AlternateSearchOutcome({
    this.asked = 0,
    this.failed = 0,
    this.unavailable = false,
  });

  /// Sources that answered at all.
  final int asked;

  /// Of those, how many failed rather than honestly having nothing.
  final int failed;

  /// The list of sources itself could not be loaded — usually the backend.
  final bool unavailable;
}

class AlternateSourceService {
  AlternateSourceService({
    required SearchFanOut engine,
    required GetProvidersUseCase providers,
    required GetEpisodesUseCase episodes,
  }) : _engine = engine,
       _providers = providers,
       _episodes = episodes;

  static const String _tag = '[alt-source]';

  /// The fan-out interface rather than [CrossSearchEngine] itself: everything
  /// here needs is `planLegs`, `search` and `searchProvider`, and the concrete
  /// engine reaches WebViews, a Dio client and the Mangayomi bridge, so taking
  /// the class made this service impossible to test without standing all three
  /// up.
  final SearchFanOut _engine;
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
    List<ProviderEntity>? candidates,
    void Function(AlternateSearchOutcome outcome)? onOutcome,
  }) async* {
    if (title.trim().isEmpty) return;

    // The caller's list when it has one, which is every source the app can
    // reach. Without it this asked GetProvidersUseCase, and that is the BACKEND
    // list alone — so a viewer whose library is mostly CloudStream or Aniyomi
    // was told nothing else had the title while a dozen installed sources did,
    // and the cross-search screen found them immediately.
    var all = candidates;
    if (all == null) {
      final snapshot = (await _providers()).getOrNull();
      if (snapshot == null) {
        // Not "nobody has it" — nobody was asked. The sheet says so rather than
        // reporting an outage as an answer.
        onOutcome?.call(const AlternateSearchOutcome(unavailable: true));
        return;
      }
      all = snapshot.providers;
    }

    final targets = all
        .where((p) {
          if (p.id == excludeProvider) return false;
          if (p.browseOnly) return false;
          if (!_categoryAllows(category, p.category)) return false;
          return true;
        })
        .map(ProviderRef.fromEntity)
        .toList();

    if (targets.isEmpty) {
      onOutcome?.call(const AlternateSearchOutcome());
      return;
    }

    // Capped like every other fan-out. Uncapped this is over an hour of wall
    // clock; it only stayed tolerable before because the backend-only list was
    // short by accident.
    final legs = _engine.planLegs(targets);
    debugPrint(
      '$_tag searching ${legs.length} of ${targets.length} sources for "$title"',
    );

    var failed = 0;
    var asked = 0;
    await for (final result in _engine.search(set: legs, query: title)) {
      asked++;
      if (!result.hasItems) {
        // "Timed out" and "does not have it" were the same `continue`, so the
        // sheet could not tell a dead source from an honest miss and neither
        // could the viewer.
        if (result.status != ProviderSearchStatus.ok) failed++;
        continue;
      }
      final best = rank(result.items, title);
      if (best == null) continue;
      yield AlternateSource(
        provider: result.provider,
        item: best.$1,
        match: best.$2,
      );
    }
    onOutcome?.call(AlternateSearchOutcome(asked: asked, failed: failed));
  }

  /// Ask ONE source, by id, for whatever it has for [query].
  ///
  /// Unranked and unfiltered on purpose. [find] and [rank] exist to keep a
  /// machine's guesses honest; this is the other half — the viewer typing the
  /// name themselves because the automatic answer was wrong or there was none.
  /// Filtering their own query against the title the catalogue happens to use
  /// would defeat the point: they may be searching the romaji, the dub's name
  /// or a spelling only this source uses, and the app has no standing to tell
  /// them their own search missed.
  ///
  /// The whole [ProviderSearchResult] comes back rather than a list, so a
  /// source that timed out can be told apart from one that honestly has
  /// nothing — the distinction the sheet already makes for [find].
  ///
  /// Null only when [providerId] is not a source this app can reach, which is a
  /// caller bug rather than an empty result.
  ///
  /// Goes through [SearchFanOut.searchProvider], which is the same call one leg
  /// of [find] makes: per-source timeouts, the extension-host budget and the
  /// health record all apply here exactly as they do there.
  Future<ProviderSearchResult?> searchOne({
    required String providerId,
    required String query,
    List<ProviderEntity>? candidates,
    int page = 1,
  }) async {
    if (query.trim().isEmpty) return null;
    var all = candidates;
    if (all == null) {
      final snapshot = (await _providers()).getOrNull();
      if (snapshot == null) return null;
      all = snapshot.providers;
    }
    ProviderEntity? entity;
    for (final p in all) {
      if (p.id == providerId) {
        entity = p;
        break;
      }
    }
    if (entity == null) return null;
    return _engine.searchProvider(
      ProviderRef.fromEntity(entity),
      query,
      page: page,
    );
  }

  /// Whether a provider's category is compatible with the title's.
  ///
  /// Only content categories are comparable. Extension providers are stamped
  /// with their ECOSYSTEM — `cloudstream`, `aniyomi`, `manga`, `mangayomi` —
  /// and comparing one of those against `anime` excluded every installed source
  /// on a value that was never a category in the first place.
  static const Set<String> _ecosystems = {
    'cloudstream',
    'aniyomi',
    'manga',
    'mangayomi',
  };

  static bool _categoryAllows(String want, String have) {
    if (want.isEmpty || have.isEmpty) return true;
    if (_ecosystems.contains(want) || _ecosystems.contains(have)) return true;
    return want == have;
  }

  /// Best match for [title] among [items], or null when none is close enough.
  ///
  /// A source that answers a search for "Naruto" with its ten most recent
  /// uploads is common, and taking `items.first` from one of those puts an
  /// unrelated show at the top of a list the viewer is being asked to trust.
  ///
  /// The scoring itself is [TitleMatch], and moving it there is the fix for a
  /// real ranking: a search for "Return of the Blossoming Blade" offered a row
  /// called "Return", one called "Blade of the Immortal" and one called "The
  /// Lord of the Rings: The Return of the King", because the formula that used
  /// to live here divided the shared words by the SHORTER title and so scored
  /// a one-word row 1.00. The knowledge that made this method worth having —
  /// that "barcha qismlar" and "(Uzbek tilida)" are decoration and not part of
  /// the name — moved with it and is [TitleMatch.normalise].
  ///
  /// Still returns rows that are only plausible, not only confident ones: this
  /// list is shown to somebody who explicitly asked what else has the title,
  /// and they can read a row and reject it. The band comes back with the match
  /// so the sheet can say which is which.
  @visibleForTesting
  (MovieEntity, TitleMatch)? rank(List<MovieEntity> items, String title) =>
      TitleMatch.best(items, query: title, titleOf: (it) => it.title);

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
    Duration resumeAt = Duration.zero,
  }) async {
    final playback = (await _episodes(
      source.item.url,
      provider: source.provider.id,
    )).getOrNull();
    if (playback == null) {
      debugPrint('$_tag episodes failed for ${source.provider.id}');
      return null;
    }
    final List<EpisodeEntity> episodes = playback.episodes;

    if (playback.isSerial || episodes.isNotEmpty) {
      if (episodes.isEmpty) return null;
      var window = playback;
      var index = 0;
      if (episodeNumber != null && episodeNumber > 0) {
        index = episodes.indexWhere((e) => e.episode == episodeNumber);
        if (index < 0) {
          // Only the first page came back — a hundred episodes. Episode 240
          // of a long run is on a later one, and "this source does not have
          // it" was the answer every long show got.
          final found = await _findOnLaterPage(source, playback, episodeNumber);
          if (found == null) return null;
          (window, index) = found;
        }
      }
      final size = playback.size > 0 ? playback.size : episodes.length;
      return PlayerArgs(
        title: source.item.title,
        provider: source.provider.id,
        // The NEW provider's headers. The caller used to pass the ones the
        // failing source was played with — its Referer, its cookies — which
        // the new host has no use for and some reject outright.
        headers: window.headers.isNotEmpty ? window.headers : playback.headers,
        contentUrl: source.item.url,
        thumbnail: source.item.thumbnail,
        episodes: window.episodes,
        initialEpisodeIndex: index,
        // Switching source mid-episode should not restart it. The new provider
        // is a different file behind the same minute of the same show, so the
        // position carries over — that is the whole point of switching rather
        // than going back and starting again.
        resumePosition: resumeAt,
        // Where this window sits in the run, so Next keeps working past the
        // page that was loaded — the same four the episode list passes.
        windowStart: (window.page - 1) * size,
        totalEpisodes: playback.total,
        pageSize: size,
        sort: playback.sort,
      );
    }

    if (playback.videoSources.isEmpty) return null;
    return PlayerArgs(
      title: source.item.title,
      provider: source.provider.id,
      headers: playback.headers,
      contentUrl: source.item.url,
      thumbnail: source.item.thumbnail,
      videoSources: List.of(playback.videoSources),
      movieUrl: playback.playerSrc,
      resumePosition: resumeAt,
    );
  }

  /// Finds episode [number] on a page past the first.
  ///
  /// The page the numbering says it should be on first, then its neighbours:
  /// a recap or a special in the list shifts an episode across a page boundary,
  /// rarely further. Three requests at most — this runs while somebody waits.
  Future<(PlaybackEntity, int)?> _findOnLaterPage(
    AlternateSource source,
    PlaybackEntity first,
    int number,
  ) async {
    if (first.totalPages < 2 || first.episodes.isEmpty) return null;
    final size = first.size > 0 ? first.size : first.episodes.length;
    if (size <= 0) return null;
    final base = first.episodes.first.episode;
    final ascending = first.sort.toLowerCase() != 'desc';
    final offset = ascending ? number - base : base - number;
    if (offset < 0) return null;
    final guess = offset ~/ size + 1;
    for (final page in [guess, guess + 1, guess - 1]) {
      if (page < 2 || page > first.totalPages) continue;
      final result = (await _episodes(
        source.item.url,
        page: page,
        size: size,
        sort: first.sort,
        provider: source.provider.id,
      )).getOrNull();
      if (result == null) continue;
      final i = result.episodes.indexWhere((e) => e.episode == number);
      if (i >= 0) return (result, i);
    }
    return null;
  }
}
