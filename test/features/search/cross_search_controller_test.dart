import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';
import 'package:soplay/features/search/presentation/blocs/cross_search_controller.dart';

/// A fan-out that emits results without touching a network, a WebView or a
/// plugin host — the controller's batching is the thing under test, and the
/// real engine's dependencies would only be faked into silence anyway.
class _StubFanOut implements SearchFanOut {
  _StubFanOut(this.emit);

  /// Drives what the run produces, so a test can decide when legs land.
  final void Function(StreamController<ProviderSearchResult> out) emit;

  @override
  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int page = 1,
    int concurrency = 5,
    Duration perProviderTimeout = const Duration(seconds: 10),
  }) {
    final out = StreamController<ProviderSearchResult>();
    emit(out);
    return out.stream;
  }

  /// The stub searches exactly what it is given: the ceiling is the engine's
  /// job and has its own test.
  @override
  List<ProviderRef> planLegs(List<ProviderRef> set, {int limit = 60}) => set;

  @override
  Future<ProviderSearchResult> searchProvider(
    ProviderRef ref,
    String query, {
    int page = 1,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      throw UnimplementedError();
}

ProviderRef _ref(int i) =>
    ProviderRef(id: 'p$i', name: 'Provider $i', kind: ProviderKind.server);

MovieEntity _item(int i) => MovieEntity(
      externalId: 'x$i',
      title: 'Naruto $i',
      description: '',
      slug: 's$i',
      url: 'https://example.test/$i',
      provider: 'p$i',
      thumbnail: null,
      year: null,
      rating: null,
      qualities: null,
      category: "",
    );

ProviderSearchResult _leg(int i) => ProviderSearchResult(
      provider: _ref(i),
      items: [_item(i)],
      status: ProviderSearchStatus.ok,
    );

void main() {
  test('a thousand legs do not cause a thousand rebuilds', () {
    // The bug this guards: every arriving leg used to trigger a full
    // `mergeSearchResults` — which regroups and re-scores every item collected
    // so far — plus a `notifyListeners`. That is quadratic in the number of
    // sources, on the UI isolate, and it is what made an all-source search
    // stop responding on a device with a large provider list.
    fakeAsync((async) {
      const legs = 1000;
      late StreamController<ProviderSearchResult> out;
      final controller = CrossSearchController(
        engine: _StubFanOut((c) => out = c),
        set: [for (var i = 0; i < legs; i++) _ref(i)],
      );

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.onQueryChanged('naruto');
      async.elapse(const Duration(milliseconds: 500)); // past the debounce
      final beforeLegs = notifications;

      // Every leg lands inside one flush window.
      for (var i = 0; i < legs; i++) {
        out.add(_leg(i));
      }
      async.elapse(const Duration(milliseconds: 300));

      final forLegs = notifications - beforeLegs;
      expect(
        forLegs,
        lessThan(5),
        reason: '$legs legs in one window should coalesce into a handful of '
            'rebuilds, not one each',
      );
      expect(controller.merged, hasLength(legs));

      controller.dispose();
    });
  });

  test('the last legs are not stranded in an unflushed window', () {
    // The batching's own failure mode: a run that ends while results are still
    // sitting in the current window would report itself finished on a list that
    // does not contain them.
    fakeAsync((async) {
      late StreamController<ProviderSearchResult> out;
      final controller = CrossSearchController(
        engine: _StubFanOut((c) => out = c),
        set: [_ref(0), _ref(1)],
      );

      controller.onQueryChanged('naruto');
      async.elapse(const Duration(milliseconds: 500));

      out.add(_leg(0));
      out.add(_leg(1));
      // Closing immediately, well inside the 250ms window.
      out.close();
      async.elapse(const Duration(milliseconds: 10));

      expect(controller.phase, CrossSearchPhase.done);
      expect(controller.merged, hasLength(2),
          reason: 'both legs must be merged before the run reports done');

      controller.dispose();
    });
  });

  test('a new query drops the previous run\'s pending flush', () {
    fakeAsync((async) {
      final controllers = <StreamController<ProviderSearchResult>>[];
      final controller = CrossSearchController(
        engine: _StubFanOut(controllers.add),
        set: [_ref(0)],
      );

      controller.onQueryChanged('naruto');
      async.elapse(const Duration(milliseconds: 500));
      controllers.first.add(_leg(0));

      // Retyping before the window elapses: the first run's merge must not
      // land on top of the second run's empty list.
      controller.onQueryChanged('bleach');
      async.elapse(const Duration(milliseconds: 500));

      expect(controller.merged, isEmpty);

      controller.dispose();
    });
  });
}
