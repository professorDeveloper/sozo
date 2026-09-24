import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

void main() {
  test('a record written by an older build still reads', () {
    final t = FollowedTitle.fromJson({
      'contentUrl': 'u',
      'provider': 'p',
      'title': 'T',
      'thumbnail': 'https://x/y.jpg',
      'year': 2020,
      'lastEpisodeCount': 7,
      'addedAt': 5,
    });
    expect(t.mode, 'video');
    expect(t.notify, isTrue);
    expect(t.anilistId, isNull);
    expect(t.lastEpisodeCount, 7);
    expect(t.updatedAt, 0);
  });

  test('defaults stay out of the stored JSON', () {
    const t = FollowedTitle(
      contentUrl: 'u',
      provider: 'p',
      title: 't',
      thumbnail: '',
    );
    final json = t.toJson();
    for (final k in ['mode', 'notify', 'anilistId', 'tmdbId', 'updatedAt']) {
      expect(json.containsKey(k), isFalse, reason: k);
    }
  });

  test('new fields round-trip', () {
    const t = FollowedTitle(
      contentUrl: 'u',
      provider: 'cs:x',
      title: 't',
      thumbnail: '',
      mode: 'manga',
      notify: false,
      anilistId: 1,
      malId: 2,
      tmdbId: 3,
      tmdbKind: 'tv',
      nextAiringAt: 99,
      nextAiringEpisode: 4,
      lastEpisodeLabel: 'S2 E5',
    );
    final back = FollowedTitle.fromJson(t.toJson());
    expect(back.mode, 'manga');
    expect(back.notify, isFalse);
    expect(back.anilistId, 1);
    expect(back.malId, 2);
    expect(back.tmdbId, 3);
    expect(back.tmdbKind, 'tv');
    expect(back.nextAiringAt, 99);
    expect(back.nextAiringEpisode, 4);
    expect(back.lastEpisodeLabel, 'S2 E5');
  });

  test('server items read ISO dates and string numbers', () {
    final t = FollowedTitle.fromJson({
      'contentUrl': 'u',
      'provider': 'p',
      'title': 't',
      'thumbnail': null,
      'addedAt': '2026-09-01T00:00:00.000Z',
      'anilistId': '42',
      'mode': 'bogus',
    });
    expect(t.addedAt, DateTime.utc(2026, 9, 1).millisecondsSinceEpoch);
    expect(t.anilistId, 42);
    expect(t.thumbnail, '');
    expect(t.mode, 'video');
  });

  test('the wire shape leaves out what the server owns', () {
    const t = FollowedTitle(
      contentUrl: 'u',
      provider: 'p',
      title: 't',
      thumbnail: 'file:///local.jpg',
      addedAt: 1000,
      autoDownload: true,
    );
    final remote = t.toRemote();
    expect(remote.containsKey('knownCount'), isFalse);
    expect(remote.containsKey('autoDownload'), isFalse);
    expect(remote['thumbnail'], isNull);
    expect(remote['updatedAt'], '1970-01-01T00:00:01.000Z');
  });
}
