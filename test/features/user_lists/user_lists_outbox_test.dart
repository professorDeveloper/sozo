// Watch Later / Watched edits made offline must survive the next fetch.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/data/datasources/user_lists_remote_data_source.dart';
import 'package:soplay/features/user_lists/data/repositories/user_lists_repository_impl.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';
import 'package:soplay/features/user_lists/presentation/pages/user_lists_page.dart';

class _SignedIn implements HiveService {
  @override
  bool get isLoggedIn => true;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A server that can be taken offline and records what reached it.
class _Server implements UserListsRemoteDataSource {
  bool offline = false;
  final calls = <String>[];
  final lists = <UserListKind, List<FavoriteModel>>{
    for (final k in UserListKind.values) k: [],
  };

  @override
  Future<List<FavoriteModel>> getList(UserListKind kind) async {
    if (offline) throw const SocketException('offline');
    return List.of(lists[kind]!);
  }

  @override
  Future<void> add(
    UserListKind kind, {
    required String provider,
    required String contentUrl,
    required String title,
    required String thumbnail,
  }) async {
    if (offline) throw const SocketException('offline');
    calls.add('add ${kind.slug} $contentUrl');
    lists[kind]!.removeWhere((e) => e.contentUrl == contentUrl);
    lists[kind]!.insert(
      0,
      FavoriteModel(
        provider: provider,
        contentUrl: contentUrl,
        title: title,
        thumbnail: thumbnail,
      ),
    );
  }

  @override
  Future<void> remove(UserListKind kind, String contentUrl) async {
    if (offline) throw const SocketException('offline');
    calls.add('remove ${kind.slug} $contentUrl');
    lists[kind]!.removeWhere((e) => e.contentUrl == contentUrl);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

FavoriteEntity _item(String url) =>
    FavoriteEntity(provider: 'p', contentUrl: url, title: url, thumbnail: '');

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_user_lists_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.userListsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async => Hive.box(AppConstants.userListsBox).clear());

  group('outbox', () {
    test('an offline add is replayed before the server list replaces the '
        'cache', () async {
      final server = _Server()..offline = true;
      var t = 0;
      final repo = UserListsRepositoryImpl(
        server,
        _SignedIn(),
        clock: () => ++t,
      );

      await repo.add(UserListKind.watchLater, _item('a'));
      expect(repo.pendingOps(), hasLength(1));

      server.offline = false;
      final list = (await repo.getList(UserListKind.watchLater)).getOrNull()!;

      expect(server.calls, ['add ${UserListKind.watchLater.slug} a']);
      expect(list.map((e) => e.contentUrl), ['a']);
      expect(repo.pendingOps(), isEmpty);
    });

    test('add then remove offline sends only the newest op', () async {
      final server = _Server()..offline = true;
      server.lists[UserListKind.watched]!.add(
        const FavoriteModel(
          provider: 'p',
          contentUrl: 'x',
          title: 'x',
          thumbnail: '',
        ),
      );
      var t = 0;
      final repo = UserListsRepositoryImpl(
        server,
        _SignedIn(),
        clock: () => ++t,
      );

      await repo.add(UserListKind.watched, _item('a'));
      await repo.remove(UserListKind.watched, 'a');
      await repo.remove(UserListKind.watched, 'x');

      final ops = repo.pendingOps();
      expect(
        ops.map((o) => '${o.isAdd ? 'add' : 'remove'} ${o.entity.contentUrl}'),
        ['remove a', 'remove x'],
      );

      server.offline = false;
      final list = (await repo.getList(UserListKind.watched)).getOrNull()!;
      final slug = UserListKind.watched.slug;
      expect(server.calls, ['remove $slug a', 'remove $slug x']);
      expect(list, isEmpty);
    });

    test(
      'ops replay oldest first, and a failed fetch keeps them overlaid',
      () async {
        final server = _Server()..offline = true;
        var t = 0;
        final repo = UserListsRepositoryImpl(
          server,
          _SignedIn(),
          clock: () => ++t,
        );

        await repo.add(UserListKind.watchLater, _item('a'));
        await repo.add(UserListKind.watched, _item('a'));
        await repo.add(UserListKind.watchLater, _item('b'));

        // Still offline: the cache, not an error, and the edits are all there.
        final offline = (await repo.getList(
          UserListKind.watchLater,
        )).getOrNull()!;
        expect(offline.map((e) => e.contentUrl), ['b']);

        server.offline = false;
        await repo.flushOutbox();
        final later = UserListKind.watchLater.slug;
        final watched = UserListKind.watched.slug;
        expect(server.calls, [
          'add $later a',
          'add $watched a',
          'add $later b',
        ]);
      },
    );

    test('a server copy without unsent edits does not undo them', () async {
      // The push fails but the fetch that follows works: a flaky link.
      final server = _Server();
      var failAdds = true;
      var t = 0;
      final repo = UserListsRepositoryImpl(
        _FlakyAdds(server, () => failAdds),
        _SignedIn(),
        clock: () => ++t,
      );

      await repo.add(UserListKind.watchLater, _item('a'));
      final list = (await repo.getList(UserListKind.watchLater)).getOrNull()!;
      expect(list.map((e) => e.contentUrl), ['a']);
      expect(repo.pendingOps(), hasLength(1));

      failAdds = false;
      await repo.flushOutbox();
      expect(repo.pendingOps(), isEmpty);
      expect(server.lists[UserListKind.watchLater]!.map((e) => e.contentUrl), [
        'a',
      ]);
    });

    test('connectivity regain flushes the outbox', () async {
      final server = _Server()..offline = true;
      final reconnects = StreamController<void>();
      final repo = UserListsRepositoryImpl(
        server,
        _SignedIn(),
        reconnects: reconnects.stream,
      );
      await repo.add(UserListKind.watchLater, _item('a'));
      server.offline = false;
      reconnects.add(null);
      await pumpEventQueue();
      expect(repo.pendingOps(), isEmpty);
      expect(server.calls, hasLength(1));
      repo.dispose();
      await reconnects.close();
    });
  });

  group('no cache', () {
    test('a failed fetch is a failure, not an empty list', () async {
      final repo = UserListsRepositoryImpl(
        _Server()..offline = true,
        _SignedIn(),
      );
      final result = await repo.getList(UserListKind.watched);
      expect(result.isError, isTrue);
    });

    test('with a cache it is the cache', () async {
      final server = _Server();
      final repo = UserListsRepositoryImpl(server, _SignedIn());
      await repo.getList(UserListKind.watched);
      server.offline = true;
      final result = await repo.getList(UserListKind.watched);
      expect(result.getOrNull(), isEmpty);
    });

    testWidgets('the tab shows Retry, and Retry loads', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      await getIt.reset();
      final repo = _ScriptedRepo();
      getIt.registerSingleton<UserListsRepository>(repo);

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
              home: const UserListsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(UserListLoadError), findsOneWidget);
      expect(find.text('Nothing saved yet'), findsNothing);

      repo.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(UserListLoadError), findsNothing);
      expect(find.text('a'), findsOneWidget);
      await getIt.reset();
    });
  });
}

class _FlakyAdds implements UserListsRemoteDataSource {
  _FlakyAdds(this.inner, this.failing);
  final _Server inner;
  final bool Function() failing;

  @override
  Future<List<FavoriteModel>> getList(UserListKind kind) => inner.getList(kind);

  @override
  Future<void> add(
    UserListKind kind, {
    required String provider,
    required String contentUrl,
    required String title,
    required String thumbnail,
  }) async {
    if (failing()) throw const SocketException('flaky');
    return inner.add(
      kind,
      provider: provider,
      contentUrl: contentUrl,
      title: title,
      thumbnail: thumbnail,
    );
  }

  @override
  Future<void> remove(UserListKind kind, String contentUrl) =>
      inner.remove(kind, contentUrl);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ScriptedRepo implements UserListsRepository {
  bool fail = true;

  @override
  Future<Result<List<FavoriteEntity>>> getList(UserListKind kind) async => fail
      ? const Failure(UserListUnavailable())
      : Success(kind == UserListKind.watchLater ? [_item('a')] : const []);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
