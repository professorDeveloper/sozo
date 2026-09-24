import 'dart:async';

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
  static const Duration timeout = Duration(seconds: 35);

  /// How many sources are asked at once. Extension hosts load code on first
  /// use and share one JS runtime; more than this only queues inside them
  /// while making the phone warm.
  static const int parallel = 3;

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
      final home = await browse.load(id).timeout(timeout);
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
    unawaited(_run(ids, controller));
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
      if (!out.isClosed) {
        out.add(
          SourceCheckProgress(
            done: done,
            total: ids.length,
            counts: Map.of(counts),
            networkDown: networkDown,
          ),
        );
      }
    }

    report();
    Future<void> pool(
      List<String> queue,
      void Function(String, SourceAttempt) on,
    ) async {
      var next = 0;
      Future<void> worker() async {
        while (next < queue.length && !_cancelled) {
          final id = queue[next++];
          on(id, await _try(id));
        }
      }

      await Future.wait(List.generate(parallel, (_) => worker()));
    }

    try {
      await pool(ids, (id, a) {
        results[id] = a;
        done++;
        final provisional = judge(a, store.of(id)).verdict;
        counts[provisional] = (counts[provisional] ?? 0) + 1;
        report();
      });
      if (_cancelled) return;

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
            v: checks.values.where((c) => c.verdict == v).length,
        });
      report();
    } finally {
      _running = false;
      await out.close();
    }
  }
}
