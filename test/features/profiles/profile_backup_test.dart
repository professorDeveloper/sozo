import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/profile/data/backup_service.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_profile_backup_');
    Hive.init(dir.path);
    ProfileScope.reset();
    await Hive.openBox(AppConstants.settingsBox);
    for (final base in ProfileScope.profileBoxes) {
      await Hive.openBox(base);
      await Hive.openBox(ProfileScope.boxFor(base, 'kid1'));
    }
  });

  tearDown(() async {
    ProfileScope.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<File> backupFile(Map<String, dynamic> boxes) async {
    final file = File('${dir.path}/backup.json');
    await file.writeAsString(
      jsonEncode({
        'format': BackupService.formatId,
        'version': 2,
        'boxes': boxes,
      }),
    );
    return file;
  }

  test('a restore lands in the active profile, not the main one', () async {
    ProfileScope.set(namespace: 'kid1', remoteId: 'kid1', kids: true);
    final file = await backupFile({
      AppConstants.settingsBox: {
        AppConstants.incognitoKey: true,
        AppConstants.languageKey: 'uz',
        ProfileSession.activeKey: '{"id":"someone-else"}',
        'incognito_mode@p_other': true,
      },
      AppConstants.historyBox: {'p::show': '{"title":"Show"}'},
    });

    final summary = await BackupService().import(file);
    expect(summary.error, isNull);

    final settings = Hive.box(AppConstants.settingsBox);
    expect(settings.get('incognito_mode@p_kid1'), isTrue);
    expect(settings.get(AppConstants.incognitoKey), isNull);
    expect(settings.get(AppConstants.languageKey), 'uz');
    expect(settings.containsKey(ProfileSession.activeKey), isFalse);
    expect(settings.containsKey('incognito_mode@p_other'), isFalse);

    expect(Hive.box('history_box__p_kid1').get('p::show'), isNotNull);
    expect(Hive.box(AppConstants.historyBox).isEmpty, isTrue);
  });

  test('with the main profile active a restore behaves as before', () async {
    final file = await backupFile({
      AppConstants.settingsBox: {AppConstants.incognitoKey: true},
      AppConstants.favoritesBox: {'p::fav': '{"title":"Fav"}'},
    });

    await BackupService().import(file);

    expect(
      Hive.box(AppConstants.settingsBox).get(AppConstants.incognitoKey),
      isTrue,
    );
    expect(Hive.box(AppConstants.favoritesBox).get('p::fav'), isNotNull);
    expect(Hive.box('favorites_box__p_kid1').isEmpty, isTrue);
  });
}
