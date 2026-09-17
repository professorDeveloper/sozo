import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// Loads and mutates the viewer's AniList library.
///
/// Holds the entries in memory for the life of the screen so switching status
/// tabs is instant — AniList returns every status in a single request, and
/// re-fetching per tab would spend a round trip to show data already held.
///
/// Anime only until a screen sets [includeReading]: the type is AniList's own
/// split, one query each, and most of what builds this controller is asking
/// about airing shows.
class AnilistLibraryController extends ChangeNotifier {
  AnilistLibraryController({required AnilistService service})
    : _service = service;

  final AnilistService _service;

  List<AnilistListEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  /// When the rate-limit window reopens, if that is what failed.
  ///
  /// The screen was offering a Try again against a budget AniList had already
  /// closed, so every press produced the same message — the feature looked
  /// broken rather than busy. Held so the page can count down and retry itself.
  DateTime? _retryAt;

  /// Entry ids with a write in flight, so a card can show a spinner without
  /// blocking the rest of the list.
  final Set<int> _busy = <int>{};

  List<AnilistListEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;

  /// null unless the failure was a rate limit that has not expired yet.
  Duration? get retryIn {
    final at = _retryAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  bool isBusy(int entryId) => _busy.contains(entryId);
  bool get isConnected => _service.isConnected;
  AnilistViewer? get viewer => _service.viewer;

  /// Which shelf the status tabs are showing. Anime to begin with, because
  /// that is what all but a handful of openings of this screen are for.
  AnilistLibraryKind _kind = AnilistLibraryKind.anime;
  AnilistLibraryKind get kind => _kind;

  void setKind(AnilistLibraryKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    notifyListeners();
  }

  /// The shelves the viewer has something on, anime always among them.
  ///
  /// The page draws its picker only when this has more than one entry, which
  /// is what keeps a library of nothing but anime looking exactly as it did
  /// before there was a picker to draw. Anime is kept unconditionally so a
  /// reader with no anime still has a way back to an empty shelf rather than
  /// the picker changing shape under them the moment they add a show.
  List<AnilistLibraryKind> get availableKinds => [
    for (final k in AnilistLibraryKind.values)
      if (k == AnilistLibraryKind.anime ||
          _entries.any((e) => k.matches(e.media)))
        k,
  ];

  /// Entries of one status on the selected shelf, most recently updated first —
  /// which is the order that puts what the viewer is actually watching at the
  /// top.
  List<AnilistListEntry> byStatus(AnilistStatus status) {
    final out = _entries
        .where((e) => e.status == status.value && _kind.matches(e.media))
        .toList();
    out.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
    return out;
  }

  /// The viewer's entry for one title, or null when it is not on their list.
  ///
  /// Keyed by media rather than entry id because the airing calendar only ever
  /// holds a media — it starts from the schedule, not from the library.
  AnilistListEntry? entryForMedia(int mediaId) {
    for (final e in _entries) {
      if (e.media.id == mediaId) return e;
    }
    return null;
  }

  /// The number on a status tab. Counted on the selected shelf only, or a
  /// reader's 300 manga would inflate the tab above a list of twelve anime.
  int countOf(AnilistStatus status) => _entries
      .where((e) => e.status == status.value && _kind.matches(e.media))
      .length;

  /// Everything with an announced next episode, soonest first.
  ///
  /// Drawn from the library rather than a separate airing query: the viewer
  /// only cares about upcoming episodes of shows they are actually on.
  List<AnilistListEntry> get upcoming {
    final out = _entries
        .where(
          (e) =>
              e.media.nextAiring != null &&
              (e.status == AnilistStatus.current.value ||
                  e.status == AnilistStatus.planning.value ||
                  e.status == AnilistStatus.repeating.value),
        )
        .toList();
    out.sort(
      (a, b) =>
          a.media.nextAiring!.airingAt.compareTo(b.media.nextAiring!.airingAt),
    );
    return out;
  }

  /// Whether what the viewer READS is held here too.
  ///
  /// Off unless a screen that can show manga asks for it. AniList's list query
  /// is per media type, so the second shelf costs a second request — and the
  /// calendar, the upcoming rail and the episode reminders all build this
  /// controller to ask one question about airing anime. Spending a request on
  /// every one of their loads, for entries they immediately drop, is exactly
  /// the kind of traffic that gets this app rate limited.
  bool _includeReading = false;

  set includeReading(bool value) {
    if (_includeReading == value) return;
    _includeReading = value;
    // A controller lent by the tracker hub has usually loaded its anime
    // already, and that load will not come round again — so the shelf the
    // library screen just asked for has to be fetched now or never appear.
    if (value && _entries.isNotEmpty) unawaited(_loadReading());
  }

  /// Adds the viewer's manga and light novels to what is held.
  ///
  /// Silent on failure, and deliberately so: an anime-only library — which is
  /// nearly every one — must not turn into an error banner because a request
  /// it never needed was refused. The cost is that a reader whose manga alone
  /// failed sees no shelf picker until they pull to refresh.
  Future<void> _loadReading() async {
    try {
      // Manga and light novels arrive together; AniList has no NOVEL type.
      final books = await _service.library(
        type: AnilistLibraryKind.manga.mediaType,
      );
      // Replaces rather than appends, so a refresh does not list every title
      // twice.
      _entries = [
        for (final e in _entries)
          if (!e.media.isManga) e,
        ...books,
      ];
      _settleKind();
      notifyListeners();
    } catch (_) {
      // Swallowed on purpose — see above. The anime already on screen stays.
    }
  }

  /// Puts the viewer back on anime when the shelf they were on is no longer
  /// offered — emptied on another device, or never fetched at all. Standing on
  /// a shelf the picker no longer draws is an empty list with no way off it.
  void _settleKind() {
    if (!availableKinds.contains(_kind)) _kind = AnilistLibraryKind.anime;
  }

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!_service.isConnected) {
      _entries = const [];
      _error = null;
      _retryAt = null;
      notifyListeners();
      return;
    }
    if (_entries.isNotEmpty && !force) return;

    _loading = true;
    _error = null;
    _retryAt = null;
    notifyListeners();
    try {
      _entries = await _service.library();
      if (_includeReading) await _loadReading();
      _settleKind();
    } catch (e) {
      _error = e is AnilistException
          ? e.message
          : 'anilist.calendar_list_error'.tr();
      final wait = e is AnilistException ? e.retryAfter : null;
      _retryAt = wait == null ? null : DateTime.now().add(wait);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Marks one more episode watched.
  ///
  /// Optimistic: the card moves immediately and is rolled back if the write
  /// fails, because the round trip is long enough that an un-animated card
  /// reads as a dead button.
  Future<String?> bumpEpisode(AnilistListEntry entry) =>
      setProgress(entry, entry.progress + 1);

  /// Writes an explicit progress value.
  Future<String?> setProgress(AnilistListEntry entry, int progress) async {
    final token = _service.token;
    if (token == null) return 'anilist.connect_first'.tr();
    if (progress < 0 || _busy.contains(entry.id)) return null;

    final previous = entry;
    _busy.add(entry.id);
    _replace(entry.copyWith(progress: progress));
    notifyListeners();

    try {
      final saved = await _service.api.saveProgress(
        token: token,
        mediaId: entry.media.id,
        progress: progress,
        status: _statusAfter(entry, progress),
      );
      // Trust the server's answer over the guess: AniList clamps progress to
      // the episode total and flips status to COMPLETED on the last one.
      _replace(entry.copyWith(progress: saved.progress, status: saved.status));
      return null;
    } catch (e) {
      _replace(previous);
      return e is AnilistException ? e.message : 'anilist.save_failed'.tr();
    } finally {
      _busy.remove(entry.id);
      notifyListeners();
    }
  }

  /// Moves an entry to another list.
  Future<String?> setStatus(
    AnilistListEntry entry,
    AnilistStatus status,
  ) async {
    final token = _service.token;
    if (token == null) return 'anilist.connect_first'.tr();
    if (_busy.contains(entry.id)) return null;

    final previous = entry;
    _busy.add(entry.id);
    _replace(entry.copyWith(status: status.value));
    notifyListeners();

    try {
      final saved = await _service.api.saveProgress(
        token: token,
        mediaId: entry.media.id,
        progress: entry.progress,
        status: status.value,
      );
      _replace(entry.copyWith(progress: saved.progress, status: saved.status));
      return null;
    } catch (e) {
      _replace(previous);
      return e is AnilistException ? e.message : 'anilist.save_failed'.tr();
    } finally {
      _busy.remove(entry.id);
      notifyListeners();
    }
  }

  /// Takes a title off the list for good.
  ///
  /// Removed from view first and put back if AniList refuses, the same way the
  /// other two writes work — the list is the viewer's own and a round trip of
  /// latency before it reflects their decision reads as the tap not landing.
  Future<String?> remove(AnilistListEntry entry) async {
    final token = _service.token;
    if (token == null) return 'anilist.connect_first'.tr();
    if (_busy.contains(entry.id)) return null;

    final previous = _entries;
    _busy.add(entry.id);
    _entries = _entries.where((e) => e.id != entry.id).toList(growable: false);
    notifyListeners();

    try {
      await _service.api.deleteEntry(token: token, entryId: entry.id);
      return null;
    } catch (e) {
      _entries = previous;
      return e is AnilistException ? e.message : 'anilist.save_failed'.tr();
    } finally {
      _busy.remove(entry.id);
      notifyListeners();
    }
  }

  /// Finishing the last episode — or the last chapter — should not leave the
  /// title on "Watching".
  static String? _statusAfter(AnilistListEntry entry, int progress) {
    final total = entry.media.totalUnits;
    if (total != null && total > 0 && progress >= total) {
      return AnilistStatus.completed.value;
    }
    if (entry.status == AnilistStatus.repeating.value) return null;
    if (entry.status == AnilistStatus.current.value) return null;
    return AnilistStatus.current.value;
  }

  void _replace(AnilistListEntry updated) {
    _entries = [
      for (final e in _entries)
        if (e.id == updated.id) updated else e,
    ];
  }
}
