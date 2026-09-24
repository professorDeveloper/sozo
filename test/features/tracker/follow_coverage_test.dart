// Who announces a new episode. The server does it for what it can reach; the
// phone must stay quiet on those when signed in, or the user hears twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/tracker/domain/follow_coverage.dart';

FollowedTitle _t(
  String provider, {
  String url = 'https://site/x',
  String mode = 'video',
  int? anilistId,
  int? tmdbId,
  String? tmdbKind,
  bool notify = true,
}) => FollowedTitle(
  contentUrl: url,
  provider: provider,
  title: 't',
  thumbnail: '',
  mode: mode,
  anilistId: anilistId,
  tmdbId: tmdbId,
  tmdbKind: tmdbKind,
  notify: notify,
);

void main() {
  group('serverCovers', () {
    test('backend providers are the server\'s', () {
      expect(FollowCoverage.serverCovers(_t('animego')), isTrue);
    });

    test('extension hosts and Jellyfin are not', () {
      for (final p in ['cs:a', 'an:b', 'mn:c', 'my:d', 'jf:e']) {
        expect(FollowCoverage.serverCovers(_t(p)), isFalse, reason: p);
      }
    });

    test('an extension title stays the device\'s even with an AniList id', () {
      expect(FollowCoverage.serverCovers(_t('cs:a', anilistId: 5)), isFalse);
    });

    test('AniList anime and TMDB shows are covered, films and books are not', () {
      expect(
        FollowCoverage.serverCovers(
          _t('cat:anilist', url: 'https://anilist.co/anime/1'),
        ),
        isTrue,
      );
      expect(
        FollowCoverage.serverCovers(
          _t('cat:tmdb', url: 'https://www.themoviedb.org/tv/1', tmdbKind: 'tv'),
        ),
        isTrue,
      );
      expect(
        FollowCoverage.serverCovers(
          _t('cat:tmdb', url: 'https://www.themoviedb.org/movie/1', tmdbKind: 'movie'),
        ),
        isFalse,
      );
      expect(
        FollowCoverage.serverCovers(
          _t('cat:anilist-manga', url: 'https://anilist.co/manga/1', mode: 'manga'),
        ),
        isFalse,
      );
    });
  });

  group('deviceNotifies', () {
    test('a guest hears about everything from the device', () {
      expect(
        FollowCoverage.deviceNotifies(_t('animego'), signedIn: false, serverLive: true),
        isTrue,
      );
    });

    test('signed in, a server-covered title is left to the server', () {
      expect(
        FollowCoverage.deviceNotifies(_t('animego'), signedIn: true, serverLive: true),
        isFalse,
      );
      expect(
        FollowCoverage.deviceNotifies(_t('cs:a'), signedIn: true, serverLive: true),
        isTrue,
      );
    });

    test('until the server has answered once, the device keeps announcing', () {
      expect(
        FollowCoverage.deviceNotifies(_t('animego'), signedIn: true, serverLive: false),
        isTrue,
      );
    });

    test('a follow still in the upload queue is unknown to the server', () {
      expect(
        FollowCoverage.deviceNotifies(
          _t('animego'),
          signedIn: true,
          serverLive: true,
          pendingUpload: true,
        ),
        isTrue,
      );
    });

    test('a muted title is announced by nobody', () {
      expect(
        FollowCoverage.deviceNotifies(
          _t('cs:a', notify: false),
          signedIn: false,
          serverLive: false,
        ),
        isFalse,
      );
    });
  });

  group('deviceChecks (background)', () {
    test('catalogue pages are never checked on the device', () {
      expect(
        FollowCoverage.deviceChecks(
          _t('cat:anilist-manga', mode: 'manga'),
          signedIn: false,
          serverLive: false,
        ),
        isFalse,
      );
    });

    test('signed in, only what the server cannot reach', () {
      expect(
        FollowCoverage.deviceChecks(_t('animego'), signedIn: true, serverLive: true),
        isFalse,
      );
      expect(
        FollowCoverage.deviceChecks(_t('mn:x'), signedIn: true, serverLive: true),
        isTrue,
      );
    });
  });
}
