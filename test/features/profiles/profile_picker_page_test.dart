import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/profile_storage.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/data/profiles_remote_data_source.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/pages/profile_picker_page.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';

const _main = HouseholdProfile(id: 'main1', name: 'Aziz', isDefault: true);
const _kid = HouseholdProfile(id: 'kid1', name: 'Lola', isKids: true);
const _guest = HouseholdProfile(id: 'guest1', name: 'Guest', hasPin: true);

class _FakeRemote implements ProfilesRemoteDataSource {
  final pins = <String>[];

  @override
  Future<ProfilesListing> list() async => ProfilesListing(
    profiles: const [_main, _kid, _guest],
    activeProfileId: ProfileScope.remoteId ?? _main.id,
    max: 5,
  );

  @override
  Future<HouseholdProfile> verifyPin(String id, String pin) async {
    pins.add(pin);
    if (pin != '1234') {
      throw const ProfileException('wrong', code: 'PIN_INVALID', status: 403);
    }
    return _guest;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ProfileSession session;
  late _FakeRemote remote;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_picker_');
    Hive.init(dir.path);
    ProfileStorage.directory = dir.path;
    ProfileScope.reset();
    // In memory, so switching inside the widget test needs no real I/O.
    Future<Box> memory(String name) => Hive.openBox(name, bytes: Uint8List(0));
    final settings = await memory(AppConstants.settingsBox);
    for (final name in ProfileScope.profileBoxes) {
      await memory(name);
      await memory(ProfileScope.boxFor(name, _guest.id));
    }
    remote = _FakeRemote();
    session = ProfileSession(
      remote: remote,
      isLoggedIn: () => true,
      settings: settings,
    );
    await session.refresh();
  });

  tearDown(() async {
    ProfileScope.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app() => MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/profiles',
      routes: [
        GoRoute(
          path: '/profiles',
          builder: (_, _) => ProfilePickerPage(session: session),
        ),
        GoRoute(
          path: '/main',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
      ],
    ),
  );

  testWidgets('shows every profile with its kids badge and PIN lock', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('Aziz'), findsOneWidget);
    expect(find.text('Lola'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.byType(KidsBadge), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('a PIN-protected profile opens only with its PIN', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();

    await tester.tap(find.text('Guest'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsNothing);

    Future<void> enter(String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await tester.runAsync(() async {
        await tester.tap(find.text('profiles.continue'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    await enter('9999');
    expect(remote.pins, ['9999']);
    expect(session.active?.id, _main.id);
    expect(find.text('HOME'), findsNothing);

    await enter('1234');
    await tester.pumpAndSettle();

    expect(remote.pins, ['9999', '1234']);
    expect(session.active?.id, _guest.id);
    expect(ProfileScope.namespace, _guest.id);
    expect(find.text('HOME'), findsOneWidget);
  });
}
