import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/player_affordances.dart';

void main() {
  const none = PlayerAffordances.none();

  test('nothing is offered before anything has resolved', () {
    expect(none.hasEpisodes, isFalse);
    expect(none.hasServers, isFalse);
    expect(none.hasQualities, isFalse);
    expect(none.hasLangs, isFalse);
    expect(none.canDownload, isFalse);
  });

  group('episodes', () {
    test('a movie never lists episodes, however many arrive', () {
      expect(none.copyWith(episodeCount: 12).hasEpisodes, isFalse);
    });

    test('a serial with an empty window has nothing to list yet', () {
      // Windowed paging can leave the list empty between pages.
      expect(none.copyWith(isSerial: true).hasEpisodes, isFalse);
    });

    test('a serial with a loaded window lists them', () {
      expect(
        none.copyWith(isSerial: true, episodeCount: 12).hasEpisodes,
        isTrue,
      );
    });
  });

  group('one of a thing is not a choice', () {
    test('a single host offers no server switch', () {
      expect(none.copyWith(serverCount: 1).hasServers, isFalse);
      expect(none.copyWith(serverCount: 2).hasServers, isTrue);
    });

    test('a single mirror offers no quality switch', () {
      expect(none.copyWith(serverSourceCount: 1).hasQualities, isFalse);
      expect(none.copyWith(serverSourceCount: 2).hasQualities, isTrue);
    });

    test('engine renditions alone are enough to offer one', () {
      // THE CASE A MIRROR COUNT WOULD HIDE. An HLS stream can carry four
      // renditions while the provider listed a single mirror; counting only
      // mirrors hid the control and made the whole feature unreachable.
      expect(
        none.copyWith(serverSourceCount: 1, engineTrackCount: 4).hasQualities,
        isTrue,
      );
    });

    test('neither source means no control, which is the honest answer', () {
      expect(
        none.copyWith(serverSourceCount: 1, engineTrackCount: 0).hasQualities,
        isFalse,
      );
    });

    test('a single audio language offers no language switch', () {
      expect(none.copyWith(langCount: 1).hasLangs, isFalse);
      expect(none.copyWith(langCount: 2).hasLangs, isTrue);
    });
  });

  group('download', () {
    const allowed = PlayerAffordances(
      isSerial: false,
      episodeCount: 0,
      serverCount: 1,
      serverSourceCount: 1,
      engineTrackCount: 0,
      langCount: 1,
      showDownloadAction: true,
      provider: 'anilist',
      hasResolvedUrl: true,
    );

    test('offered when the route allows it and a stream has resolved', () {
      expect(allowed.canDownload, isTrue);
    });

    test('withheld until the stream resolves — THE drift this file fixes', () {
      // The overlay checked this and the settings sheet did not, under a
      // comment in the overlay claiming the two gates matched. During a load
      // the sheet handed the viewer a download with no url behind it.
      expect(allowed.copyWith(hasResolvedUrl: false).canDownload, isFalse);
    });

    test('withheld when the route never allowed it', () {
      expect(allowed.copyWith(showDownloadAction: false).canDownload, isFalse);
    });

    test("withheld for uzmovi, whose urls expire", () {
      // A downloaded file from a single-use url is a file that will not play.
      expect(allowed.copyWith(provider: 'uzmovi').canDownload, isFalse);
    });

    test('other providers are unaffected by that exclusion', () {
      expect(allowed.copyWith(provider: 'uzmovi2').canDownload, isTrue);
      expect(allowed.copyWith(provider: 'cs:uzmovi').canDownload, isTrue);
    });
  });

  test('copyWith changes one field and carries the rest', () {
    const base = PlayerAffordances(
      isSerial: true,
      episodeCount: 4,
      serverCount: 3,
      serverSourceCount: 2,
      engineTrackCount: 0,
      langCount: 2,
      showDownloadAction: true,
      provider: 'anilist',
      hasResolvedUrl: true,
    );
    final next = base.copyWith(episodeCount: 0);
    expect(next.hasEpisodes, isFalse);
    expect(next.hasServers, isTrue);
    expect(next.hasQualities, isTrue);
    expect(next.hasLangs, isTrue);
    expect(next.canDownload, isTrue);
  });
}
