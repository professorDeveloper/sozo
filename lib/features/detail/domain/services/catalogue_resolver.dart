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

/// Where a catalogue title was found — or, when [approximate], where it might
/// be.
class CatalogueLink {
  const CatalogueLink({
    required this.providerId,
    required this.providerName,
    required this.contentUrl,
    this.catalogueId = '',
    this.providerImage = '',
    this.approximate = false,
  });

  final String providerId;
  final String providerName;
  final String contentUrl;

  /// Which catalogue the title came from — the page shows its mark next to
  /// the source's, so the hand-off is visible: "TMDB › VidAPI".
  final String catalogueId;
  final String providerImage;

  /// This source is not of the catalogue's kind, and is a guess rather than an
  /// answer.
  ///
  /// [CatalogueResolver.kindsFor] asks only the catalogue's own kind, so this
  /// is false for every link it makes today; older stored links may carry it.
  /// The title can be right and the WORK still wrong: a light novel and its manga adaptation share a name,
  /// which is exactly what makes the title score untrustworthy here. Anything
  /// that puts this in front of somebody has to say so; presenting it as a
  /// found source is the one thing this flag exists to prevent.
  final bool approximate;

  CatalogueLink withCatalogue(String id) => CatalogueLink(
    providerId: providerId,
    providerName: providerName,
    contentUrl: contentUrl,
    catalogueId: id,
    providerImage: providerImage,
    approximate: approximate,
  );

  String encode() => jsonEncode({
    'p': providerId,
    'n': providerName,
    'u': contentUrl,
    if (providerImage.isNotEmpty) 'i': providerImage,
    // Carried although [CatalogueResolver] never stores a guess: the day
    // something else does, a link that came back from Hive without this would
    // be a guess that had quietly stopped looking like one.
    if (approximate) 'g': true,
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
        approximate: m['g'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

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

  /// Whether anything was found — never whether it is the right WORK. A guess
  /// is found too: see [CatalogueLink.approximate], which is the only thing
  /// separating the two and which whatever renders this has to show.
  bool get found => link != null;
}

typedef AlternateFinder =
    Stream<AlternateSource> Function({
      required String title,
      required List<ProviderEntity> candidates,
      void Function(AlternateSearchOutcome outcome)? onOutcome,
    });

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
///
/// Only sources of the catalogue's own kind are asked. See [kindsFor].
class CatalogueResolver {
  CatalogueResolver({
    required AlternateFinder finder,
    required HiveService hive,
    required Future<List<ProviderEntity>> Function() providers,
    ContentMode Function(String providerId)? providerKind,
  }) : _find = finder,
       _hive = hive,
       _providers = providers,
       _kindOf = providerKind ?? _declaredKind;

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
    // ask is decided in [locate], by [ContentMode], where the vocabulary is one
    // enum — see [kindsFor].
    finder: ({required title, required candidates, onOutcome}) =>
        alternates.find(
          title: title,
          excludeProvider: '',
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

  /// What kind of thing a source carries.
  ///
  /// Handed in for one reason: [ContentModeX.contentMode] answers a `my:` id by
  /// looking the source up in the installed-repo store through the global
  /// service locator, so with no locator standing up there is no provider id
  /// that reads as [ContentMode.novel] — which would leave the novel path, the
  /// one all of this is for, the only path that cannot be exercised. Production
  /// passes nothing and gets the real lookup.
  final ContentMode Function(String providerId) _kindOf;

  static ContentMode _declaredKind(String providerId) => providerId.contentMode;

  static const String _tag = '[catalogue]';

  /// How long the fan-out is given once it has an answer worth taking.
  ///
  /// Sources still out at this point are the slow ones, and nothing they can
  /// say is worth making somebody wait for when there is already a match.
  static const Duration _budget = Duration(seconds: 8);

  /// And how long it is given when it has nothing at all.
  ///
  /// The eight seconds above used to be the whole of it, which made this the
  /// least patient search in the app while asking the most of it. A backend
  /// source is allowed ten seconds on its own ([CrossSearchEngine.defaultTimeout])
  /// and an extension host forty-five ([CrossSearchEngine.channelTimeout]),
  /// because the first search against a freshly-installed source has to
  /// download and dex-load its APK before it can issue a single request. So a
  /// title was reported as carried by nothing after eight — before a single
  /// on-device leg could have finished, and before even an HTTP leg's own
  /// timeout — and then opened first try when the viewer searched for it by
  /// hand. Same source, same title, different patience.
  ///
  /// Giving up is the expensive answer here, not waiting: it ends in a page
  /// with no Play button. And nobody is watching a spinner for it — the detail
  /// page renders the catalogue's own record first and fills the source in when
  /// it arrives, so this time is spent behind a page that is already up.
  static const Duration _patience = Duration(seconds: 25);

  static String _key(String catalogueId, String contentUrl) =>
      '$catalogueId|$contentUrl';

  CatalogueLink? remembered(String catalogueId, String contentUrl) =>
      CatalogueLink.decode(
        _hive.getCatalogueLink(_key(catalogueId, contentUrl)),
      )?.withCatalogue(catalogueId);

  Future<void> forget(String catalogueId, String contentUrl) =>
      _hive.setCatalogueLink(_key(catalogueId, contentUrl), null);

  /// A source the viewer picked for this catalogue title by hand: the page
  /// opens on it from now on, as it does on one the resolver found.
  Future<void> choose(
    String catalogueId,
    String contentUrl,
    CatalogueLink link,
  ) => _hive.setCatalogueLink(_key(catalogueId, contentUrl), link.encode());

  /// Which kinds of source a catalogue's titles are looked for on: only its
  /// own. A light novel is searched on novel sources, never on the manga
  /// readers, which carry its adaptation rather than the novel.
  static Set<ContentMode> kindsFor(Catalogue catalogue) => {catalogue.mode};

  /// What a source of the catalogue's own kind is worth in the ranking, and
  /// what one of the wrong kind costs.
  ///
  /// Ordering only, both of them: neither can lift a weak title match into one
  /// worth remembering. Sized against the title scores they are added to — a
  /// fifth of the range is enough to outweigh the spelling advantage a larger
  /// index tends to have, and not so much that a clearly better title loses.
  static const double _rightKind = 0.15;
  static const double _wrongKind = -0.2;

  /// How well a source's kind suits a catalogue's. Positive helps, negative
  /// hurts, zero is "cannot tell" — an on-device plugin whose category is
  /// its ecosystem's name says nothing about what it carries.
  ///
  /// A null [p] is that same "cannot tell", and it is not a production state:
  /// it means an answer arrived from a provider that was not among the ones
  /// asked, and [AlternateSourceService.find] only ever searches the candidate
  /// list it is handed. Only a hand-written finder in a test can reach it, so
  /// the zero it returns is what keeps such a fixture rankable rather than a
  /// deliberate score for anything real.
  double _fit(Catalogue? catalogue, ProviderEntity? p) {
    if (catalogue == null || p == null) return 0;
    final anime = p.category == 'anime' || p.id.startsWith('an:');
    final film = p.category == 'movies' || p.category == 'tmdb';
    return switch (catalogue) {
      Catalogue.anilist => anime ? _rightKind : (film ? _wrongKind : 0),
      Catalogue.tmdb => film ? _rightKind : (anime ? _wrongKind : 0),
      // The readers have no anime-versus-film split to weigh, and their
      // category is no help at all — a Mihon source's is the name of its
      // ecosystem. Mode is the only thing that separates a novel source from a
      // manga one, and on the light-novel shelf both are in the running, so
      // without an opinion here the guess would outrank the real answer on
      // spelling alone.
      //
      // The manga shelf keeps the order it had, but not because this arm sits
      // out: [kindsFor] widens nothing there, so every candidate is manga-mode
      // and every answer gets the same [_rightKind], and a constant added to
      // every score cannot reorder anything. It is uniform, not absent — the
      // day a wrong-kind reader is asked on that shelf, this moves the
      // ranking, which is the point.
      Catalogue.anilistManga || Catalogue.anilistNovel =>
        _kindOf(p.id) == catalogue.mode ? _rightKind : _wrongKind,
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

  /// One fan-out under one name.
  Future<_Sweep> _sweep({
    required String query,
    required MovieEntity hint,
    required Catalogue catalogue,
    required List<ProviderEntity> candidates,
    required Map<String, ProviderEntity> byId,
    required bool ownKindAsked,
  }) async {
    AlternateSource? best;
    TitleMatch? bestMatch;
    var bestRank = double.negativeInfinity;
    AlternateSearchOutcome? outcome;
    final done = Completer<void>();
    late final StreamSubscription<AlternateSource> sub;
    sub =
        _find(
          title: query,
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
            // Stop early on an answer nothing better can argue with: the same
            // title, from a source of the right kind — or, when no source of
            // the right kind was asked, from the best kind there is. A perfect
            // title from the wrong kind of source is worth waiting on only
            // while a right-kind source is still out there to wait for; when
            // none was asked, waiting buys a differently-spelled guess at the
            // cost of the whole budget. A disagreeing year has already pulled
            // [match] down to weak either way.
            if (match.confidence == TitleConfidence.exact &&
                (fit >= 0 || !ownKindAsked) &&
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
    // Two deadlines, not one: take what there is at [_budget], but hold on to
    // [_patience] rather than call a title uncarried on the strength of nothing
    // having answered yet.
    Timer? deadline;
    void settle() {
      if (!done.isCompleted) done.complete();
    }

    deadline = Timer(_budget, () {
      if (best != null) return settle();
      deadline = Timer(_patience - _budget, settle);
    });
    await done.future;
    deadline?.cancel();
    // Not awaited. All the fan-out's onCancel does is flip a flag that stops it
    // scheduling more legs, so there is nothing here worth a turn of the event
    // loop — and a cancel on a subscription whose stream has already finished is
    // not guaranteed to complete at all, which would leave this method hanging
    // on the one path where it had already got its answer.
    unawaited(sub.cancel());
    return _Sweep(
      best: best,
      match: bestMatch,
      rank: bestRank,
      outcome: outcome,
    );
  }

  /// The one other name worth asking for, or null.
  ///
  /// A catalogue knows a work by several names and a SOURCE does not get to
  /// choose: it indexes under whichever one its own site uses. Measured —
  /// animecube lists "Kaiju Girl Caramelise" and answers a search for
  /// "Otome Kaijuu Caramelise" with nothing at all, so a title it carries was
  /// recorded as carried by nothing and the page offered no Play button.
  ///
  /// One extra name, not all of them. Each pass costs up to [_patience], and
  /// AniList's third name is the original script — the least likely of the three
  /// to be what an aggregator indexes under, and the one most likely to be
  /// answered with a front page of unrelated rows. The first alternative is the
  /// transliteration, which is the one that pays.
  ///
  /// [already] is a name that has been asked; a catalogue that spells two of its
  /// names the same way, bar case or punctuation, is asked once.
  static String? _otherName(MovieEntity hint, String already) {
    final asked = TitleMatch.normalise(already);
    for (final name in hint.altTitles) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      if (TitleMatch.normalise(trimmed) == asked) continue;
      return trimmed;
    }
    return null;
  }

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

    // Every source of a kind this catalogue can be answered by, that is not
    // browse-only: an anime title is looked for on video sources, a manga title
    // on manga sources. A leg spent asking a reader for an anime is a leg not
    // spent on a source that might have it. A light novel is looked for on
    // novel sources only.
    final kinds = kindsFor(catalogue);
    final candidates = [
      for (final p in await _providers())
        if (!p.browseOnly && kinds.contains(_kindOf(p.id))) p,
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

    // Whether an answer of the catalogue's own kind can arrive at all.
    //
    // It decides how long the fan-out is allowed to hold out. It is always
    // true while [kindsFor] asks only the catalogue's own kind, so the stop below is exactly what it was, and an
    // anime shelf still waits out a film source's perfect title for the anime
    // source that may answer late.
    final ownKindAsked = candidates.any((p) => _kindOf(p.id) == catalogue.mode);

    // Under the catalogue's own name first, and under one of its other names
    // only if that found nothing worth keeping. See [_otherName].
    var sweep = await _sweep(
      query: hint.title,
      hint: hint,
      catalogue: catalogue,
      candidates: candidates,
      byId: byId,
      ownKindAsked: ownKindAsked,
    );
    final second = _otherName(hint, hint.title);
    if (!sweep.usable && second != null) {
      debugPrint('$_tag "${hint.title}" → retrying as "$second"');
      final retry = await _sweep(
        query: second,
        hint: hint,
        catalogue: catalogue,
        candidates: candidates,
        byId: byId,
        ownKindAsked: ownKindAsked,
      );
      // Keep whichever answer is actually better. A weak match under the
      // English name is still an answer, and the second pass finding nothing
      // must not throw it away.
      if (retry.rank > sweep.rank) sweep = retry;
    }
    final best = sweep.best;
    final bestMatch = sweep.match;
    final outcome = sweep.outcome;

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
    // Only a source outside the catalogue's kind can make this true.
    final approximate = _kindOf(pick.provider.id) != catalogue.mode;
    final link = CatalogueLink(
      providerId: pick.provider.id,
      providerName: pick.provider.name,
      contentUrl: pick.item.url,
      catalogueId: catalogueId,
      // From the provider list rather than the search result: the engine's
      // result refs do not always carry the image, and a blank mark next to
      // the catalogue's own is worse than none.
      providerImage: pick.provider.image ?? byId[pick.provider.id]?.image ?? '',
      approximate: approximate,
    );
    debugPrint(
      '$_tag "${hint.title}" → ${link.providerName} '
      '(${match.score.toStringAsFixed(2)} ${match.confidence.name}'
      '${approximate ? ', guess: not a ${catalogue.mode.id} source' : ''})',
    );
    // Remembered on the band, not on a number of this file's own. A weak match
    // is worth opening once — the viewer can see it is wrong and change it —
    // but pinning it means every future open of this title goes straight to a
    // guess, with no search to correct it.
    //
    // A guess is never remembered whatever the band says, because the band is
    // about the title and what is wrong here is the kind: "Spice and Wolf" off
    // a manga source scores 1.00 against the novel and is still not the novel.
    // Pinning it would turn one caveated offer into the permanent answer, with
    // no search left to find the novel source the viewer installs tomorrow.
    if (match.isTrustworthy && !approximate) {
      await _hive.setCatalogueLink(
        _key(catalogueId, contentUrl),
        link.encode(),
      );
    }
    return CatalogueResolution(catalogue: catalogue, link: link);
  }
}

/// What one pass of the fan-out came back with.
class _Sweep {
  const _Sweep({this.best, this.match, required this.rank, this.outcome});

  final AlternateSource? best;
  final TitleMatch? match;

  /// Title similarity plus the kind-of-source adjustment, for comparing two
  /// passes against each other. Negative infinity when nothing answered.
  final double rank;
  final AlternateSearchOutcome? outcome;

  /// Whether this is an answer worth stopping on.
  ///
  /// The band, not the number: a weak match is worth offering once and is not
  /// worth giving up the other name for, because the other name is exactly how a
  /// weak guess turns into the right title.
  bool get usable => match?.isTrustworthy ?? false;
}
