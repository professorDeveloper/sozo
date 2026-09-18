// What incognito promises, checked at every place that remembers something.
//
// The mode is one promise — "this session leaves no trace" — spread across a
// dozen unrelated write paths, and it is only ever as true as the least
// careful of them. Three were leaking when this file was written:
//
//   * every query typed in incognito was written to the search recents, which
//     the idle Search screen draws. Leave the player, go back to Search, and
//     the private session was listed on the screen;
//   * every Live TV channel opened was pushed onto the recent-channels row on
//     the home screen;
//   * a minute into playback the app pinged the streak endpoint, writing
//     "watched today" onto the account. That one the viewer cannot clear,
//     because it is not on their device.
//
// So the guarantee is stated once, here, surface by surface — and each case
// asserts the ordinary (non-incognito) write still happens, because "records
// nothing, ever" would pass a leak test and break the feature.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/search/data/search_recents_store.dart';
import 'package:soplay/features/streak/data/streak_remote_data_source.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

/// Answers only what the code under test asks, so a change to [HiveService]
/// elsewhere does not drag this file along with it.
class _Mode implements HiveService {
  _Mode({required this.incognito, this.loggedIn = true});
  final bool incognito;
  final bool loggedIn;

  @override
  bool get isIncognito => incognito;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Counts pings instead of making them.
class _CountingRemote implements StreakRemoteDataSource {
  int pings = 0;

  @override
  Future<StreakPingResult> ping(int tzOffsetMinutes) async {
    pings++;
    return const StreakPingResult(state: StreakState.empty);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_incognito_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
    // HiveService opens both boxes in its field initialisers.
    await Hive.openBox(AppConstants.authBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box(AppConstants.settingsBox).clear();
    await Hive.box(AppConstants.authBox).clear();
    await getIt.reset();
  });

  /// Puts a [HiveService] in front of the locator, which is how the stores that
  /// are not constructed with one find out what mode the app is in.
  void mode({required bool incognito}) {
    getIt.registerSingleton<HiveService>(_Mode(incognito: incognito));
  }

  group('the search box forgets what was typed in it', () {
    test('a query run in incognito is not written down', () async {
      mode(incognito: true);
      final store = SearchRecentsStore();

      await store.add('something private');

      expect(store.load(), isEmpty);
      expect(
        Hive.box(AppConstants.settingsBox).get('search_recent_queries'),
        anyOf(isNull, isEmpty),
        reason: 'nothing may reach the box, not even an empty key',
      );
    });

    test('and the list it returns is the stored one, not the new one', () {
      // The caller assigns this straight into the state that renders the
      // recents row: returning the query would put it on screen for the rest
      // of the session even with nothing on disk.
      mode(incognito: true);
      expect(SearchRecentsStore().add('something private'), completion(isEmpty));
    });

    test('an earlier query survives a private one', () async {
      // Incognito suppresses the write; it must not clear what was there.
      mode(incognito: false);
      await SearchRecentsStore().add('public');
      await getIt.reset();
      mode(incognito: true);

      await SearchRecentsStore().add('private');

      expect(SearchRecentsStore().load(), ['public']);
    });

    test('and an ordinary query is still remembered', () async {
      mode(incognito: false);
      expect(await SearchRecentsStore().add('ordinary'), ['ordinary']);
    });
  });

  group('the Live TV row forgets which channel was on', () {
    // Through the real HiveService: the guard is inside it, and a fake would
    // be testing the fake.
    test('a channel opened in incognito is not added', () async {
      final hive = HiveService();
      await hive.setIncognito(true);

      await hive.pushLiveTvRecent('bbc-one');

      expect(hive.getLiveTvRecent(), isEmpty);
    });

    test('and one opened normally is', () async {
      final hive = HiveService();
      await hive.setIncognito(false);

      await hive.pushLiveTvRecent('bbc-one');

      expect(hive.getLiveTvRecent(), ['bbc-one']);
    });

    test('a private channel does not disturb the row already there', () async {
      final hive = HiveService();
      await hive.setIncognito(false);
      await hive.pushLiveTvRecent('bbc-one');
      await hive.setIncognito(true);

      await hive.pushLiveTvRecent('somewhere-private');

      expect(hive.getLiveTvRecent(), ['bbc-one']);
    });
  });

  group('the streak does not learn about a private session', () {
    test('no ping while incognito', () async {
      // The one record the viewer cannot go and delete, because it lives on
      // the account rather than on the phone.
      final remote = _CountingRemote();
      final service = StreakService(
        remote: remote,
        hive: _Mode(incognito: true),
      );

      expect(await service.ping(), isNull);
      expect(remote.pings, 0, reason: 'the request must not be sent at all');
    });

    test('but an ordinary session still counts', () async {
      // Without this the leak test above passes on a streak feature that
      // simply never works.
      final remote = _CountingRemote();
      final service = StreakService(
        remote: remote,
        hive: _Mode(incognito: false),
      );

      expect(await service.ping(), isNotNull);
      expect(remote.pings, 1);
    });

    test('and a signed-out session was never going to ping anyway', () async {
      final remote = _CountingRemote();
      final service = StreakService(
        remote: remote,
        hive: _Mode(incognito: false, loggedIn: false),
      );

      expect(await service.ping(), isNull);
      expect(remote.pings, 0);
    });
  });
}
