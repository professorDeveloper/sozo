// A failed next page used to clear the spinner and leave nothing, and every
// scroll frame near the bottom fired another request.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/widgets/load_more_failed_footer.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/home/domain/usecase/view_all_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_event.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_state.dart';

MovieEntity _movie(int i) => MovieEntity(
  externalId: '$i',
  title: 'Title $i',
  description: '',
  slug: 'title-$i',
  url: 'https://example.test/$i',
  provider: 'p',
  thumbnail: '',
  year: 2024,
  rating: null,
  qualities: const [],
  category: '',
);

class _Pages implements HomeRepository {
  bool failMore = true;
  final requested = <int>[];

  @override
  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) async {
    requested.add(page);
    if (page > 1 && failMore) return Failure(Exception('timeout'));
    return Success(
      ViewAllPagingEntity(
        page: page,
        totalPages: 5,
        provider: 'p',
        items: [for (var i = 0; i < 3; i++) _movie(page * 10 + i)],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('backoff', () {
    test('doubles and is capped', () {
      expect(ViewAllBloc.backoffFor(0), Duration.zero);
      expect(ViewAllBloc.backoffFor(1), const Duration(seconds: 2));
      expect(ViewAllBloc.backoffFor(2), const Duration(seconds: 4));
      expect(ViewAllBloc.backoffFor(3), const Duration(seconds: 8));
      expect(ViewAllBloc.backoffFor(20), ViewAllBloc.maxBackoff);
    });

    test('a failed page sets loadMoreFailed and keeps the grid', () async {
      final repo = _Pages();
      var now = DateTime(2026);
      final bloc = ViewAllBloc(useCase: ViewAllUseCase(repo), now: () => now);
      bloc.add(ViewAllLoad(key: 'k'));
      await pumpEventQueue();
      bloc.add(ViewAllLoadMore());
      await pumpEventQueue();

      final s = bloc.state as ViewAllLoaded;
      expect(s.loadMoreFailed, isTrue);
      expect(s.items, hasLength(3));
      expect(repo.requested, [1, 2]);

      // Scroll frames inside the backoff send nothing.
      for (var i = 0; i < 10; i++) {
        bloc.add(ViewAllLoadMore());
      }
      await pumpEventQueue();
      expect(repo.requested, [1, 2]);

      // After it, one scroll tries once — and fails, so the wait doubles.
      now = now.add(const Duration(seconds: 3));
      bloc.add(ViewAllLoadMore());
      await pumpEventQueue();
      expect(repo.requested, [1, 2, 2]);
      now = now.add(const Duration(seconds: 3));
      bloc.add(ViewAllLoadMore());
      await pumpEventQueue();
      expect(repo.requested, [1, 2, 2], reason: 'second backoff is 4s');

      // Retry from the footer ignores the backoff.
      repo.failMore = false;
      bloc.add(ViewAllLoadMore(retry: true));
      await pumpEventQueue();
      final ok = bloc.state as ViewAllLoaded;
      expect(repo.requested, [1, 2, 2, 2]);
      expect(ok.loadMoreFailed, isFalse);
      expect(ok.items, hasLength(6));
      await bloc.close();
    });
  });

  testWidgets('the footer reads "Couldn\'t load more · Retry" and retries', (
    tester,
  ) async {
    final repo = _Pages();
    late final ViewAllBloc bloc;
    await tester.runAsync(() async {
      bloc = ViewAllBloc(useCase: ViewAllUseCase(repo));
      bloc.add(ViewAllLoad(key: 'k'));
      await pumpEventQueue();
      bloc.add(ViewAllLoadMore());
      await pumpEventQueue();
    });
    expect((bloc.state as ViewAllLoaded).loadMoreFailed, isTrue);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _Translations(),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: BlocBuilder<ViewAllBloc, ViewAllState>(
                bloc: bloc,
                builder: (context, state) =>
                    state is ViewAllLoaded && state.loadMoreFailed
                    ? LoadMoreFailedFooter(
                        onRetry: () => bloc.add(ViewAllLoadMore(retry: true)),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't load more"), findsOneWidget);
    expect(find.text(' · '), findsOneWidget);

    repo.failMore = false;
    await tester.tap(find.text('Retry'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();

    expect(find.byType(LoadMoreFailedFooter), findsNothing);
    expect(repo.requested, [1, 2, 2]);
    await tester.runAsync(bloc.close);
  });
}
