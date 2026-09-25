import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/profile_storage.dart';
import 'package:soplay/features/onboarding/data/genre_catalog.dart';
import 'package:soplay/features/onboarding/data/taste_sources.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';

void main() {
  late Directory dir;
  late HiveService hive;

  const action = TasteGenre(
    slug: 'action',
    label: 'Action',
    catalogues: {'anilist', 'tmdb'},
  );
  const romance = TasteGenre(
    slug: 'romance',
    label: 'Romance',
    catalogues: {'anilist-manga'},
  );
  const mine = TasteProfile(
    kinds: [TasteKind.anime, TasteKind.manga],
    genres: [action, romance],
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_taste_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.authBox);
    await Hive.openBox(AppConstants.settingsBox);
    ProfileScope.reset();
    hive = HiveService();
  });

  tearDown(() async {
    ProfileScope.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('per profile', () {
    test('nothing is stored until something is picked', () {
      expect(hive.getTasteProfile().isEmpty, isTrue);
    });

    test('each profile keeps its own taste', () async {
      await hive.saveTasteProfile(mine);

      ProfileScope.set(namespace: 'kid1', remoteId: 'kid1');
      expect(hive.getTasteProfile().isEmpty, isTrue);
      await hive.saveTasteProfile(
        const TasteProfile(kinds: [TasteKind.novels]),
      );
      expect(hive.getTasteProfile().kinds, [TasteKind.novels]);

      ProfileScope.reset();
      final back = hive.getTasteProfile();
      expect(back.kinds, [TasteKind.anime, TasteKind.manga]);
      expect(back.genres.map((g) => g.slug), ['action', 'romance']);
      expect(back.genres.first.catalogues, {'anilist', 'tmdb'});
      expect(hive.getTasteProfileFor('kid1').kinds, [TasteKind.novels]);
    });

    test('another profile can be written without switching to it', () async {
      await hive.saveTasteProfileFor(
        'kid2',
        const TasteProfile(kinds: [TasteKind.movies]),
      );
      expect(hive.getTasteProfile().isEmpty, isTrue);
      ProfileScope.set(namespace: 'kid2', remoteId: 'kid2');
      expect(hive.getTasteProfile().kinds, [TasteKind.movies]);
    });

    test('deleting a profile deletes its taste', () async {
      await hive.saveTasteProfileFor('kid3', mine);
      await ProfileStorage.delete('kid3', Hive.box(AppConstants.settingsBox));
      expect(hive.getTasteProfileFor('kid3').isEmpty, isTrue);
    });

    test('a write is announced', () async {
      final before = hive.tasteChanged.value;
      await hive.saveTasteProfile(mine);
      expect(hive.tasteChanged.value, before + 1);
    });

    test('the key is one of the per-profile keys', () {
      expect(
        ProfileScope.profileKeys.contains(AppConstants.tasteProfileKey),
        isTrue,
      );
    });
  });

  group('taste profile', () {
    test('survives a round trip, dropping kinds it does not know', () {
      final json = mine.toJson();
      (json['kinds'] as List).add('podcasts');
      final back = TasteProfile.fromJson(json);
      expect(back.kinds, mine.kinds);
      expect(back.genres, mine.genres);
    });

    test('browses each genre only where the picked kinds list it', () {
      final video = mine.browseTargets(ContentMode.video);
      expect(video.map((t) => '${t.catalogue}:${t.genre.slug}'), [
        'anilist:action',
      ]);
      final manga = mine.browseTargets(ContentMode.manga);
      expect(manga.map((t) => '${t.catalogue}:${t.genre.slug}'), [
        'anilist-manga:romance',
      ]);
      expect(mine.browseTargets(ContentMode.novel), isEmpty);
    });

    test('genres from several catalogues merge by slug', () {
      final merged = mergeGenres([
        ...GenreCatalog.fallbackFor('anilist'),
        ...GenreCatalog.fallbackFor('tmdb'),
      ]);
      final slugs = merged.map((g) => g.slug).toList();
      expect(slugs.toSet().length, slugs.length);
      final scifi = merged.firstWhere((g) => g.slug == 'sci-fi');
      expect(scifi.catalogues, {'anilist', 'tmdb'});
      expect(merged.firstWhere((g) => g.slug == 'war').catalogues, {'tmdb'});
    });
  });

  group('starting sources', () {
    test('a reading mode with no reader lands on its catalogue', () {
      final plan = planTasteSources(
        modes: const [ContentMode.manga, ContentMode.video],
        remembered: (_) => null,
        currentId: 'vidapi',
        usable: const [],
        favorites: const {},
      );
      expect(plan.remember[ContentMode.manga], 'cat:anilist-manga');
      expect(plan.select, 'cat:anilist-manga');
    });

    test('a remembered source is kept', () {
      final plan = planTasteSources(
        modes: const [ContentMode.novel],
        remembered: (m) => m == ContentMode.novel ? 'my:somenovels' : null,
        currentId: 'vidapi',
        usable: const [],
        favorites: const {},
      );
      expect(plan.remember, isEmpty);
      expect(plan.select, 'my:somenovels');
    });

    test('staying in the current mode changes nothing current', () {
      final plan = planTasteSources(
        modes: const [ContentMode.video, ContentMode.novel],
        remembered: (_) => null,
        currentId: 'vidapi',
        usable: null,
        favorites: const {},
      );
      expect(plan.select, isNull);
      expect(plan.remember.containsKey(ContentMode.video), isFalse);
      expect(plan.remember[ContentMode.novel], 'cat:anilist-novel');
    });
  });
}
