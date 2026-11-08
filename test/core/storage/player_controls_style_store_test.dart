import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/native/player_controls_style.dart';
import 'package:soplay/core/storage/hive_service.dart';

void main() {
  late Directory dir;
  late HiveService hive;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_controls_style_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.authBox);
    await Hive.openBox(AppConstants.settingsBox);
    hive = HiveService();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('nothing stored reads as the classic glass', () {
    expect(hive.storedPlayerControlsStyle, isNull);
    expect(hive.playerControlsStyle, PlayerControlsStyle.classicGlass);
  });

  test('a stored choice is respected', () async {
    for (final s in PlayerControlsStyle.values) {
      await hive.setPlayerControlsStyle(s);
      expect(hive.storedPlayerControlsStyle, s);
      expect(hive.playerControlsStyle, s);
    }
  });

  test('the offer is remembered as shown', () async {
    expect(hive.nativeControlsOffered, isFalse);
    await hive.markNativeControlsOffered();
    expect(hive.nativeControlsOffered, isTrue);
  });
}
