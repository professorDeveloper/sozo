import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/matching/title_match.dart';
import 'package:soplay/core/network/image_headers.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/detail/data/source_choice_store.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/detail/presentation/widgets/source_search_sheet.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';

/// "This source is down — here is who else has it."
///
/// Opened from two places: the player's error screen, where a source has just
/// failed, and the detail page, where someone would rather not find out the
/// hard way. Both want the same thing — this title, playing, somewhere else.
///
/// Results stream in per provider rather than arriving as one list. Someone
/// already waiting on a failure is better served by the first working source
/// after two seconds than a complete list after fifteen; sources that answer
/// late simply appear below the ones that answered early.
///
/// ## Three things the list has to admit
///
/// A row used to be a source's name and a title, drawn identically whether the
/// match was certain or a coincidence. That is how a viewer came to read the
/// whole feature as broken: four of the six rows offered for "Return of the
/// Blossoming Blade" were other shows entirely, and nothing on screen
/// distinguished them from the two that were right. So:
///
/// 1. every row says how sure the match is, in a word and an icon rather than
///    in a colour, because a colour survives neither a screenshot nor a
///    colour-blind reader;
/// 2. every row offers **Wrong title?**, which searches that one source by
///    hand — an automatic matcher is wrong sometimes no matter how good it
///    gets, and the person looking at both titles can settle it instantly;
/// 3. sources that matched nothing are still listed, quietly, with the same
///    by-hand search. They used to vanish, which meant the only sources a
///    viewer could correct were the ones that did not need correcting — and a
///    stricter matcher makes more of them vanish, not fewer.
///
/// A correction is remembered ([SourceChoiceStore]) so it survives the episode,
/// the sheet and the app.
///
/// Returns the [PlayerArgs] for the source the viewer picked, or null.
class AlternateSourceSheet extends StatefulWidget {
  const AlternateSourceSheet._({
    required this.title,
    required this.provider,
    required this.category,
    required this.episodeNumber,
    this.resumeAt = Duration.zero,
  }) : candidates = null,
       choices = null;

  /// The sheet with its two collaborators supplied rather than looked up.
  ///
  /// [show] reads the installed sources off [ProviderBloc] and the corrections
  /// out of the settings box, neither of which exists in a widget test; this
  /// constructor is how a test drives the same widget with a known source list
  /// and its own storage.
  @visibleForTesting
  const AlternateSourceSheet.withDependencies({
    super.key,
    required this.title,
    required this.provider,
    required this.category,
    required this.episodeNumber,
    this.resumeAt = Duration.zero,
    required this.candidates,
    required this.choices,
  });

  final String title;
  final String provider;
  final String category;
  final int? episodeNumber;

  /// Where the viewer is now, carried onto the source they pick.
  ///
  /// Zero when the sheet opens from a playback failure — there is nothing to
  /// resume to. Non-zero when they chose to switch mid-episode, which is the
  /// case that must not restart it.
  final Duration resumeAt;

  /// Every source the app can reach, or null to read them off [ProviderBloc].
  final List<ProviderEntity>? candidates;

  /// Where corrections are read and written, or null for the real store.
  final SourceChoiceStore? choices;

  static Future<PlayerArgs?> show(
    BuildContext context, {
    required String title,
    required String provider,
    required String category,
    required int? episodeNumber,
    Duration resumeAt = Duration.zero,
  }) async {
    final picked = await _open(
      context,
      title: title,
      provider: provider,
      category: category,
      episodeNumber: episodeNumber,
      resumeAt: resumeAt,
    );
    return picked is PlayerArgs ? picked : null;
  }

  /// For manga and novels: the source picked, to open its own page — its
  /// chapter list — rather than a player. [show] built playback arguments
  /// for whatever was picked, so finding a manga on another source opened
  /// the video player on it.
  static Future<AlternateSource?> pickToRead(
    BuildContext context, {
    required String title,
    required String provider,
    required String category,
  }) async {
    final picked = await _open(
      context,
      title: title,
      provider: provider,
      category: category,
      episodeNumber: null,
    );
    return picked is AlternateSource ? picked : null;
  }

  static Future<Object?> _open(
    BuildContext context, {
    required String title,
    required String provider,
    required String category,
    required int? episodeNumber,
    Duration resumeAt = Duration.zero,
  }) {
    return showAdaptiveModal<Object>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AlternateSourceSheet._(
        title: title,
        provider: provider,
        category: category,
        episodeNumber: episodeNumber,
        resumeAt: resumeAt,
      ),
    );
  }

  @override
  State<AlternateSourceSheet> createState() => _AlternateSourceSheetState();
}

/// One line of the list, whatever produced it.
///
/// A row the matcher found and a row the viewer corrected are the same tap with
/// the same consequence, so they are the same type — the only difference the UI
/// draws is the badge, and that is exactly the difference worth drawing.
class _Row {
  const _Row({required this.source, required this.chosen});

  final AlternateSource source;

  /// True when the viewer picked this entry by hand. It outranks the score:
  /// nothing the matcher computes is evidence against someone who read both
  /// titles.
  final bool chosen;

  ProviderRef get provider => source.provider;
}

class _AlternateSourceSheetState extends State<AlternateSourceSheet> {
  /// Torrent streaming is Android-only — the engine is a native Android
  /// library. Hidden elsewhere rather than shown and failing.
  static bool get _torrentsAvailable => !kIsWeb && Platform.isAndroid;

  final List<AlternateSource> _found = [];
  StreamSubscription<AlternateSource>? _sub;
  bool _searching = true;

  /// Set while an entry is being turned into PlayerArgs, so the row can show a
  /// spinner and the rest of the list stops accepting taps. Fetching an episode
  /// list is a network call, and without this a second tap starts a second one.
  String? _preparing;

  /// The source whose Play just failed, and what to say about it.
  ///
  /// Shown ON the tile. This used to be a snackbar — which a modal bottom sheet
  /// covers, so the one thing that explained why nothing happened was drawn
  /// underneath the sheet the viewer was looking at. From the outside it was a
  /// Play button that did nothing at all.
  ({String provider, String message})? _failed;

  /// How the run ended, so the empty state can say which kind of empty.
  AlternateSearchOutcome? _outcome;

  /// The sources this device can reach, which is more than the backend knows
  /// about. Held rather than read on demand because the by-hand search needs
  /// the same list the automatic one used.
  List<ProviderEntity> _candidates = const [];

  late final SourceChoiceStore _choices =
      widget.choices ?? SourceChoiceStore();

  /// The viewer's corrections for this title, by provider id.
  final Map<String, SourceChoice> _corrections = {};

  /// Collapsed by default: this is the section for sources that had nothing to
  /// say, and on a device with extensions installed it is long. It exists to be
  /// reachable, not to be read.
  bool _showSilent = false;

  @override
  void initState() {
    super.initState();
    // Every source the app can reach, not only the ones the backend serves.
    // The bloc is the only place the installed extension sources exist.
    _candidates = widget.candidates ?? _fromBloc();
    for (final choice in _choices.forSubject(widget.title)) {
      _corrections[choice.providerId] = choice;
    }
    _sub = getIt<AlternateSourceService>()
        .find(
          title: widget.title,
          excludeProvider: widget.provider,
          titleProvider: widget.provider,
          candidates: _candidates.isEmpty ? null : _candidates,
          onOutcome: (o) {
            if (mounted) setState(() => _outcome = o);
          },
        )
        .listen(
          (s) {
            if (!mounted) return;
            setState(() {
              _found.add(s);
              // Best match first. The list grows while it is on screen, so this
              // is a re-sort rather than a sorted insert — it is a handful of
              // entries and the alternative is watching rows jump around less
              // predictably than they do now.
              _found.sort((a, b) => b.score.compareTo(a.score));
            });
          },
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
          onError: (_) {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  List<ProviderEntity> _fromBloc() {
    final state = context.read<ProviderBloc>().state;
    return state is ProviderLoaded ? state.usableProviders : const [];
  }

  /// Which kind of empty this is.
  ///
  /// "No other source has it" was shown for every one of these, and for most of
  /// them it was a claim the run never established. Asking twenty sources and
  /// being told no is an answer; asking twenty and having them all time out is
  /// not, and neither is asking none at all. They lead to different next steps,
  /// so they get different sentences.
  String _emptyMessage() {
    final outcome = _outcome;
    // The stream ended without reporting — an error on the way out. Nothing was
    // established either way, and saying so beats inventing a result.
    if (outcome == null) return 'player.alt_no_answer'.tr();
    if (outcome.unavailable) return 'player.alt_unavailable'.tr();
    // Nobody was asked: no other installed source handles this kind of title.
    if (outcome.asked == 0) return 'player.alt_none_asked'.tr();
    if (outcome.failed >= outcome.asked) return 'player.alt_all_failed'.tr();
    if (outcome.failed > 0) {
      return 'player.alt_some_failed'.tr(args: ['${outcome.failed}']);
    }
    // Asked, answered, and every answer was about a different show. This is the
    // only branch the old single message actually described.
    return 'player.alt_no_match'.tr(args: ['${outcome.asked}']);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// The list as drawn: corrections first, then the matcher's rows by score.
  ///
  /// A correction leads because it is the only row here that is known rather
  /// than inferred, and it replaces the matcher's row for the same source —
  /// two lines for one source, one of them the guess that was just overruled,
  /// would be the switcher arguing with the viewer.
  List<_Row> get _rows {
    final byProvider = {for (final s in _found) s.provider.id: s};
    final corrections = _corrections.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return [
      for (final c in corrections)
        _Row(
          source: AlternateSource(
            provider: byProvider[c.providerId]?.provider ?? _refFor(c),
            item: c.asItem(),
            // Computed rather than faked to exact: the score still orders
            // nothing and decides nothing here, but a stored record that
            // claimed certainty would be a lie the moment it was read by
            // anything else.
            match: TitleMatch.of(query: widget.title, candidate: c.title),
          ),
          chosen: true,
        ),
      for (final s in _found)
        if (!_corrections.containsKey(s.provider.id))
          _Row(source: s, chosen: false),
    ];
  }

  /// A handle for a source known only from a stored correction.
  ///
  /// The installed list is the better answer — it carries the icon and the
  /// right search dispatch — but a correction outlives the source being
  /// present, and a remembered row is still worth showing with the name it was
  /// saved under.
  ProviderRef _refFor(SourceChoice choice) {
    for (final p in _candidates) {
      if (p.id == choice.providerId) return ProviderRef.fromEntity(p);
    }
    return ProviderRef(
      id: choice.providerId,
      name: choice.providerName,
      kind: ProviderRef.kindOf(choice.providerId, scopesAll: false),
    );
  }

  /// Sources that were in the run and produced no row.
  ///
  /// Only once the search is over: a source that has not answered yet has not
  /// found nothing, it is still looking.
  ///
  /// The category rule below is a copy of [AlternateSourceService]'s own, which
  /// is private to it. That is a duplicate worth removing — see the note in the
  /// service — but the alternative today is a section that either hides sources
  /// that were asked or invents ones that never were.
  List<ProviderEntity> get _silent {
    if (_searching) return const [];
    final answered = {
      for (final s in _found) s.provider.id,
      ..._corrections.keys,
    };
    final out = [
      for (final p in _candidates)
        if (p.id != widget.provider &&
            !p.browseOnly &&
            !answered.contains(p.id) &&
            _sameKind(widget.category, p.category))
          p,
    ];
    out.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return out;
  }

  /// Extension providers are stamped with their ECOSYSTEM rather than a content
  /// category, and an ecosystem says nothing about what a source carries — so
  /// it is never grounds for hiding one. Mirrors the service's rule exactly.
  static const Set<String> _ecosystems = {
    'cloudstream',
    'aniyomi',
    'manga',
    'mangayomi',
    'jellyfin',
  };

  static bool _sameKind(String want, String have) {
    if (want.isEmpty || have.isEmpty) return true;
    if (_ecosystems.contains(want) || _ecosystems.contains(have)) return true;
    return want == have;
  }

  /// Manga and novels are read, not played: the pick is the source itself.
  bool get _reads => widget.provider.contentMode != ContentMode.video;

  Future<void> _pick(AlternateSource source) async {
    if (_preparing != null) return;
    if (_reads) {
      Navigator.of(context).pop(source);
      return;
    }
    setState(() {
      _preparing = source.provider.id;
      _failed = null;
    });
    final args = await getIt<AlternateSourceService>().buildArgs(
      source: source,
      episodeNumber: widget.episodeNumber,
      resumeAt: widget.resumeAt,
    );
    if (!mounted) return;
    if (args == null) {
      setState(() {
        _preparing = null;
        _failed = (
          provider: source.provider.id,
          message: widget.episodeNumber != null
              // The common failure, and worth naming precisely: the source has
              // the show but not this episode number.
              ? 'player.alt_no_episode'.tr(args: ['${widget.episodeNumber}'])
              : 'player.alt_failed'.tr(),
        );
      });
      return;
    }
    Navigator.of(context).pop(args);
  }

  /// Hand the question to the viewer: search this one source, take their pick.
  ///
  /// Remembered before the row is redrawn, so the correction is already on disk
  /// if they close the sheet immediately — which is what someone does when the
  /// row they wanted is finally there.
  Future<void> _correct(ProviderRef provider) async {
    final picked = await SourceSearchSheet.show(
      context,
      provider: provider,
      query: widget.title,
      candidates: _candidates.isEmpty ? null : _candidates,
    );
    if (picked == null || !mounted) return;
    final choice = SourceChoice(
      subject: widget.title,
      providerId: provider.id,
      providerName: provider.name,
      url: picked.url,
      title: picked.title,
      thumbnail: picked.thumbnail,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    await _choices.remember(choice);
    if (!mounted) return;
    // A corrected source drops out of the "nothing matched" section by itself:
    // it now answers for this title.
    setState(() => _corrections[provider.id] = choice);

    // And then GO there.
    //
    // This used to stop at a snackbar, which left the viewer holding the
    // answer and nowhere to put it: they had searched a source by hand, found
    // the right title and tapped it, and the sheet's reply was to redraw a row
    // they then had to find and tap a second time. On a serial that is two
    // taps between them and the episode list they were already asking for.
    //
    // An exact match, without qualification: every other row here carries a
    // score because a machine guessed it. This one was chosen by a person
    // looking at the title, which is the strongest evidence this sheet can
    // have — and `_pick` is what turns a choice into something the player or
    // the episode list can be handed, including saying so when the source has
    // the show but not this episode.
    await _pick(
      AlternateSource(
        provider: provider,
        item: picked,
        match: const TitleMatch(score: 1, confidence: TitleConfidence.exact),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows;
    final quiet = _silent;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'player.alt_sources'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_searching)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (list.isNotEmpty) _matchGrid(list),
                if (list.isEmpty) _emptyBlock(),
                if (quiet.isNotEmpty) ..._silentSection(quiet),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Every source that has this title, as posters.
  ///
  /// It was a list of names, and a name is the one thing that does not settle
  /// the question being asked here — which is "is this the show I was
  /// watching". Four sources answering with the same words look identical in a
  /// list and are told apart instantly by their artwork, and a source that has
  /// quietly matched the wrong series is usually obvious from the cover before
  /// it is obvious from the title.
  ///
  /// Sized by the widest a tile may be rather than by a column count, so a
  /// phone lands on three and a tablet or a desktop window takes four or more
  /// without a second layout being written for them.
  Widget _matchGrid(List<_Row> rows) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: rows.length,
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 132,
      mainAxisSpacing: 12,
      crossAxisSpacing: 10,
      // The poster's own 2:3 plus room for two lines of caption, which grows
      // with the text scale rather than clipping at it.
      mainAxisExtent:
          132 * 1.5 + 34 + MediaQuery.textScalerOf(context).scale(12) * 1.6,
    ),
    itemBuilder: (context, i) => _matchTile(rows[i]),
  );

  Widget _matchTile(_Row row) {
    final busy = _preparing == row.provider.id;
    final enabled = _preparing == null;
    final failure = _failed?.provider == row.provider.id
        ? _failed!.message
        : null;
    final poster = row.source.item.thumbnail;
    // Deliberately NOT an ExcludeSemantics over the whole tile: the "Wrong
    // title?" control and the confidence pill each have something of their own
    // to say, and swallowing them to give the tile one tidy label took the
    // escape hatch away from exactly the reader most likely to need it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: const Color(0xFF1C1C1C),
                      child: poster == null || poster.isEmpty
                          ? const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white24,
                              size: 22,
                            )
                          : CachedNetworkImage(
                              imageUrl: poster,
                              httpHeaders: posterImageHeaders(poster),
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 180),
                              errorWidget: (_, _, _) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white24,
                                size: 22,
                              ),
                            ),
                    ),
                    // A scrim under the play mark and the badges, so both stay
                    // legible on a bright cover as well as a dark one.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x00000000)],
                          stops: [0, 0.55],
                        ),
                      ),
                    ),
                    Center(
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            )
                          : Icon(
                              // A manga opens to be read, not played.
                              _reads
                                  ? Icons.menu_book_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: Colors.white70,
                              size: 34,
                            ),
                    ),
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: Semantics(
                          button: true,
                          label:
                              '${row.provider.name}, ${row.source.item.title}',
                          child: InkWell(
                            onTap: enabled ? () => _pick(row.source) : null,
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 4,
                      start: 4,
                      child: Wrap(spacing: 4, children: _badge(row)),
                    ),
                    // On the tile that failed, over its own poster, where the
                    // finger already is.
                    if (failure != null)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.white70,
                                  size: 22,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  failure,
                                  textAlign: TextAlign.center,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    height: 1.25,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // The escape hatch keeps its own target in the corner: the
                    // tile's own tap is still "play this", and a cover that
                    // opened a search when somebody meant to watch would be a
                    // worse bug than the one it is here to fix.
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: _wrongTitleButton(row.provider),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              row.provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            // The source's own title for the show, not ours. Two catalogues
            // spell the same series differently, and seeing which one this
            // source means is how the viewer tells a real match from a near
            // miss before committing.
            Text(
              row.source.item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 11.5),
        ),
      ],
    );
  }

  /// How sure this row is, said in a word.
  ///
  /// Only the two rows that need it carry one: a match the viewer chose, and a
  /// match that is a guess. An [TitleConfidence.exact] or
  /// [TitleConfidence.strong] row is left exactly as it was, because a badge on
  /// every row is a badge nobody reads.
  ///
  /// Word plus icon, never colour on its own — the dim grey a weak row is drawn
  /// in disappears in a screenshot, in high contrast, and for a reader who
  /// cannot tell it from the one beside it.
  List<Widget> _badge(_Row row) {
    if (row.chosen) {
      return [
        _Pill(
          icon: Icons.person_outline_rounded,
          label: 'player.alt_your_pick'.tr(),
        ),
      ];
    }
    if (row.source.confidence != TitleConfidence.weak) return const [];
    return [
      _Pill(
        icon: Icons.help_outline_rounded,
        label: 'player.alt_guess'.tr(),
        semanticsLabel: 'player.alt_guess_spoken'.tr(),
      ),
    ];
  }

  /// The escape hatch, on every row.
  ///
  /// Its own target rather than the tile's tap: the primary action is still
  /// "play this", and a cover that opened a search when someone meant to watch
  /// would be a worse bug than the one this fixes.
  ///
  /// An icon rather than the words it used to be, because a tile is 132px wide
  /// and "Wrong title?" is not — but it keeps a 48dp target, a tooltip, and a
  /// spoken label that says something actionable rather than "button".
  Widget _wrongTitleButton(ProviderRef provider) {
    final label = 'player.alt_wrong_title'.tr();
    return Tooltip(
      message: 'player.alt_wrong_title_hint'.tr(args: [provider.name]),
      child: Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: _preparing == null ? () => _correct(provider) : null,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.edit_outlined,
                color: Colors.white70,
                size: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The sources that were asked and matched nothing.
  ///
  /// They were dropped from the list entirely before this, which made the
  /// by-hand search available on exactly the sources that did not need it. A
  /// source whose automatic match failed is the single most likely place for a
  /// correction to be needed.
  List<Widget> _silentSection(List<ProviderEntity> quiet) {
    return [
      const Divider(color: Colors.white12, height: 1),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _showSilent = !_showSilent),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'player.alt_unmatched'.tr(args: ['${quiet.length}']),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                _showSilent
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: Colors.white38,
                size: 20,
              ),
            ],
          ),
        ),
      ),
      if (_showSilent) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'player.alt_unmatched_hint'.tr(),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        for (final p in quiet)
          ListTile(
            dense: true,
            enabled: _preparing == null,
            onTap: () => _correct(ProviderRef.fromEntity(p)),
            leading: const Icon(
              Icons.search_off_rounded,
              color: Colors.white30,
              size: 20,
            ),
            title: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            subtitle: Text(
              'player.alt_search_by_hand'.tr(),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
      ],
    ];
  }

  Widget _emptyBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _searching ? 'player.alt_searching'.tr() : _emptyMessage(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          // Only once the search is over, and only when it found nothing.
          // Cross-search casts a wider net — every category, no title matching
          // — so it is the right next step for someone this sheet could not
          // help, and a dead end is the wrong thing to leave them with.
          if (!_searching) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/cross-search', extra: widget.title);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text('player.alt_search_all'.tr()),
            ),
            // The last resort, and this is the moment for it: a source just
            // failed and none of the others has the title either. Offering
            // torrents earlier would push people onto BitTorrent for something
            // that streams fine; offering nothing here leaves them at a dead
            // end.
            if (_torrentsAvailable)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/torrents', extra: widget.title);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                icon: const Icon(Icons.hub_rounded, size: 18),
                label: Text('search.try_torrents'.tr()),
              ),
          ],
        ],
      ),
    );
  }
}

/// A word and a mark, in a box.
///
/// Both carriers on purpose: the icon survives a colour-blind reader and a
/// greyscale screenshot, the word survives a screen reader, and neither is the
/// only thing saying what the pill says.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.semanticsLabel});

  final IconData icon;
  final String label;

  /// What a screen reader says instead of [label], when a whole sentence is
  /// clearer out loud than the one word the row has space for.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? label,
      excludeSemantics: semanticsLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: Colors.white70),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
