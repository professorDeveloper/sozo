import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/detail/data/title_prefs_store.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_titleprefs_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async => TitlePrefsStore().clear());

  test('a title nobody has watched remembers nothing', () {
    final s = TitlePrefsStore();
    expect(s.langFor('hianimes', 'https://x/naruto'), isNull);
    expect(s.qualityFor('hianimes', 'https://x/naruto'), isNull);
  });

  test('two shows keep separate choices', () async {
    // The whole point. One global setting meant watching one show dubbed
    // silently re-pointed the other, and whichever was touched last won.
    final s = TitlePrefsStore();
    await s.rememberLang('hianimes', 'https://x/naruto', 'dub');
    await s.rememberLang('hianimes', 'https://x/frieren', 'sub');

    expect(s.langFor('hianimes', 'https://x/naruto'), 'dub');
    expect(s.langFor('hianimes', 'https://x/frieren'), 'sub');
  });

  test('the same show on two sources is two titles', () async {
    // Different sources carry different servers and different language tags,
    // so a choice made on one says nothing about the other.
    final s = TitlePrefsStore();
    await s.rememberQuality('hianimes', 'https://x/naruto', '1080p');
    expect(s.qualityFor('anikai', 'https://x/naruto'), isNull);
  });

  test('language and quality live side by side', () async {
    final s = TitlePrefsStore();
    await s.rememberLang('p', 'u', 'dub');
    await s.rememberQuality('p', 'u', 'Server 3');
    expect(s.langFor('p', 'u'), 'dub');
    expect(s.qualityFor('p', 'u'), 'Server 3',
        reason: 'writing one field must not wipe the other');
  });

  test('a later choice replaces the earlier one', () async {
    final s = TitlePrefsStore();
    await s.rememberLang('p', 'u', 'sub');
    await s.rememberLang('p', 'u', 'dub');
    expect(s.langFor('p', 'u'), 'dub');
  });

  test('an empty url or value is not stored', () async {
    // A title with no url is something opened by direct link; keying on the
    // empty string would make every one of them the same title.
    final s = TitlePrefsStore();
    await s.rememberLang('p', '', 'dub');
    expect(s.langFor('p', ''), isNull);
    await s.rememberLang('p', 'u', '');
    expect(s.langFor('p', 'u'), isNull);
  });

  test('the store is bounded, dropping the least recently touched', () async {
    // One entry per title watched grows without limit in a box read at
    // startup. Over-filling it deliberately here so the eviction is exercised
    // rather than assumed.
    final s = TitlePrefsStore();
    for (var i = 0; i < TitlePrefsStore.maxEntries + 20; i++) {
      await s.rememberLang('p', 'url$i', 'sub');
    }
    // The oldest are gone; the newest are all still there.
    expect(s.langFor('p', 'url0'), isNull);
    expect(s.langFor('p', 'url${TitlePrefsStore.maxEntries + 19}'), 'sub');
  });

  test('touching an old title keeps it alive', () async {
    // Recency, not insertion order: the title somebody is part-way through
    // must survive a spree of browsing.
    final s = TitlePrefsStore();
    await s.rememberLang('p', 'keeper', 'dub');
    for (var i = 0; i < TitlePrefsStore.maxEntries - 5; i++) {
      await s.rememberLang('p', 'filler$i', 'sub');
    }
    await s.rememberLang('p', 'keeper', 'dub'); // touched again
    for (var i = 0; i < 40; i++) {
      await s.rememberLang('p', 'more$i', 'sub');
    }
    expect(s.langFor('p', 'keeper'), 'dub');
  });

  test('a corrupt store reads as empty instead of throwing', () async {
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.titlePrefsKey, 'not a map');
    expect(TitlePrefsStore().langFor('p', 'u'), isNull);
  });
}
