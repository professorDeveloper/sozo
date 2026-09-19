// An extension search that never answers has to end anyway.
//
// The backend search goes through Dio, which has connect, send and receive
// timeouts. The five on-device host paths — CloudStream, Aniyomi, Manga,
// Mangayomi and the JS runtime — had none at all. A plugin whose `search()`
// never returns (a dead host, a Cloudflare challenge that never resolves, a
// socket the plugin opened with no read timeout of its own) left the Search tab
// on its skeleton forever: no results, no empty state, no error, and no way out
// but backing off the screen.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/repositories/search_repository_imp.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

/// A Mangayomi source that behaves however the test says — including never
/// answering, which is the case under test.
class _Bridge implements MangayomiBridge {
  _Bridge(this.answer);

  /// Returns the future the host would return. A future that never completes
  /// stands for the plugin that hangs.
  final Future<Map<String, dynamic>> Function() answer;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> search(String id, String query, {int page = 1}) {
    calls++;
    return answer();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The backend, which must never be reached on a host path.
class _UnusedBackend implements SearchDataSource {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _OnSource implements HiveService {
  _OnSource(this.id);
  final String id;

  @override
  String getCurrentProvider() => id;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  SearchRepositoryImp repoOver(_Bridge bridge) => SearchRepositoryImp(
    dataSource: _UnusedBackend(),
    mangayomi: bridge,
    hive: _OnSource('my:somesource'),
  );

  test('a host that never answers fails instead of hanging', () {
    // FakeAsync because the budget is deliberately long — a first search has
    // to download and dex-load an extension APK — and a test should not sit
    // through it.
    fakeAsync((async) {
      final bridge = _Bridge(() => Completer<Map<String, dynamic>>().future);
      Result<Object?>? outcome;
      repoOver(bridge).searchMovies('anything').then((r) => outcome = r);

      async.elapse(CrossSearchEngine.channelTimeout - const Duration(seconds: 1));
      expect(
        outcome,
        isNull,
        reason: 'cut off early, a slow-but-working source looks broken',
      );

      async.elapse(const Duration(seconds: 2));
      expect(
        outcome,
        isNotNull,
        reason: 'this is the hang: without a budget nothing ever resolves',
      );
      expect(outcome!.isError, isTrue);
      expect(
        outcome!.getErrorOrNull().toString(),
        contains('no answer'),
        reason:
            'a host that never replied is not the same as one that replied '
            'with a failure, and only this one is worth trying another source '
            'for',
      );
    });
  });

  test('a host that answers in time is not disturbed', () {
    // The other half: the budget must not truncate a source that is merely
    // slow, which is every extension on its first use.
    fakeAsync((async) {
      final slow = CrossSearchEngine.channelTimeout - const Duration(seconds: 5);
      final bridge = _Bridge(
        () => Future.delayed(slow, () => {'items': <dynamic>[], 'page': 1}),
      );
      Result<Object?>? outcome;
      repoOver(bridge).searchMovies('anything').then((r) => outcome = r);

      async.elapse(slow + const Duration(seconds: 1));

      expect(outcome, isNotNull);
      expect(outcome!.isSuccess, isTrue);
    });
  });

  test('and the budget is the one cross-search already uses', () {
    // Two paths search the same extension. Picking a second number here is how
    // they end up disagreeing about whether a source works.
    expect(CrossSearchEngine.channelTimeout.inSeconds, greaterThan(30));
  });
}
