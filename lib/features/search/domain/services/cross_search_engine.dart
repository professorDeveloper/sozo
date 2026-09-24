import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/search_relevance.dart';

typedef _Leg = ({List<MovieEntity> items, int page, int totalPages});

/// Fans a query out across a set of providers with **bounded concurrency**, a
/// **per-provider timeout**, and **incremental** emission — the core reason the
/// feature never freezes even with a large provider set:
///
/// - never runs more than [concurrency] provider searches at once;
/// - a slow/hung provider is dropped at [perProviderTimeout] (its native call
///   keeps running in the background but its result is ignored);
/// - each provider's result is emitted the moment it resolves;
/// - cancelling the returned stream stops scheduling further work;
/// - one provider throwing never fails the batch.
///
/// Native `cs:`/`an:`/`mn:` searches already run off the platform thread, so the
/// pool only guards against overwhelming the device — the UI thread never blocks.
/// What a cross-search surface actually needs from the engine.
///
/// Named so the controller can be driven by a stub in a test. The engine itself
/// reaches WebViews, a Dio client and the Mangayomi bridge; standing all three
/// up to assert that arriving legs are batched would test the fakes, not the
/// batching.
abstract interface class SearchFanOut {
  /// The legs an all-source run will actually cover, healthiest first.
  ///
  /// Called by the surface that owns the set rather than inside [search], so
  /// the counters the UI shows — how many are pending, how many answered —
  /// describe the run that is really happening.
  List<ProviderRef> planLegs(List<ProviderRef> set, {int limit});

  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int page,
    int concurrency,
    Duration perProviderTimeout,
  });

  /// [deliberate] marks a run the user asked for by name — the Retry beside a
  /// failed source, or the source diagnostic — which is exempt from the
  /// broken-source penalty budget. See [SourceHealthStore.budgetFor].
  Future<ProviderSearchResult> searchProvider(
    ProviderRef ref,
    String query, {
    int page,
    Duration timeout,
    bool deliberate,
  });
}

class CrossSearchEngine implements SearchFanOut {
  CrossSearchEngine({
    required this.jsRuntime,
    required this.dataSource,
    required this.mangayomi,
    this.jellyfin,
    SourceHealthStore? health,
  }) : health = health ?? SourceHealthStore();

  final JsRuntimeService jsRuntime;
  final SearchDataSource dataSource;
  final MangayomiBridge mangayomi;
  final JellyfinBridge? jellyfin;

  /// What each source did last time. Decides who is asked first and for how
  /// long — see [SourceHealthStore].
  final SourceHealthStore health;

  /// How many sources one all-source run will actually ask.
  ///
  /// Not a performance tweak — a ceiling on wall-clock. The pool is bounded, so
  /// a run costs roughly `legs / concurrency * timeout` in the worst case: with
  /// a couple of thousand extension sources installed that is over an hour, and
  /// a search nobody waits for is a search that did not happen.
  ///
  /// The legs kept are the healthiest ones ([SourceHealthStore.order] runs
  /// first), which are also the ones most likely to answer at all. Sixty of
  /// those is roughly two minutes of worst case and, in practice, seconds —
  /// most legs return long before their budget.
  ///
  /// A user who wants a specific source beyond the ceiling can still pick it:
  /// narrowing the scope is not capped, because then the count is theirs.
  static const int maxLegs = 60;

  static const int defaultConcurrency = 5;
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Budget for an on-device extension host (`cs:` / `an:` / `mn:`).
  ///
  /// The first search against a freshly-installed source has to download and
  /// dex-load its extension APK before it can issue a single request — several
  /// megabytes over whatever connection the user has. Under the 10s budget that
  /// suits an HTTP provider, every extension source timed out on first use and
  /// the feature looked broken precisely when the user had just added sources.
  /// Later searches hit the cached APK and return in well under a second, so
  /// this ceiling is only ever paid once per source.
  static const Duration channelTimeout = Duration(seconds: 45);

  /// Every selected provider is its own leg, server providers included: the
  /// backend takes an explicit `provider`, so collapsing them into one call was
  /// both a lie in the summary ("1 of 1 sources") and a silent no-op for every
  /// server provider the user picked beyond the first.
  @override
  List<ProviderRef> planLegs(List<ProviderRef> set, {int limit = maxLegs}) {
    if (set.length <= limit) return set;
    return health
        .order(
          List<ProviderRef>.of(set),
          (r) => r.id,
          keyOf: (r) => r.healthKey,
        )
        .take(limit)
        .toList();
  }

  @override
  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int page = 1,
    int concurrency = defaultConcurrency,
    Duration perProviderTimeout = defaultTimeout,
  }) {
    // Healthiest first. With a bounded pool, the order is the whole game: a
    // dead source at the head of the queue occupies a worker for its full
    // budget while results that were ready in 400ms wait behind it.
    final tasks = health.order(
      List<ProviderRef>.of(set),
      (r) => r.id,
      keyOf: (r) => r.healthKey,
    );
    // For the next run, not this one — see [SourceHealthStore.refreshRemote].
    unawaited(health.refreshRemote());
    final controller = StreamController<ProviderSearchResult>();
    var cancelled = false;
    controller.onCancel = () => cancelled = true;

    Future<void> drain() async {
      var next = 0;
      final pool = concurrency < 1 ? 1 : concurrency;
      Future<void> worker() async {
        while (!cancelled) {
          final i = next++;
          if (i >= tasks.length) return;
          final result = await searchProvider(
            tasks[i],
            query,
            page: page,
            timeout: perProviderTimeout,
          );
          if (cancelled || controller.isClosed) return;
          controller.add(result);
        }
      }

      await Future.wait([for (var w = 0; w < pool; w++) worker()]);
      if (!controller.isClosed) await controller.close();
    }

    // Fire-and-forget; every error is captured inside [searchProvider].
    unawaited(drain());
    return controller.stream;
  }

  /// One leg on its own — used to retry a single failed source and to page it.
  @override
  Future<ProviderSearchResult> searchProvider(
    ProviderRef ref,
    String query, {
    int page = 1,
    Duration timeout = defaultTimeout,
    bool deliberate = false,
  }) async {
    // Both on-device kinds get the longer budget. `js` was left out, although
    // the JS runtime declares its own ceiling well above the ten seconds this
    // defaulted to and needs the same head start for the same reason — it
    // fetches the extension before it can answer. So a JS source that works
    // perfectly when selected on its own timed out in all-source search, got
    // marked broken, and from then on ran on four seconds. That is exactly the
    // shape of "search only works on one source".
    final onDevice =
        ref.kind == ProviderKind.channel || ref.kind == ProviderKind.js;
    final full = onDevice && timeout < channelTimeout
        ? channelTimeout
        : timeout;
    // A source that broke last time is still asked, on a shorter leash. Enough
    // for a recovered source to prove it; not enough to hold up the batch.
    // Never for a run the user asked for by name.
    final effective = health.budgetFor(
      ref.id,
      full,
      deliberate: deliberate,
      key: ref.healthKey,
    );
    final started = DateTime.now();
    Future<void> mark(bool succeeded) => health.record(
      ref.id,
      succeeded: succeeded,
      elapsed: DateTime.now().difference(started),
      budget: effective,
      // What the source would have got with no penalty, so a failure under a
      // shortened budget is recognised as teaching nothing and does not renew
      // the mark that shortened it.
      honestBudget: full,
    );
    try {
      final leg = await _dispatch(ref, query, page).timeout(effective);
      unawaited(mark(true));
      // A source that answered with its front page is reported as having no
      // match, which it does not. Its rows are worse than none: they are
      // confident, well-formed cards for a completely different title, and on
      // the single-source page they are the whole answer.
      if (SearchRelevance.looksUnsearched(leg.items, query)) {
        developer.log(
          '${ref.id} ignored "$query" — dropping ${leg.items.length} rows',
          name: 'search',
        );
        return ProviderSearchResult(
          provider: ref,
          items: const [],
          page: leg.page,
          totalPages: leg.totalPages,
          status: ProviderSearchStatus.empty,
        );
      }
      // Ranked, never filtered. A zero-scoring row can still be the best answer
      // in the set — see [SearchRelevance] — so it sinks rather than vanishing.
      final items = SearchRelevance.rank(leg.items, query);
      return ProviderSearchResult(
        provider: ref,
        items: items,
        page: leg.page,
        totalPages: leg.totalPages,
        status: items.isEmpty
            ? ProviderSearchStatus.empty
            : ProviderSearchStatus.ok,
      );
    } on TimeoutException {
      unawaited(mark(false));
      return ProviderSearchResult(
        provider: ref,
        items: const [],
        status: ProviderSearchStatus.timeout,
      );
    } catch (e) {
      unawaited(mark(false));
      return ProviderSearchResult(
        provider: ref,
        items: const [],
        status: ProviderSearchStatus.error,
        message: describeFailure(e),
      );
    }
  }

  /// A failed leg's one-line reason.
  ///
  /// `DioException.toString()` is a paragraph about `validateStatus` that the
  /// page used to print under the source's name. The server's own message is
  /// the useful part when it sent one; the status code is the next best thing.
  static String describeFailure(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg = data is Map ? data['message'] : null;
      if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      final code = e.response?.statusCode;
      if (code != null) return 'errors.source_http'.tr(args: ['$code']);
      return 'errors.network'.tr();
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  /// Unwraps an extension host's response.
  ///
  /// Throws when the source is genuinely broken (empty map = channel failure,
  /// or an `error` field from the host) so the leg is reported as `error`
  /// rather than `empty` — "this source is down" and "no match here" look
  /// identical to the user otherwise, and only one of them is worth retrying.
  _Leg _unwrap(Map<String, dynamic> map, String label) {
    if (map.isEmpty) throw Exception('$label: source unavailable');
    final model = SearchModel.fromJson(map);
    final error = (map['error'] as String?)?.trim();
    if (model.items.isEmpty && error != null && error.isNotEmpty) {
      throw Exception('$label: $error');
    }
    return (items: model.items, page: model.page, totalPages: model.totalPages);
  }

  Future<_Leg> _dispatch(ProviderRef ref, String query, int page) async {
    final id = ref.id;
    if (id.startsWith('cs:')) {
      return _unwrap(
        await CloudStreamChannel.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (id.startsWith('an:')) {
      return _unwrap(
        await AniyomiChannel.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (id.startsWith('mn:')) {
      return _unwrap(
        await MangaChannel.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (id.startsWith('my:')) {
      return _unwrap(
        await mangayomi.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    final jf = jellyfin;
    if (jf != null && id.startsWith('jf:')) {
      return _unwrap(
        await jf.search(JellyfinBridge.bare(id), query, page: page),
        ref.name,
      );
    }
    if (ref.kind == ProviderKind.js) {
      final map = await jsRuntime.trySearch(id, query, page);
      // A null response means the extractor is missing or failed to load. That
      // is a broken source, not "no match here" — reporting it as empty is the
      // one place this engine used to invert its own distinction.
      if (map == null) throw Exception('${ref.name}: source unavailable');
      return _unwrap(map, ref.name);
    }
    final model = await dataSource.searchMovies(
      query,
      page: page,
      provider: ref.id,
    );
    return (items: model.items, page: model.page, totalPages: model.totalPages);
  }
}
