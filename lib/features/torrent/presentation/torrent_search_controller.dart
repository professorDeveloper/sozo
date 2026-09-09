import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/torrent_search_repository.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// Drives the torrent search page.
///
/// A [ChangeNotifier] rather than a bloc, matching `CrossSearchController`:
/// this is one screen's transient state with no events worth replaying, and
/// nothing outside the page reads it.
///
/// The one piece of real logic is request ordering. Searching four trackers
/// takes seconds, the user keeps typing, and a slow response from an abandoned
/// query must never overwrite a newer one — so every search carries a sequence
/// number and stale results are dropped on arrival.
class TorrentSearchController extends ChangeNotifier {
  TorrentSearchController({required TorrentSearchRepository repository})
      : _repository = repository;

  final TorrentSearchRepository _repository;

  int _sequence = 0;
  CancelToken? _cancelToken;
  Timer? _debounce;
  StreamSubscription<TorrentSearchUpdate>? _subscription;

  String _term = '';
  TorrentQuery _query = const TorrentQuery(term: '');
  TorrentFilters _filters = const TorrentFilters();
  Set<String>? _enabledIndexers;
  bool _nsfwAllowed = false;

  List<TorrentResult> _results = const [];

  /// Everything the trackers returned, before filtering.
  ///
  /// Filters and sort order are computed entirely from data already here, so
  /// keeping the unfiltered set means flipping a switch is instant instead of
  /// an eight-second round trip to four websites — several of which rate-limit
  /// a client that asks too often.
  List<TorrentResult> _raw = const [];

  bool _loading = false;
  int _pendingIndexers = 0;
  List<String> _failedIndexers = const [];
  Object? _error;

  String get term => _term;
  TorrentQuery get query => _query;
  TorrentFilters get filters => _filters;
  List<TorrentResult> get results => _results;
  bool get loading => _loading;

  /// Trackers still to answer. Non-zero while results are already on screen is
  /// the normal state now — the list fills in as each tracker replies.
  int get pendingIndexers => _pendingIndexers;

  /// Trackers that errored, timed out, or answered with nothing — usually a
  /// rate limit rather than a genuinely empty result.
  List<String> get failedIndexers => _failedIndexers;

  Object? get error => _error;

  /// True once a search has run, so the page can tell "nothing searched yet"
  /// apart from "searched and found nothing" — they need different empty
  /// states.
  bool get hasSearched => _sequence > 0;

  List<TorrentIndexer> get indexers => _repository.indexers;

  Set<String> get enabledIndexers =>
      _enabledIndexers ??
      _repository.indexers
          .where((i) => !i.isNsfw)
          .map((i) => i.id)
          .toSet();

  /// Typing runs a debounced search; submitting runs one immediately.
  ///
  /// 450 ms is longer than a normal in-app debounce on purpose — each keystroke
  /// that gets through costs four requests to third-party trackers, some of
  /// which rate-limit.
  void onTermChanged(String value) {
    _term = value;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _cancelInFlight();
      _results = const [];
      _raw = const [];
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), search);
  }

  void setCategory(TorrentCategory category) {
    if (_query.category == category) return;
    _query = _query.copyWith(category: category, page: 1);
    notifyListeners();
    if (_term.trim().isNotEmpty) search();
  }

  /// Re-ranks what is already on screen. No network.
  void setSort(TorrentSort sort) {
    if (_query.sort == sort) return;
    _query = _query.copyWith(sort: sort, page: 1);
    _reapply();
  }

  /// Re-filters what is already on screen. No network.
  void setFilters(TorrentFilters filters) {
    _filters = filters;
    _reapply();
  }

  /// Recomputes the visible list from [_raw].
  ///
  /// Only used while a result set is in hand; with nothing fetched yet there is
  /// nothing to re-filter and the change simply applies to the next search.
  void _reapply() {
    _results = _repository.applyFilters(_raw, _filters, _query.sort);
    notifyListeners();
  }

  /// Which trackers to query. Unlike the filters this really does change what
  /// the servers return, so it re-runs the search.
  void setEnabledIndexers(Set<String> ids) {
    if (setEquals(_enabledIndexers, ids)) return;
    _enabledIndexers = ids;
    notifyListeners();
    if (_term.trim().isNotEmpty) search();
  }

  set nsfwAllowed(bool value) {
    if (_nsfwAllowed == value) return;
    _nsfwAllowed = value;
    notifyListeners();
  }

  /// Starts a search, publishing results as each tracker answers.
  ///
  /// Nothing is awaited here: the page updates from [notifyListeners] as
  /// frames arrive, so the first tracker's results are on screen in about half
  /// a second instead of after the slowest one.
  void search() {
    final term = _term.trim();
    if (term.isEmpty) return;

    _cancelInFlight();
    final sequence = ++_sequence;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    _loading = true;
    _error = null;
    // The previous query's results are dropped immediately. Keeping them while
    // a *different* search runs would show rows that do not match what is in
    // the search box.
    _results = const [];
    _raw = const [];
    _pendingIndexers = 0;
    _failedIndexers = const [];
    notifyListeners();

    _subscription = _repository
        .searchIncremental(
          _query.copyWith(term: term),
          filters: _filters,
          enabledIds: enabledIndexers,
          nsfwAllowed: _nsfwAllowed,
          cancelToken: cancelToken,
        )
        .listen(
      (update) {
        // A newer search started while this one was still arriving.
        if (sequence != _sequence) return;
        _results = update.results;
        _raw = update.raw;
        _pendingIndexers = update.pending;
        _failedIndexers = update.failed;
        _loading = !update.isComplete;
        notifyListeners();
      },
      onError: (Object error) {
        if (sequence != _sequence) return;
        _error = error;
        _loading = false;
        _pendingIndexers = 0;
        notifyListeners();
      },
      onDone: () {
        if (sequence != _sequence) return;
        _loading = false;
        _pendingIndexers = 0;
        notifyListeners();
      },
    );
  }

  void _cancelInFlight() {
    _debounce?.cancel();
    _subscription?.cancel();
    _subscription = null;
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('superseded');
    }
    _cancelToken = null;
  }

  @override
  void dispose() {
    _cancelInFlight();
    super.dispose();
  }
}
