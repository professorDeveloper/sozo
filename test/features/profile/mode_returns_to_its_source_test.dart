import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart';

ProviderEntity source(String id) => ProviderEntity(
  id: id,
  name: id,
  image: '',
  url: '',
  description: '',
  domains: const [],
);

void main() {
  group('pickSourceForMode', () {
    final watch = [source('vidapi'), source('cs:hdrezka'), source('an:gogo')];

    test('coming back to a mode lands on the source last used there', () {
      final pick = pickSourceForMode(
        mode: ContentMode.video,
        remembered: 'cs:hdrezka',
        currentId: 'mn:mangadex',
        candidates: watch,
        favorites: {'vidapi'},
      );
      expect(pick.id, 'cs:hdrezka');
      expect(pick.remember, isTrue);
    });

    test('a remembered catalogue of the same mode comes back too', () {
      final pick = pickSourceForMode(
        mode: ContentMode.video,
        remembered: 'cat:tmdb',
        currentId: 'mn:mangadex',
        candidates: watch,
        favorites: const {},
      );
      expect(pick.id, 'cat:tmdb');
    });

    test('a remembered source not enumerated yet is stood in for, '
        'and the memory is kept', () {
      final pick = pickSourceForMode(
        mode: ContentMode.video,
        remembered: 'cs:not-loaded-yet',
        currentId: 'mn:mangadex',
        candidates: watch,
        favorites: {'an:gogo'},
      );
      expect(pick.id, 'an:gogo');
      expect(pick.remember, isFalse);
    });

    test('with nothing remembered the old rules still apply', () {
      expect(
        pickSourceForMode(
          mode: ContentMode.video,
          remembered: '',
          currentId: 'mn:mangadex',
          candidates: watch,
          favorites: {'an:gogo'},
        ),
        (id: 'an:gogo', remember: true),
      );
      expect(
        pickSourceForMode(
          mode: ContentMode.manga,
          remembered: '',
          currentId: 'vidapi',
          candidates: const [],
          favorites: const {},
        ).id,
        'cat:anilist-manga',
      );
    });

    test('a catalogue from another mode is not a memory for this one', () {
      final pick = pickSourceForMode(
        mode: ContentMode.video,
        remembered: 'cat:anilist-manga',
        currentId: 'vidapi',
        candidates: watch,
        favorites: const {},
      );
      expect(pick.id, 'vidapi');
    });
  });

  group('HiveService per-mode memory', () {
    late Directory dir;
    late HiveService hive;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('sozo_mode_memory_');
      Hive.init(dir.path);
      await Hive.openBox(AppConstants.authBox);
      await Hive.openBox(AppConstants.settingsBox);
      hive = HiveService();
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('each mode keeps its own source', () async {
      await hive.rememberProviderForMode('video', 'cs:hdrezka');
      await hive.rememberProviderForMode('manga', 'mn:mangadex');
      await hive.rememberProviderForMode('video', 'an:gogo');
      expect(hive.providerForMode('video'), 'an:gogo');
      expect(hive.providerForMode('manga'), 'mn:mangadex');
      expect(hive.providerForMode('novel'), isNull);
    });
  });
}
