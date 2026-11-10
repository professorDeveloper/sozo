// A profile PIN with the server out of reach, and launching straight into the
// last profile. The fallback must only ever stand in for a server that could
// not be asked: a server that said no is never second-guessed by the device.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/profile_storage.dart';
import 'package:soplay/features/app_lock/data/pin_secrets.dart';
import 'package:soplay/features/profiles/data/profile_pin_store.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/data/profiles_remote_data_source.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';

const _main = HouseholdProfile(id: 'main1', name: 'Aziz', isDefault: true);
const _kid = HouseholdProfile(id: 'kid1', name: 'Lola', isKids: true);
const _guest = HouseholdProfile(id: 'guest1', name: 'Guest', hasPin: true);

enum _Net { up, down, gateway }

class _FakeRemote implements ProfilesRemoteDataSource {
  List<HouseholdProfile> profiles = [_main, _kid, _guest];
  String serverPin = '1234';
  _Net net = _Net.up;
  bool rateLimited = false;
  int verifies = 0;

  void _reach() {
    if (net == _Net.down) throw const ProfileException('offline');
    if (net == _Net.gateway) {
      throw const ProfileException('Bad gateway', status: 502);
    }
  }

  @override
  Future<ProfilesListing> list() async {
    _reach();
    return ProfilesListing(
      profiles: profiles,
      activeProfileId: ProfileScope.remoteId ?? _main.id,
      max: 4,
    );
  }

  @override
  Future<HouseholdProfile> verifyPin(String id, String pin) async {
    verifies++;
    _reach();
    if (rateLimited) throw const ProfileException('slow down', status: 429);
    if (pin != serverPin) {
      throw const ProfileException('wrong', code: 'PIN_INVALID', status: 403);
    }
    return profiles.firstWhere((p) => p.id == id);
  }

  @override
  Future<HouseholdProfile> update(
    String id,
    Map<String, dynamic> changes, {
    String? currentPin,
  }) async {
    _reach();
    final old = profiles.firstWhere((p) => p.id == id);
    final updated = HouseholdProfile(
      id: old.id,
      name: old.name,
      isDefault: old.isDefault,
      hasPin: changes.containsKey('pin') ? changes['pin'] != null : old.hasPin,
    );
    profiles = [for (final p in profiles) p.id == id ? updated : p];
    return updated;
  }

  @override
  Future<void> delete(String id, {String? currentPin}) async {
    _reach();
    profiles = profiles.where((p) => p.id != id).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoBiometrics extends DeviceBiometrics {
  @override
  Future<bool> isAvailable() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box settings;
  late _FakeRemote remote;
  late ProfilePinStore pins;
  late DateTime now;
  var loggedIn = true;

  ProfileSession session() => ProfileSession(
    remote: remote,
    isLoggedIn: () => loggedIn,
    settings: settings,
    pins: pins,
    accountId: () => 'acc1',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_pin_offline_');
    Hive.init(dir.path);
    ProfileStorage.directory = dir.path;
    ProfileScope.reset();
    Future<Box> memory(String name) => Hive.openBox(name, bytes: Uint8List(0));
    settings = await memory(AppConstants.settingsBox);
    for (final name in ProfileScope.profileBoxes) {
      await memory(name);
      await memory(ProfileScope.boxFor(name, _guest.id));
    }
    FlutterSecureStorage.setMockInitialValues({});
    now = DateTime(2026, 11, 7, 12);
    pins = ProfilePinStore(
      biometrics: _NoBiometrics(),
      clock: () => now,
      iterations: 10,
    );
    remote = _FakeRemote();
    loggedIn = true;
  });

  tearDown(() async {
    ProfileScope.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<ProfileException> refused(Future<Object?> f) async {
    try {
      await f;
    } on ProfileException catch (e) {
      return e;
    }
    fail('expected a ProfileException');
  }

  group('offline PIN', () {
    test('a PIN accepted online opens the profile offline', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      expect(await pins.has('acc1', _guest.id), isTrue);

      remote.net = _Net.down;
      expect((await s.verifyPin(_guest.id, '1234')).id, _guest.id);
    });

    test('a gateway error counts as unreachable', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      remote.net = _Net.gateway;
      expect((await s.verifyPin(_guest.id, '1234')).id, _guest.id);
    });

    test('offline, a wrong PIN is wrong', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      remote.net = _Net.down;
      final e = await refused(s.verifyPin(_guest.id, '9999'));
      expect(e.code, 'PIN_INVALID');
    });

    test('a server that said no is never overruled by the device', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      // Changed on another device: the old PIN is still what this one knows.
      remote.serverPin = '5555';
      final e = await refused(s.verifyPin(_guest.id, '1234'));
      expect(e.code, 'PIN_INVALID');
      expect(e.status, 403);

      remote.rateLimited = true;
      final limited = await refused(s.verifyPin(_guest.id, '5555'));
      expect(limited.status, 429);
    });

    test('offline with nothing kept says so', () async {
      final s = session();
      await s.refresh();
      remote.net = _Net.down;
      final e = await refused(s.verifyPin(_guest.id, '1234'));
      expect(e.code, 'PIN_NOT_ON_DEVICE');
    });

    test('offline guessing locks out', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      remote.net = _Net.down;
      for (var i = 1; i < PinBackoff.freeAttempts; i++) {
        expect((await refused(s.verifyPin(_guest.id, '0000'))).code,
            'PIN_INVALID');
      }
      final locked = await refused(s.verifyPin(_guest.id, '0000'));
      expect(locked.code, 'PIN_LOCKED');
      expect(locked.retryAt, now.add(PinBackoff.firstWait));
      expect(
        (await refused(s.verifyPin(_guest.id, '1234'))).code,
        'PIN_LOCKED',
      );
      now = now.add(const Duration(minutes: 1));
      expect((await s.verifyPin(_guest.id, '1234')).id, _guest.id);
    });

    test('a new PIN set here replaces the kept one', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      await s.update(_guest.id, {'pin': '7777'}, currentPin: '1234');
      remote.net = _Net.down;
      expect((await refused(s.verifyPin(_guest.id, '1234'))).code,
          'PIN_INVALID');
      expect((await s.verifyPin(_guest.id, '7777')).id, _guest.id);
    });

    test('removing the PIN forgets it', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      await s.update(_guest.id, {'pin': null}, currentPin: '1234');
      expect(await pins.has('acc1', _guest.id), isFalse);
    });

    test('a PIN removed elsewhere is forgotten on the next listing', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      remote.profiles = [
        _main,
        _kid,
        const HouseholdProfile(id: 'guest1', name: 'Guest'),
      ];
      await s.refresh();
      expect(await pins.has('acc1', _guest.id), isFalse);
    });

    test('deleting the profile forgets it', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      await s.delete(_guest.id, currentPin: '1234');
      expect(await pins.has('acc1', _guest.id), isFalse);
    });

    test('sign-out forgets every one', () async {
      final s = session();
      await s.refresh();
      await s.verifyPin(_guest.id, '1234');
      loggedIn = false;
      await s.forgetAll();
      expect(await pins.has('acc1', _guest.id), isFalse);
    });
  });

  group('launch', () {
    test('the picker is skipped only when asked to, and never for a PIN', () {
      expect(
        ProfileSession.opensLastProfile(askOnLaunch: true, restored: _kid),
        isFalse,
      );
      expect(
        ProfileSession.opensLastProfile(askOnLaunch: false, restored: _kid),
        isTrue,
      );
      expect(
        ProfileSession.opensLastProfile(askOnLaunch: false, restored: _guest),
        isFalse,
      );
      expect(
        ProfileSession.opensLastProfile(askOnLaunch: false, restored: null),
        isFalse,
      );
    });

    Future<ProfileSession> relaunchAs(HouseholdProfile last) async {
      await session().refresh();
      await settings.put(ProfileSession.activeKey, jsonEncode(last.toJson()));
      ProfileScope.set(namespace: last.namespace, remoteId: last.id);
      return session();
    }

    test('asks by default', () async {
      final s = await relaunchAs(_main);
      expect(s.askOnLaunch, isTrue);
      expect(s.shouldPick, isTrue);
    });

    test('with the setting off, opens the last profile', () async {
      await session().setAskOnLaunch(false);
      final s = await relaunchAs(_main);
      expect(s.active?.id, _main.id);
      expect(s.shouldPick, isFalse);
    });

    test('with the setting off, a PIN profile still goes through the picker',
        () async {
      await session().setAskOnLaunch(false);
      final s = await relaunchAs(_guest);
      expect(s.shouldPick, isTrue);
    });

    test('a fresh sign-in still picks', () async {
      await session().setAskOnLaunch(false);
      final s = session();
      await s.refresh();
      expect(s.shouldPick, isTrue);
    });

    test('the active profile is not asked for again once unlocked', () async {
      final s = session();
      await s.refresh();
      expect(s.needsPin(_guest), isTrue);
      await s.verifyPin(_guest.id, '1234');
      expect(s.needsPin(_guest), isTrue, reason: 'not the active one yet');
      await s.activate(_guest);
      expect(s.needsPin(_guest), isFalse);
      expect(s.needsPin(_kid), isFalse);
    });

    test('a fresh run asks for the active profile again', () async {
      final s = await relaunchAs(_guest);
      expect(s.active?.id, _guest.id);
      expect(s.needsPin(_guest), isTrue);
    });
  });
}
