import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/sources/data/source_browse_repository.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';

/// What one attempt at a source came back with, before any history is
/// weighed.
class SourceAttempt {
  const SourceAttempt({
    required this.items,
    required this.ms,
    this.failure,
    this.empty = false,
  });

  final int items;
  final int ms;
  final SourceFailure? failure;

  /// Answered with nothing, and said nothing about why.
  final bool empty;

  bool get succeeded => failure == null && !empty && items > 0;
}

/// A run over many sources, as it goes.
class SourceCheckProgress {
  const SourceCheckProgress({
    required this.done,
    required this.total,
    required this.counts,
    this.networkDown = false,
  });

  final int done;
  final int total;
  final Map<SourceVerdict, int> counts;

  /// Nearly everything failed to connect: the device is offline or its
  /// network is blocking, and no source was marked for it.
  final bool networkDown;

  bool get finished => done >= total;
}

/// Finds out which sources still answer.
///
/// A check is the cheapest thing that proves a source works: its home page,
/// the same call the Sources screen makes to browse one. A search would
/// prove less — a source with nothing for the query is not a dead one.
///
/// ## Dead is a claim over time
///
/// One failure is a bad minute. A source is called dead after two failures
/// at least [deadSpacing] apart, or three in a row, or a site that answered
/// "gone" (404/410) twice. A bot wall is not death — the site is there, the
/// app just has to be let through — and a source whose code no longer fits
/// its site is "outdated", which an update from its repository fixes.
///
/// ## The network is not the sources
///
/// A run where most sources could not be reached at all says nothing about
/// any of them: the phone is on a captive portal, or offline. Such a run
/// records nothing and says so, rather than marking a hundred sources dead.
class SourceCheckService {
  SourceCheckService({
    required this.browse,
    required this.store,
    Future<SourceAttempt> Function(String id)? attempt,
    int Function()? now,
  }) : _attempt = attempt,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SourceBrowseRepository browse;
  final SourceCheckStore store;
  final Future<SourceAttempt> Function(String id)? _attempt;
  final int Function() _now;

  static const Duration deadSpacing = Duration(minutes: 10);

  /// How far apart two failures seen in ordinary use must be to count twice.
  static const Duration observeSpacing = Duration(minutes: 1);

  /// Long enough for a slow site's first page; a check that takes longer
  /// than this is a source nobody would wait for either.
  static const Duration timeout = Duration(seconds: 20);

  /// How many sources are asked at once, in all.
  static const int parallel = 8;

  /// And per host. Mangayomi sources share one JS runtime that runs one call
  /// at a time, so a second one in flight only waits — with its timeout
  /// running, and a queue of them timing out looks like a dead network. The
  /// native hosts and the server take a few each.
  static int limitFor(String id) {
    if (id.startsWith('my:')) return 1;
    if (id.startsWith('cs:') || id.startsWith('an:') || id.startsWith('mn:')) {
      return 3;
    }
    return 4;
  }

  static String _familyOf(String id) =>
      id.length > 3 && id[2] == ':' ? id.substring(0, 2) : '';

  /// The run in progress, for any screen that wants to show it — the Sources
  /// screen can be left and come back to a run that kept going.
  final ValueNotifier<SourceCheckProgress?> progress = ValueNotifier(null);

  /// [ids] in the order worth checking them in, most in need first.
  List<String> plan(Iterable<String> ids) {
    final list = ids.toSet().toList();
    final urgency = {for (final id in list) id: store.urgencyOf(id)};
    list.sort((a, b) {
      final x = urgency[a]!, y = urgency[b]!;
      final c = x.$1.compareTo(y.$1);
      return c != 0 ? c : x.$2.compareTo(y.$2);
    });
    return list;
  }

  /// Of [ids], the ones with nothing known on this phone, or nothing recent.
  List<String> staleOf(Iterable<String> ids) => [
    for (final id in ids)
      if (store.of(id) == null) id,
  ];

  /// Of [ids], the ones marked down or failing here.
  List<String> troubledOf(Iterable<String> ids) => [
    for (final id in ids)
      if (switch (store.verdictOf(id)) {
        SourceVerdict.dead ||
        SourceVerdict.outdated ||
        SourceVerdict.failing => true,
        _ => false,
      })
        id,
  ];

  Timer? _sweepTimer;

  /// Once per launch, a while after it: a quiet [sweep] on Wi-Fi, when the
  /// setting allows. [ids] is read when the time comes, so it sees the
  /// sources as they are then.
  void scheduleSweep(
    List<String> Function() ids, {
    Duration after = const Duration(seconds: 90),
  }) {
    if (_sweepTimer != null) return;
    _sweepTimer = Timer(after, () async {
      if (!store.autoSweep || !await _onWifi()) return;
      await sweep(ids());
    });
  }

  static Future<bool> _onWifi() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  /// A few of [ids] that need it most, checked quietly — for keeping a large
  /// collection's verdicts fresh a handful at a time rather than all at once.
  /// Does nothing while another run is going.
  Future<void> sweep(Iterable<String> ids, {int limit = 12}) async {
    if (_running) return;
    final picked = plan(staleOf(ids)).take(limit).toList();
    if (picked.isEmpty) return;
    await checkAll(picked).drain<void>();
  }

  /// Above this share of "could not connect", a run is the network's fault.
  static const double networkDownShare = 0.7;

  bool _cancelled = false;
  bool _running = false;
  bool get running => _running;

  void cancel() => _cancelled = true;

  Future<SourceAttempt> _try(String id) async {
    final custom = _attempt;
    if (custom != null) return custom(id);
    final sw = Stopwatch()..start();
    try {
      final home = await browse.probe(id).timeout(timeout);
      final items = home.sections.fold<int>(
        home.banner.length,
        (n, s) => n + s.items.length,
      );
      return SourceAttempt(
        items: items,
        ms: sw.elapsedMilliseconds,
        empty: items == 0,
      );
    } on SourceBrowseException catch (e) {
      final message = e.message;
      // A host that came back with no sections and no reason is "empty",
      // not broken.
      if (message == null || message.isEmpty) {
        return SourceAttempt(items: 0, ms: sw.elapsedMilliseconds, empty: true);
      }
      return SourceAttempt(
        items: 0,
        ms: sw.elapsedMilliseconds,
        failure: SourceFailure.of(message),
      );
    } on TimeoutException {
      return SourceAttempt(
        items: 0,
        ms: sw.elapsedMilliseconds,
        failure: SourceFailure.of('timeout'),
      );
    } catch (e) {
      return SourceAttempt(
        items: 0,
        ms: sw.elapsedMilliseconds,
        failure: SourceFailure.of('$e'),
      );
    }
  }

  /// The verdict [attempt] earns, given what was known before.
  SourceCheck judge(SourceAttempt attempt, SourceCheck? previous) {
    final now = _now();
    if (attempt.succeeded) {
      return SourceCheck(verdict: SourceVerdict.alive, at: now, ms: attempt.ms);
    }
    if (attempt.empty) {
      return SourceCheck(verdict: SourceVerdict.empty, at: now, ms: attempt.ms);
    }
    final failure = attempt.failure!;
    final detail = (failure.detail ?? failure.headline);
    final trimmed = detail.length > 200
        ? '${detail.substring(0, 200)}…'
        : detail;
    switch (failure.kind) {
      case SourceFailureKind.blocked:
      case SourceFailureKind.rateLimited:
        return SourceCheck(
          verdict: SourceVerdict.blocked,
          at: now,
          detail: trimmed,
          ms: attempt.ms,
        );
      case SourceFailureKind.outdated:
      case SourceFailureKind.incompatible:
        return SourceCheck(
          verdict: SourceVerdict.outdated,
          at: now,
          detail: trimmed,
          ms: attempt.ms,
        );
      default:
        break;
    }
    final wasFailing =
        previous != null &&
        previous.fails > 0 &&
        (previous.verdict == SourceVerdict.failing ||
            previous.verdict == SourceVerdict.dead);
    final fails = wasFailing ? previous.fails + 1 : 1;
    final firstFailAt = wasFailing
        ? (previous.firstFailAt ?? previous.at)
        : now;
    final spanned = now - firstFailAt >= deadSpacing.inMilliseconds;
    final gone = failure.kind == SourceFailureKind.gone;
    final dead = (fails >= 2 && (spanned || gone)) || fails >= 3;
    return SourceCheck(
      verdict: dead ? SourceVerdict.dead : SourceVerdict.failing,
      at: now,
      detail: trimmed,
      fails: fails,
      firstFailAt: firstFailAt,
      ms: attempt.ms,
    );
  }

  /// Checks one source and records the verdict.
  Future<SourceCheck> check(String id) async {
    final attempt = await _try(id);
    final verdict = judge(attempt, store.of(id));
    await store.put(id, verdict);
    SourceHealthStore.bumpChanges();
    return verdict;
  }

  /// A verdict from ordinary use — the home page opening, or failing to —
  /// without a separate request. Only what is certain is recorded: a
  /// success clears any mark; a failure counts only when it is about the
  /// source — gone, outdated, its own code — and never when it could be the
  /// phone's connection, which ordinary use cannot tell apart.
  Future<void> observe(String id, {required bool ok, String? error}) async {
    if (id.isEmpty) return;
    final previous = store.of(id);
    if (ok) {
      // Nothing to write when it was already known to work.
      if (previous == null || previous.verdict == SourceVerdict.alive) return;
      await store.put(
        id,
        judge(const SourceAttempt(items: 1, ms: 0), previous),
      );
      return;
    }
    final failure = SourceFailure.of(error);
    if (failure.kind == SourceFailureKind.unreachable ||
        failure.kind == SourceFailureKind.unknown) {
      return;
    }
    // Retries in quick succession are one failure seen several times, not
    // several failures: tapping Retry three times on a 404 used to be
    // "gone twice", and dead, inside ten seconds.
    if (previous != null &&
        previous.fails > 0 &&
        _now() - previous.at < observeSpacing.inMilliseconds) {
      return;
    }
    await store.put(
      id,
      judge(SourceAttempt(items: 0, ms: 0, failure: failure), previous),
    );
    SourceHealthStore.bumpChanges();
  }

  /// Checks [ids], [parallel] at a time, reporting as it goes; the ones that
  /// failed are tried once more at the end, which is what turns a "gone"
  /// into a verdict inside one run.
  Stream<SourceCheckProgress> checkAll(List<String> ids) {
    final controller = StreamController<SourceCheckProgress>();
    unawaited(_run(plan(ids), controller));
    return controller.stream;
  }

  Future<void> _run(
    List<String> ids,
    StreamController<SourceCheckProgress> out,
  ) async {
    if (_running) {
      await out.close();
      return;
    }
    _running = true;
    _cancelled = false;
    final results = <String, SourceAttempt>{};
    final counts = <SourceVerdict, int>{};
    var done = 0;
    void report({bool networkDown = false}) {
      final now = SourceCheckProgress(
        done: done,
        total: ids.length,
        counts: Map.of(counts),
        networkDown: networkDown,
      );
      progress.value = now;
      if (!out.isClosed) out.add(now);
    }

    report();
    // Hands out work as slots free, within the per-host limits.
    Future<void> pool(
      List<String> queue,
      void Function(String, SourceAttempt) on,
    ) {
      final pending = List.of(queue);
      final active = <String, int>{};
      var inFlight = 0;
      final finished = Completer<void>();
      void pump() {
        var i = 0;
        while (!_cancelled && inFlight < parallel && i < pending.length) {
          final id = pending[i];
          final family = _familyOf(id);
          if ((active[family] ?? 0) >= limitFor(id)) {
            i++;
            continue;
          }
          pending.removeAt(i);
          active[family] = (active[family] ?? 0) + 1;
          inFlight++;
          unawaited(
            _try(id).then((a) => on(id, a)).whenComplete(() {
              active[family] = active[family]! - 1;
              inFlight--;
              pump();
            }),
          );
        }
        if (inFlight == 0 &&
            (pending.isEmpty || _cancelled) &&
            !finished.isCompleted) {
          finished.complete();
        }
      }

      pump();
      return finished.future;
    }

    try {
      await pool(ids, (id, a) {
        results[id] = a;
        done++;
        final verdict = judge(a, store.of(id));
        counts[verdict.verdict] = (counts[verdict.verdict] ?? 0) + 1;
        // An answer is kept at once — it holds whatever else the run finds,
        // and a run stopped halfway through a thousand sources keeps what it
        // learned. A failure waits for the retry and the network check.
        if (a.failure == null) unawaited(store.put(id, verdict, defer: true));
        report();
      });
      if (_cancelled) {
        await store.flush();
        SourceHealthStore.bumpChanges();
        return;
      }

      final unreachable = results.values
          .where((a) => a.failure?.kind == SourceFailureKind.unreachable)
          .length;
      if (results.length >= 4 &&
          unreachable / results.length >= networkDownShare) {
        report(networkDown: true);
        return;
      }

      // One more try for what failed, so a single dropped request does not
      // count against a source the way two do.
      final retry = [
        for (final e in results.entries)
          if (e.value.failure != null &&
              e.value.failure!.kind != SourceFailureKind.blocked &&
              e.value.failure!.kind != SourceFailureKind.rateLimited &&
              e.value.failure!.kind != SourceFailureKind.outdated &&
              e.value.failure!.kind != SourceFailureKind.incompatible)
            e.key,
      ];
      final checks = <String, SourceCheck>{};
      for (final e in results.entries) {
        if (e.value.failure == null) continue;
        checks[e.key] = judge(e.value, store.of(e.key));
      }
      if (retry.isNotEmpty && !_cancelled) {
        await pool(retry, (id, a) {
          checks[id] = judge(a, checks[id]);
        });
      }
      await store.putAll(checks);
      SourceHealthStore.bumpChanges();
      counts
        ..clear()
        ..addAll({
          for (final v in SourceVerdict.values)
            v: ids.where((id) => store.verdictOf(id) == v).length,
        });
      report();
    } finally {
      _running = false;
      progress.value = null;
      await out.close();
    }
  }
}
