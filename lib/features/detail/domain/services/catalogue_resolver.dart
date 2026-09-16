import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/matching/title_match.dart';
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

  String encode() => jsonEncode({
    'p': providerId,
    'n': providerName,
    'u': contentUrl,
    if (providerImage.isNotEmpty) 'i': providerImage,
  });

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
/// Why a catalogue title could not be opened.
///
/// One message was shown for all of these — "None of your sources has this
/// title" — and for most of them it was simply untrue. Somebody who opens a
/// manga from the AniList manga shelf with no reader installed was told their
/// sources do not carry Berserk; what was actually wrong is that there was
/// nothing to ask. These are not shades of one failure, they are four different
/// things for the reader to do next, so the page needs to know which happened.
enum CatalogueMiss {
  /// Nothing to search with: no title on the card, or an id that is not a
  /// catalogue's. A bug upstream rather than anything the reader can fix.
  nothingToSearch,

  /// No source of this catalogue's KIND is installed — no reader for a manga,
  /// no player for an anime. Nothing was asked, so nothing was missing.
  noSourcesOfKind,

  /// Sources of the right kind were asked, and answered, and none of them
  /// lists this title. The only one of these that the old message described.
  notCarried,

  /// The sources were asked and did not answer: every leg failed, or the
  /// search ran out of time. Says nothing about whether they carry the title.
  sourcesUnreachable,
}

/// What [CatalogueResolver.locate] found, and when it found nothing, why.
@immutable
class CatalogueResolution {
  const CatalogueResolution({required this.catalogue, this.link, this.miss});

  /// The catalogue the title came from — null only when the id was not one.
  /// Its [Catalogue.mode] is which kind of source was looked at.
  final Catalogue? catalogue;

  final CatalogueLink? link;

  /// Null exactly when [link] is not.
  final CatalogueMiss? miss;

  bool get found => link != null;
}

typedef AlternateFinder =
    Stream<AlternateSource> Function({
      required String title,
      required List<ProviderEntity> candidates,
      void Function(AlternateSearchOutcome outcome)? onOutcome,
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
    finder: ({required title, required candidates, onOutcome}) =>
        alternates.find(
          title: title,
          excludeProvider: '',
          category: '',
          candidates: candidates,
          onOutcome: onOutcome,
        ),
    hive: hive,
    providers: () async =>
        (await providers()).getOrNull()?.providers ?? const [],
  );

  final AlternateFinder _find;
  final HiveService _hive;
  final Future<List<ProviderEntity>> Function() _providers;

  static const String _tag = '[catalogue]';

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
      // The readers have no anime-versus-film split to weigh.
      Catalogue.anilistManga || Catalogue.anilistNovel => 0,
    };
  }

  /// The source to open [hint] on, or null when nothing installed has it.
  ///
  /// Kept for callers that only need the answer. Anything that has to TELL
  /// somebody why there was no answer wants [locate] instead — see
  /// [CatalogueMiss].
  Future<CatalogueLink?> resolve({
    required String catalogueId,
    required String contentUrl,
    required MovieEntity? hint,
  }) async => (await locate(
    catalogueId: catalogueId,
    contentUrl: contentUrl,
    hint: hint,
  )).link;

  /// The source to open [hint] on, or which of the four ways it was missing.
  Future<CatalogueResolution> locate({
    required String catalogueId,
    required String contentUrl,
    required MovieEntity? hint,
  }) async {
    final catalogue = Catalogue.fromId(catalogueId);
    final known = remembered(catalogueId, contentUrl);
    if (known != null) {
      return CatalogueResolution(catalogue: catalogue, link: known);
    }
    if (catalogue == null || hint == null || hint.title.trim().isEmpty) {
      return CatalogueResolution(
        catalogue: catalogue,
        miss: CatalogueMiss.nothingToSearch,
      );
    }

    // Every source of the catalogue's own kind that is not browse-only: an
    // anime title is looked for on video sources, a manga title on manga
    // sources. A leg spent asking a reader for an anime is a leg not spent
    // on a source that might have it.
    final candidates = [
      for (final p in await _providers())
        if (!p.browseOnly && p.id.contentMode == catalogue.mode) p,
    ];
    if (candidates.isEmpty) {
      // Not "nobody has it" — nobody was asked, and this is the common way to
      // see the message: opening a manga with no reader installed, which is
      // the state every install starts in.
      debugPrint('$_tag no ${catalogue.mode.id} source installed');
      return CatalogueResolution(
        catalogue: catalogue,
        miss: CatalogueMiss.noSourcesOfKind,
      );
    }
    final byId = {for (final p in candidates) p.id: p};

    AlternateSource? best;
    TitleMatch? bestMatch;
    var bestRank = double.negativeInfinity;
    AlternateSearchOutcome? outcome;
    final done = Completer<void>();
    late final StreamSubscription<AlternateSource> sub;
    sub =
        _find(
          title: hint.title,
          candidates: candidates,
          onOutcome: (o) => outcome = o,
        ).listen(
          (found) {
            // The year, applied by the matcher rather than by a second rule
            // here: it is the cheapest disambiguator there is, a year that
            // agrees is worth little and a year that disagrees is worth a
            // great deal, and [TitleMatch.withYear] is the one place that
            // knows by how much.
            final match = found.match.withYear(
              queryYear: hint.year,
              candidateYear: found.item.year,
            );

            // The kind of source has to fit the kind of catalogue. An AniList
            // title is an anime; a film-and-series provider that happens to
            // carry the live-action of the same name is a worse answer than an
            // anime source that answers a little later, whatever the title
            // similarity says. The first live run picked exactly that: VidAPI's
            // 2023 ONE PIECE for AniList's 1999 one.
            //
            // Ordering only. It can reorder two answers; it can never turn a
            // weak match into one worth remembering, which is decided on the
            // band and not on this number.
            final fit = _fit(catalogue, byId[found.provider.id]);
            final ranked = match.score + fit;

            if (ranked > bestRank) {
              bestRank = ranked;
              bestMatch = match;
              best = found;
            }
            // Stop early only on an answer nothing argues with: the same title,
            // from the right kind of source. A perfect title from the wrong
            // kind of source is exactly the case worth waiting on, and a
            // disagreeing year has already pulled [match] down to weak.
            if (match.confidence == TitleConfidence.exact &&
                fit >= 0 &&
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
    final match = bestMatch;
    if (pick == null || match == null) {
      // Which of these it is decides what the page says. A run where every leg
      // failed, or where the budget expired before the fan-out reported, has
      // not established that nothing carries the title — it has established
      // nothing at all.
      final report = outcome;
      final unreachable =
          report == null ||
          report.unavailable ||
          (report.asked > 0 && report.failed == report.asked);
      debugPrint(
        '$_tag "${hint.title}" not found on ${candidates.length} sources '
        '(${unreachable ? 'unreachable' : 'not carried'})',
      );
      return CatalogueResolution(
        catalogue: catalogue,
        miss: unreachable
            ? CatalogueMiss.sourcesUnreachable
            : CatalogueMiss.notCarried,
      );
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
      '(${match.score.toStringAsFixed(2)} ${match.confidence.name})',
    );
    // Remembered on the band, not on a number of this file's own. A weak match
    // is worth opening once — the viewer can see it is wrong and change it —
    // but pinning it means every future open of this title goes straight to a
    // guess, with no search to correct it.
    if (match.isTrustworthy) {
      await _hive.setCatalogueLink(
        _key(catalogueId, contentUrl),
        link.encode(),
      );
    }
    return CatalogueResolution(catalogue: catalogue, link: link);
  }
}
