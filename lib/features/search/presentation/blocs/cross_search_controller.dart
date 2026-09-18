import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';
import 'package:soplay/features/search/presentation/blocs/search_query_policy.dart';

/// Where a cross-search run is, so the UI can never claim a finished search it
/// has not started: [pending] is "the query changed, the fan-out has not begun",
/// which is exactly the window in which the old query's counts used to be
/// presented as the new query's answer.
enum CrossSearchPhase { idle, pending, running, done }

/// Drives one cross-search surface: debounces input, runs the engine, collects
/// results incrementally, and cancels the previous run on every new query.
class CrossSearchController extends ChangeNotifier {
  CrossSearchController({required this.engine, required List<ProviderRef> set})
      : _set = set;

  final SearchFanOut engine;
  List<ProviderRef> _set;

  final QueryDebouncer _debouncer = QueryDebouncer();
  StreamSubscription<ProviderSearchResult>? _sub;
  int _token = 0;

  String _query = '';
  CrossSearchPhase _phase = CrossSearchPhase.idle;

  /// Keyed by provider id, but read back in [providerSet] order so a leg that
  /// lands late cannot make the sections jump around under the user's finger.
  final Map<String, ProviderSearchResult> _results = {};
  final Set<String> _retrying = {};
  List<MergedSearchTitle> _merged = const [];

  /// Coalesces arriving legs into one merge per tick.
  ///
  /// `mergeSearchResults` rebuilds from scratch: it regroups every item of
  /// every leg collected so far and re-scores each one against the query. Doing
  /// that per arrival is quadratic in the number of sources — at 2000 installed
  /// sources it is tens of millions of item comparisons over a run, all of it
  /// on the UI isolate, which is why the screen stopped responding long before
  /// the search itself was finished.
  ///
  /// Batching does not delay a result by more than this window, and a user
  /// cannot read a list that reflows sixty times a second anyway.
  static const Duration _flushWindow = Duration(milliseconds: 250);
  Timer? _flush;

  static const int _cacheEntries = 6;
  static const Duration _cacheTtl = Duration(minutes: 5);
  final LinkedHashMap<String, _CachedRun> _cache = LinkedHashMap();

  String get query => _query;
  CrossSearchPhase get phase => _phase;
  bool get searching =>
      _phase == CrossSearchPhase.pending || _phase == CrossSearchPhase.running;
  List<ProviderRef> get providerSet => _set;

  int get expectedLegs => _set.length;
  int get completedLegs => results.length;
  int get totalItems => _results.values.fold(0, (s, r) => s + r.items.length);
  int get sourcesWithResults => _results.values.where((r) => r.hasItems).length;

  /// The four outcomes kept apart, because "searched and found nothing",
  /// "blew up", "took too long" and "has not answered yet" are four different
  /// answers and the summary used to render all of them as a missing source.
  int get emptySources => _countStatus(ProviderSearchStatus.empty);
  int get erroredSources => _countStatus(ProviderSearchStatus.error);
  int get timedOutSources => _countStatus(ProviderSearchStatus.timeout);
  int get brokenSources => erroredSources + timedOutSources;
  int get runningSources => expectedLegs - completedLegs;

  int _countStatus(ProviderSearchStatus status) =>
      results.where((r) => r.status == status).length;

  /// Nothing answered usefully and every leg that did answer broke — the state
  /// that must never be reported as "no results".
  bool get everySourceBroken =>
      _phase == CrossSearchPhase.done &&
      expectedLegs > 0 &&
      brokenSources == expectedLegs;

  /// A query the user is still typing that is too short to fan out on. Without
  /// this the page showed a finished-looking "0 results" for a single letter.
  bool get awaitingLongerQuery =>
      _phase == CrossSearchPhase.idle && _query.isNotEmpty;

  /// Every leg in the selected order — answered or not.
  List<ProviderSearchResult> get results => [
        for (final ref in _set)
          if (_results[ref.id] != null) _results[ref.id]!,
      ];

  List<ProviderSearchResult> get legsWithItems =>
      results.where((r) => r.hasItems).toList();

  List<ProviderSearchResult> get failedLegs => results
      .where((r) =>
          r.status == ProviderSearchStatus.timeout ||
          r.status == ProviderSearchStatus.error)
      .toList();

  /// Sources that have not answered yet, by name — a progress line that names
  /// what it is waiting for instead of counting anonymous legs.
  List<String> get pendingSources => [
        for (final ref in _set)
          if (!_results.containsKey(ref.id)) ref.name,
      ];

  bool isRetrying(String providerId) => _retrying.contains(providerId);

  /// One card per title, contributed by one or more sources.
  List<MergedSearchTitle> get merged => _merged;

  bool get hasMoreAnywhere => results.any((r) => r.hasMore);

  void onQueryChanged(String raw) {
    final trimmed = SearchQueryPolicy.normalize(raw);
    if (trimmed == _query) return;
    _query = trimmed;

    _cancel();
    _results.clear();
    _retrying.clear();
    _merged = const [];

    if (trimmed.isEmpty) {
      _phase = CrossSearchPhase.idle;
      notifyListeners();
      return;
    }

    if (_restoreFromCache(trimmed)) return;

    _debouncer.reset();
    // A query below the minimum length arms nothing, so claiming "pending"
    // would leave the page spinning against a request that never happens.
    _phase = _debouncer.schedule(trimmed, _run)
        ? CrossSearchPhase.pending
        : CrossSearchPhase.idle;
    notifyListeners();
  }

  /// The keyboard's Search key: no debounce, no minimum length.
  void submit(String raw) {
    final trimmed = SearchQueryPolicy.normalize(raw);
    if (trimmed.isEmpty) return;
    _query = trimmed;
    _debouncer.reset();
    _run(trimmed);
  }

  void setProviderSet(List<ProviderRef> set) {
    if (_sameSet(set)) return;
    _set = set;
    _results.clear();
    _retrying.clear();
    _merged = const [];
    if (_query.isEmpty) {
      _phase = CrossSearchPhase.idle;
      notifyListeners();
      return;
    }
    _cancel();
    // The cache is keyed by set + query, so toggling a source off and back on
    // is instant instead of re-running every other leg from scratch.
    if (_restoreFromCache(_query)) return;
    _debouncer.reset();
    _run(_query);
  }

  bool _sameSet(List<ProviderRef> set) {
    if (set.length != _set.length) return false;
    for (var i = 0; i < set.length; i++) {
      if (set[i].id != _set[i].id) return false;
    }
    return true;
  }

  /// Re-runs a single source. A first-ever extension search has to download and
  /// dex-load an APK, so a timeout here is expected and needs to be actionable
  /// per source rather than as one anonymous "2 timed out".
  Future<void> retryProvider(String providerId) async {
    final ref = _set.where((p) => p.id == providerId).firstOrNull;
    if (ref == null || _query.isEmpty || _retrying.contains(providerId)) return;

    final token = _token;
    _retrying.add(providerId);
    notifyListeners();

    // The user pressed this, on one named source, and is watching it. It gets
    // the source's honest budget rather than the four-second penalty leash —
    // which Retry always inherited, because Retry only ever appears beside a
    // source that has just been marked broken.
    final result = await engine.searchProvider(ref, _query, deliberate: true);
    _retrying.remove(providerId);
    if (token != _token) return;

    _results[ref.id] = result;
    _remerge();
    notifyListeners();
  }

  /// Every leg that failed or timed out, a few at a time.
  ///
  /// Bounded, because `Future.wait` over every failed id was not. When most of
  /// a run fails — which is the ordinary case on a device whose extension
  /// sources are cold — "Retry all" launched up to [CrossSearchEngine.maxLegs]
  /// simultaneous searches, each of which can boot a WebView or dex-load an
  /// APK. That is precisely the overload the engine's own concurrency pool
  /// exists to prevent, reached by going around it.
  Future<void> retryFailed() async {
    // One run at a time. The pool below bounds ONE call; it does nothing about
    // a second tap, and the button sits next to a list of failures where the
    // natural reaction to "nothing happened yet" is to press it again. Each
    // extra tap added another five-wide pool of its own, so three impatient
    // taps put fifteen extension searches on a device that was already slow
    // enough to invite them.
    if (_retryingAll) return;
    _retryingAll = true;
    notifyListeners();
    try {
      await _retryFailed();
    } finally {
      _retryingAll = false;
      notifyListeners();
    }
  }

  /// Whether a "Retry all" is in flight, so the button can say so.
  bool get retryingAll => _retryingAll;
  bool _retryingAll = false;

  Future<void> _retryFailed() async {
    final ids = [for (final leg in failedLegs) leg.provider.id];
    if (ids.isEmpty) return;
    final queue = List<String>.of(ids);
    await Future.wait([
      for (var i = 0; i < CrossSearchEngine.defaultConcurrency; i++)
        () async {
          while (queue.isNotEmpty) {
            await retryProvider(queue.removeAt(0));
          }
        }(),
    ]);
  }

  /// Whether a [loadMore] is in flight, so the button can say so and refuse a
  /// second tap. Without it two taps both page from the same snapshot: the
  /// same page is fetched twice and the second write clobbers the first.
  bool get loadingMore => _loadingMore;
  bool _loadingMore = false;

  /// Next page from every source that reported one.
  Future<void> loadMore() async {
    if (_loadingMore) return;
    final token = _token;
    final pending = results.where((r) => r.hasMore).toList();
    if (pending.isEmpty || _query.isEmpty) return;

    _loadingMore = true;
    notifyListeners();
    try {
      await _loadMoreLegs(pending, token);
    } finally {
      // A superseded run must not clear the flag for the one that replaced it.
      if (token == _token) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadMoreLegs(
    List<ProviderSearchResult> pending,
    int token,
  ) async {
    for (final leg in pending) {
      final next = await engine.searchProvider(
        leg.provider,
        _query,
        page: leg.page + 1,
      );
      if (token != _token) return;
      if (next.status != ProviderSearchStatus.ok) continue;
      final seen = {for (final m in leg.items) '${m.provider}::${m.url}'};
      _results[leg.provider.id] = leg.copyWith(
        items: [
          ...leg.items,
          for (final m in next.items)
            if (seen.add('${m.provider}::${m.url}')) m,
        ],
        page: next.page,
        totalPages: next.totalPages,
      );
      _remerge();
      notifyListeners();
    }
  }

  void _run(String q) {
    _cancel();
    final token = ++_token;
    _loadingMore = false;
    _results.clear();
    _retrying.clear();
    _merged = const [];
    _phase =
        _set.isEmpty ? CrossSearchPhase.done : CrossSearchPhase.running;
    notifyListeners();
    if (_set.isEmpty) return;

    _sub = engine.search(set: _set, query: q).listen(
      (result) {
        if (token != _token) return;
        _results[result.provider.id] = result;
        _scheduleFlush();
      },
      onDone: () {
        if (token != _token) return;
        _phase = CrossSearchPhase.done;
        _store(q);
        // The last legs may still be sitting in the current window; the run is
        // not allowed to report itself finished on a stale list.
        _flushNow();
      },
    );
  }

  void _remerge() => _merged = mergeSearchResults(results, query: _query);

  void _scheduleFlush() {
    _flush ??= Timer(_flushWindow, _flushNow);
  }

  void _flushNow() {
    _flush?.cancel();
    _flush = null;
    _remerge();
    notifyListeners();
  }

  void _store(String q) {
    // Never replay a run that contains a failure: retyping the query is how a
    // user asks for another attempt, and serving them the cached failure for
    // the next five minutes is indistinguishable from the app being broken.
    if (failedLegs.isNotEmpty) return;
    _cache.remove(_cacheKey(q));
    _cache[_cacheKey(q)] = _CachedRun(
      at: DateTime.now(),
      results: List.of(results),
    );
    while (_cache.length > _cacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  bool _restoreFromCache(String q) {
    final hit = _cache[_cacheKey(q)];
    if (hit == null) return false;
    if (DateTime.now().difference(hit.at) > _cacheTtl) {
      _cache.remove(_cacheKey(q));
      return false;
    }
    ++_token;
    for (final r in hit.results) {
      _results[r.provider.id] = r;
    }
    _remerge();
    _phase = CrossSearchPhase.done;
    notifyListeners();
    return true;
  }

  String _cacheKey(String q) =>
      '${_set.map((p) => p.id).join(',')}|${q.toLowerCase()}';

  void _cancel() {
    _debouncer.cancel();
    _flush?.cancel();
    _flush = null;
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _cancel();
    super.dispose();
  }
}

class _CachedRun {
  const _CachedRun({required this.at, required this.results});

  final DateTime at;
  final List<ProviderSearchResult> results;
}
