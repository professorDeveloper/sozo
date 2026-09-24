// Household profiles on the device: the storage switch is the part that can
// lose somebody's data, so it is checked here box by box.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/profile_storage.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/data/profiles_remote_data_source.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';

const _main = HouseholdProfile(id: 'main1', name: 'Aziz', isDefault: true);
const _kid = HouseholdProfile(id: 'kid1', name: 'Lola', isKids: true);
const _guest = HouseholdProfile(id: 'guest1', name: 'Guest', hasPin: true);

class _FakeRemote implements ProfilesRemoteDataSource {
  List<HouseholdProfile> profiles = [_main, _kid, _guest];
  bool staleActive = false;
  bool offline = false;
  final deleted = <String>[];

  @override
  Future<ProfilesListing> list() async {
    if (offline) throw const ProfileException('offline');
    return ProfilesListing(
      profiles: profiles,
      activeProfileId: staleActive ? null : (ProfileScope.remoteId ?? _main.id),
      max: 5,
    );
  }

  @override
  Future<void> delete(String id, {String? currentPin}) async {
    deleted.add(id);
    profiles = profiles.where((p) => p.id != id).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

HistoryItem _row(String url) => HistoryItem(
  contentUrl: url,
  provider: 'p',
  title: url,
  watchedAt: DateTime(2026, 9, 1).millisecondsSinceEpoch,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box settings;
  late _FakeRemote remote;
  var loggedIn = true;
  var scopeChanges = 0;

  ProfileSession session() => ProfileSession(
    remote: remote,
    isLoggedIn: () => loggedIn,
    onScopeChanged: ({required bool resync}) async => scopeChanges++,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_profiles_');
    Hive.init(dir.path);
    ProfileStorage.directory = dir.path;
    ProfileScope.reset();
    settings = await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.authBox);
    for (final name in ProfileScope.profileBoxes) {
      await Hive.openBox(name);
    }
    remote = _FakeRemote();
    loggedIn = true;
    scopeChanges = 0;
  });

  tearDown(() async {
    ProfileScope.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('existing data becomes the main profile\'s, untouched', () async {
    final history = HistoryService();
    await history.save(_row('old-show'));
    await settings.put(AppConstants.incognitoKey, true);

    final s = session();
    expect(await s.refresh(), isTrue);

    expect(s.active, _main);
    expect(ProfileScope.namespace, isNull);
    expect(ProfileScope.remoteId, 'main1');
    expect(history.getAll().map((e) => e.contentUrl), ['old-show']);
    expect(HiveService().isIncognito, isTrue);
    expect(scopeChanges, 0, reason: 'nothing moved, so nothing to rebuild');
  });

  test('switching swaps history, My List and personal settings', () async {
    final history = HistoryService();
    final favorites = MyListLocalDataSource();
    await history.save(_row('parent-show'));
    await favorites.add(
      const FavoriteEntity(
        provider: 'p',
        contentUrl: 'fav',
        title: 'Fav',
        thumbnail: '',
      ),
    );
    await settings.put('history_sync_cursor', 'main-cursor');

    final s = session();
    await s.refresh();
    await s.activate(_guest);

    expect(ProfileScope.namespace, 'guest1');
    expect(history.getAll(), isEmpty);
    expect(favorites.getAll(), isEmpty);
    expect(settings.get(ProfileScope.key('history_sync_cursor')), isNull);

    await history.save(_row('guest-show'));
    expect(
      Hive.box('history_box__p_guest1').length,
      1,
      reason: 'the guest writes to its own box',
    );
    expect(Hive.box(AppConstants.historyBox).length, 1);

    await s.activate(_main);
    expect(history.getAll().map((e) => e.contentUrl), ['parent-show']);
    expect(favorites.getAll().map((e) => e.contentUrl), ['fav']);
    expect(settings.get('history_sync_cursor'), 'main-cursor');
    expect(scopeChanges, 2);
  });

  test('a kids profile never shows 18+, whatever was chosen', () async {
    final hive = HiveService();
    await hive.setShowAdultContent(true);
    expect(hive.showAdultContent, isTrue);

    final s = session();
    await s.refresh();
    await s.activate(_kid);

    expect(ProfileScope.isKids, isTrue);
    expect(hive.showAdultContent, isFalse);
    await hive.setShowAdultContent(true);
    expect(hive.showAdultContent, isFalse);
    expect(s.canManage, isFalse);

    await s.activate(_main);
    expect(hive.showAdultContent, isTrue);
  });

  test('an extra profile does not inherit the legacy 18+ switch', () async {
    await settings.put(AppConstants.showNsfwMangaSourcesKey, true);
    final hive = HiveService();
    expect(hive.showAdultContent, isTrue);

    final s = session();
    await s.refresh();
    await s.activate(_guest);
    expect(hive.showAdultContent, isFalse);
  });

  test(
    'picker is due only with several profiles and until one is chosen',
    () async {
      final s = session();
      await s.refresh();
      expect(s.shouldPick, isTrue);
      await s.activate(_main);
      expect(s.shouldPick, isFalse);

      remote.profiles = [_main];
      final single = session();
      await single.refresh();
      expect(single.shouldPick, isFalse);
    },
  );

  test('the active choice survives a restart', () async {
    final s = session();
    await s.refresh();
    await s.activate(_kid);
    await HistoryService().save(_row('kid-show'));
    await Hive.close();

    ProfileScope.reset();
    settings = await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.authBox);
    for (final name in ProfileScope.profileBoxes) {
      await Hive.openBox(name);
    }
    await ProfileSession.restore(settings, loggedIn: true);

    expect(ProfileScope.namespace, 'kid1');
    expect(ProfileScope.isKids, isTrue);
    expect(HistoryService().getAll().map((e) => e.contentUrl), ['kid-show']);
    expect(session().active?.id, 'kid1');
  });

  test('restore ignores a stored profile once signed out', () async {
    await settings.put(ProfileSession.activeKey, jsonEncode(_kid.toJson()));
    await ProfileSession.restore(settings, loggedIn: false);
    expect(ProfileScope.namespace, isNull);
    expect(ProfileScope.remoteId, isNull);
    expect(session().active, isNull);
  });

  test('a profile deleted elsewhere falls back to the main one', () async {
    final s = session();
    await s.refresh();
    await s.activate(_guest);
    var picks = 0;
    s.pickRequests.addListener(() => picks++);

    remote.staleActive = true;
    remote.profiles = [_main, _kid];
    await s.refresh();

    expect(s.active, _main);
    expect(ProfileScope.namespace, isNull);
    expect(picks, 1);
  });

  test('deleting a profile removes its data from the device', () async {
    final s = session();
    await s.refresh();
    await s.activate(_guest);
    await HistoryService().save(_row('guest-show'));
    await settings.put(ProfileScope.key(AppConstants.incognitoKey), true);
    await s.activate(_main);

    await s.delete(_guest.id);

    expect(remote.deleted, ['guest1']);
    expect(s.byId('guest1'), isNull);
    expect(await Hive.boxExists('history_box__p_guest1'), isFalse);
    expect(settings.keys.where(ProfileScope.isProfileKey), isEmpty);
  });

  test('deleting the active profile moves to the main one first', () async {
    final s = session();
    await s.refresh();
    await s.activate(_guest);
    await s.delete(_guest.id);
    expect(s.active, _main);
    expect(ProfileScope.namespace, isNull);
  });

  test(
    'sign-out removes every extra profile and keeps the main boxes',
    () async {
      await HistoryService().save(_row('parent-show'));
      final s = session();
      await s.refresh();
      await s.activate(_kid);
      await HistoryService().save(_row('kid-show'));
      await settings.put(ProfileScope.key(AppConstants.watchStatsKey), 'x');
      await s.activate(_guest);
      await HistoryService().save(_row('guest-show'));

      loggedIn = false;
      await s.forgetAll();

      expect(ProfileScope.namespace, isNull);
      expect(ProfileScope.remoteId, isNull);
      expect(s.profiles, isEmpty);
      expect(await Hive.boxExists('history_box__p_kid1'), isFalse);
      expect(await Hive.boxExists('history_box__p_guest1'), isFalse);
      expect(settings.keys.where(ProfileScope.isProfileKey), isEmpty);
      expect(settings.get(ProfileSession.cacheKey), isNull);
      expect(Hive.box(AppConstants.historyBox).length, 1);
    },
  );

  test('offline refresh keeps the cached list', () async {
    final s = session();
    await s.refresh();
    remote.offline = true;
    final again = session();
    expect(again.profiles.length, 3);
    expect(await again.refresh(), isFalse);
    expect(again.profiles.length, 3);
  });
}
