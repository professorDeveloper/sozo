import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';

/// Where a catalogue title was found.
class CatalogueLink {
  const CatalogueLink({
    required this.providerId,
    required this.providerName,
    required this.contentUrl,
    this.catalogueId = '',
    this.providerImage = '',
  });

  final String providerId;
  final String providerName;
  final String contentUrl;

  /// Which catalogue the title came from — the page shows its mark next to
  /// the source's, so the hand-off is visible: "TMDB › VidAPI".
  final String catalogueId;
  final String providerImage;

  CatalogueLink withCatalogue(String id) => CatalogueLink(
    providerId: providerId,
    providerName: providerName,
    contentUrl: contentUrl,
    catalogueId: id,
    providerImage: providerImage,
  );

  String encode() =>
      jsonEncode({'p': providerId, 'n': providerName, 'u': contentUrl});

  static CatalogueLink? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final p = m['p']?.toString() ?? '';
      final u = m['u']?.toString() ?? '';
      if (p.isEmpty || u.isEmpty) return null;
      return CatalogueLink(
        providerId: p,
        providerName: m['n']?.toString() ?? p,
        contentUrl: u,
        providerImage: m['i']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Turns a catalogue title into a source that has it.
///
/// A catalogue card is AniList's or TMDB's idea of a title — a name, a year, a
/// poster — with nothing behind it to play. This asks every installed source
/// of the right kind for that name at once, takes the closest answer, and
/// remembers it, so the second time the same title is opened there is no
/// search at all.
///
/// The search itself is [AlternateSourceService], which already existed for
/// "this source died mid-episode, find me another". Same fan-out, same ranking;
/// the only difference is that nothing is excluded, because there is no source
/// to move away from.
///
/// Silent by design, and agreed that way: Play uses the best answer, the page
/// says which source that was, and the viewer can change it. The alternative —
/// a list of sources to pick from before every title — is a tap before
/// playing, every time, for a decision most people do not want to make.
typedef AlternateFinder =
    Stream<AlternateSource> Function({
      required String title,
      required List<ProviderEntity> candidates,
    });

class CatalogueResolver {
  CatalogueResolver({
    required AlternateFinder finder,
    required HiveService hive,
    required Future<List<ProviderEntity>> Function() providers,
  }) : _find = finder,
       _hive = hive,
       _providers = providers;

  /// The production wiring: the alternate-source search over the sources the
  /// resolver picks, and the provider list from the same use case the picker
  /// reads.
  factory CatalogueResolver.using(
    AlternateSourceService alternates,
    HiveService hive,
    GetProvidersUseCase providers,
  ) => CatalogueResolver(
    // Category is left blank on purpose. A TMDB card says `movie` and the
    // providers say `movies` (or `tmdb`, or `anime`), and one letter of
    // difference silently excluded every source there was. Which sources to
    // ask is decided in [resolve], by mode, where the vocabulary is one enum.
    finder: ({required title, required candidates}) => alternates.find(
      title: title,
      excludeProvider: '',
      category: '',
      candidates: candidates,
    ),
    hive: hive,
    providers: () async =>
        (await providers()).getOrNull()?.providers ?? const [],
  );

  final AlternateFinder _find;
  final HiveService _hive;
  final Future<List<ProviderEntity>> Function() _providers;

  static const String _tag = '[catalogue]';

  /// A match this close ends the search early; the rest of the sources are
  /// not worth waiting for.
  static const double _confident = 0.92;

  /// Below this nothing is remembered. A weak match is worth opening once —
  /// the viewer can see it is wrong and change it — but not worth opening
  /// every time from now on.
  static const double _rememberFloor = 0.6;

  /// How long the fan-out is given before the best answer so far is taken.
  /// Sources that have not answered by then are the slow ones, and the page
  /// should not sit on a spinner for them.
  static const Duration _budget = Duration(seconds: 8);

  static String _key(String catalogueId, String contentUrl) =>
      '$catalogueId|$contentUrl';

  CatalogueLink? remembered(String catalogueId, String contentUrl) =>
      CatalogueLink.decode(
        _hive.getCatalogueLink(_key(catalogueId, contentUrl)),
      )?.withCatalogue(catalogueId);

  Future<void> forget(String catalogueId, String contentUrl) =>
      _hive.setCatalogueLink(_key(catalogueId, contentUrl), null);

  /// How well a source's kind suits a catalogue's. Positive helps, negative
  /// hurts, zero is "cannot tell" — an on-device plugin whose category is
  /// its ecosystem's name says nothing about what it carries.
  static double _fit(Catalogue? catalogue, ProviderEntity? p) {
    if (catalogue == null || p == null) return 0;
    final anime = p.category == 'anime' || p.id.startsWith('an:');
    final film = p.category == 'movies' || p.category == 'tmdb';
    return switch (catalogue) {
      Catalogue.anilist => anime ? 0.15 : (film ? -0.2 : 0),
      Catalogue.tmdb => film ? 0.15 : (anime ? -0.2 : 0),
    };
  }

  /// The source to open [hint] on, or null when nothing installed has it.
  Future<CatalogueLink?> resolve({
    required String catalogueId,
    required String contentUrl,
    required MovieEntity? hint,
  }) async {
    final known = remembered(catalogueId, contentUrl);
    if (known != null) return known;
    if (hint == null || hint.title.trim().isEmpty) return null;
    if (Catalogue.fromId(catalogueId) == null) return null;

    // Every source that plays video and is not browse-only. Both catalogues
    // are anime and film; a manga source cannot have the title, and a leg
    // spent asking it is a leg not spent on one that might.
    final candidates = [
      for (final p in await _providers())
        if (!p.browseOnly && p.id.contentMode == ContentMode.video) p,
    ];
    if (candidates.isEmpty) return null;
    final byId = {for (final p in candidates) p.id: p};
    final catalogue = Catalogue.fromId(catalogueId);

    AlternateSource? best;
    var bestScore = 0.0;
    final done = Completer<void>();
    late final StreamSubscription<AlternateSource> sub;
    sub = _find(title: hint.title, candidates: candidates).listen(
      (found) {
        var score = found.score;

        // The kind of source has to fit the kind of catalogue. An AniList
        // title is an anime; a film-and-series provider that happens to
        // carry the live-action of the same name is a worse answer than an
        // anime source that answers a little later, whatever the title
        // similarity says. The first live run picked exactly that: VidAPI's
        // 2023 ONE PIECE for AniList's 1999 one.
        final fit = _fit(catalogue, byId[found.provider.id]);
        score += fit;

        // The year is the cheapest disambiguator there is, and decisive. A
        // matching year lifts the score; a year known on both sides that
        // differs pulls it down hard enough that a same-title, right-year
        // answer beats it.
        final sameYear = hint.year != null && found.item.year == hint.year;
        final wrongYear =
            hint.year != null &&
            found.item.year != null &&
            found.item.year != hint.year;
        if (sameYear) score += 0.05;
        if (wrongYear) score -= 0.25;

        if (score > bestScore) {
          bestScore = score;
          best = found;
        }
        // Stop early only on an answer nothing argues with: right kind of
        // source, and the year not against it. A perfect title from the
        // wrong kind of source is exactly the case worth waiting on.
        if (bestScore >= _confident &&
            fit >= 0 &&
            !wrongYear &&
            !done.isCompleted) {
          done.complete();
        }
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(_budget, onTimeout: () {});
    await sub.cancel();

    final pick = best;
    if (pick == null) {
      debugPrint('$_tag nothing installed has "${hint.title}"');
      return null;
    }
    final link = CatalogueLink(
      providerId: pick.provider.id,
      providerName: pick.provider.name,
      contentUrl: pick.item.url,
      catalogueId: catalogueId,
      // From the provider list rather than the search result: the engine's
      // result refs do not always carry the image, and a blank mark next to
      // the catalogue's own is worse than none.
      providerImage: pick.provider.image ?? byId[pick.provider.id]?.image ?? '',
    );
    debugPrint(
      '$_tag "${hint.title}" → ${link.providerName} '
      '(${bestScore.toStringAsFixed(2)})',
    );
    if (bestScore >= _rememberFloor) {
      await _hive.setCatalogueLink(
        _key(catalogueId, contentUrl),
        link.encode(),
      );
    }
    return link;
  }
}
