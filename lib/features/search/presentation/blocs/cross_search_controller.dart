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

  final CrossSearchEngine engine;
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

    final result = await engine.searchProvider(ref, _query);
    _retrying.remove(providerId);
    if (token != _token) return;

    _results[ref.id] = result;
    _remerge();
    notifyListeners();
  }

  /// Every leg that failed or timed out, at once.
  Future<void> retryFailed() async {
    final ids = [for (final leg in failedLegs) leg.provider.id];
    if (ids.isEmpty) return;
    await Future.wait(ids.map(retryProvider));
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
        _remerge();
        notifyListeners();
      },
      onDone: () {
        if (token != _token) return;
        _phase = CrossSearchPhase.done;
        _store(q);
        notifyListeners();
      },
    );
  }

  void _remerge() => _merged = mergeSearchResults(results, query: _query);

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
