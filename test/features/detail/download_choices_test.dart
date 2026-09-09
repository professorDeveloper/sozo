import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

VideoSourceEntity src(
  String quality, {
  String? url,
  String? type,
  String? mirror,
  String? codec,
  String? hdr,
  bool atmos = false,
  int? sizeBytes,
  bool accessible = true,
}) =>
    VideoSourceEntity(
      quality: quality,
      videoUrl: url ?? 'https://cdn.test/${quality.replaceAll(' ', '')}',
      isDefault: false,
      accessible: accessible,
      type: type,
      mirror: mirror,
      codec: codec,
      hdr: hdr,
      atmos: atmos,
      sizeBytes: sizeBytes,
    );

void main() {
  group('what is offered', () {
    test('the playing stream leads and is marked', () {
      final sources = [src('Voe · 720p'), src('DoodStream · 1080p')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 1,
        currentUrl: sources[1].videoUrl,
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.first.isCurrent, isTrue);
      expect(offers.first.url, sources[1].videoUrl);
      expect(offers.where((o) => o.isCurrent).length, 1);
    });

    test('every other direct source is offered too — the whole point', () {
      // Watching 480p to save data used to mean you could only download 480p.
      final sources = [src('Voe · 480p'), src('Voe · 720p'), src('Voe · 1080p')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: sources[0].videoUrl,
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.length, 3);
      expect(offers.map((o) => o.url).toSet(),
          sources.map((s) => s.videoUrl).toSet());
    });

    test('under a directive the other mirrors are offered, but flagged', () {
      // They are embed PAGES. Refusing them meant the sheet had one row and
      // never opened on the fourteen providers that carry a directive, so you
      // could only keep the quality you happened to be watching. They are
      // offered and marked instead; the caller sniffs the picked one.
      final sources = [src('Voe · 720p'), src('Voe · 1080p')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: 'https://cdn.test/sniffed.m3u8',
        currentHeaders: const {},
        hasDirective: true,
      );
      expect(offers.length, 2);
      expect(offers.first.isCurrent, isTrue);
      expect(offers.first.needsSniff, isFalse,
          reason: 'the playing stream is already resolved');
      expect(offers.last.needsSniff, isTrue);
      expect(offers.last.url, sources[1].videoUrl);
    });

    test('without a directive nothing needs sniffing', () {
      final sources = [src('Voe · 720p'), src('Voe · 1080p')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: sources[0].videoUrl,
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.every((o) => !o.needsSniff), isTrue);
    });

    test('an iframe mirror becomes offerable once a sniff is coming', () {
      // isPlayable(hasDirective: true) admits it, which is the same rule the
      // playback ladder uses.
      final sources = [src('Voe · 720p'), src('Voe · embed', type: 'iframe')];
      final withSniff = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: 'https://cdn.test/sniffed.m3u8',
        currentHeaders: const {},
        hasDirective: true,
      );
      expect(withSniff.length, 2);
      expect(withSniff.last.needsSniff, isTrue);
    });

    test('an iframe entry is a page, so it is never an offer', () {
      final sources = [src('Voe · 720p'), src('Voe · embed', type: 'iframe')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: sources[0].videoUrl,
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.length, 1);
    });

    test('an unreachable mirror is not offered', () {
      final sources = [
        src('Voe · 720p'),
        src('Voe · 1080p', accessible: false),
      ];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: sources[0].videoUrl,
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.length, 1);
    });

    test('a url appearing twice is offered once', () {
      // The resolved current url is often identical to its own source entry.
      final sources = [src('Voe · 720p', url: 'https://cdn.test/a')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: 'https://cdn.test/a',
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.length, 1);
    });

    test('nothing playing and nothing direct yields no offers', () {
      expect(
        DownloadChoices.from(
          sources: const [],
          currentIndex: -1,
          currentUrl: null,
          currentHeaders: const {},
          hasDirective: false,
        ),
        isEmpty,
      );
    });

    test('a current index out of range does not throw', () {
      final sources = [src('Voe · 720p')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 9,
        currentUrl: 'https://cdn.test/resolved',
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.length, 2);
    });
  });

  group('how an offer reads', () {
    test('the mirror names it when the source gave one', () {
      final offers = DownloadChoices.from(
        sources: [src('Voe · 1080p', mirror: 'DoodStream')],
        currentIndex: 0,
        currentUrl: 'https://cdn.test/a',
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.single.label, 'DoodStream');
    });

    test('otherwise the server half of the label names it', () {
      final offers = DownloadChoices.from(
        sources: [src('Voe · 1080p')],
        currentIndex: 0,
        currentUrl: 'https://cdn.test/a',
        currentHeaders: const {},
        hasDirective: false,
      );
      expect(offers.single.label, 'Voe');
      expect(offers.single.detail, contains('1080p'));
    });

    test('HLS and direct are distinguished — they download differently', () {
      final hls = DownloadChoices.from(
        sources: [src('Voe · 720p', type: 'hls')],
        currentIndex: 0,
        currentUrl: 'https://cdn.test/a',
        currentHeaders: const {},
        hasDirective: false,
      ).single;
      final direct = DownloadChoices.from(
        sources: [src('Voe · 720p', type: 'mp4')],
        currentIndex: 0,
        currentUrl: 'https://cdn.test/b',
        currentHeaders: const {},
        hasDirective: false,
      ).single;
      expect(hls.detail, contains('HLS'));
      expect(direct.detail, contains('Direct'));
    });

    test('the risky properties are stated before you commit to a file', () {
      final offer = DownloadChoices.from(
        sources: [
          src('Voe · 2160p',
              codec: 'h265', hdr: 'dv', atmos: true, sizeBytes: 17179869184),
        ],
        currentIndex: 0,
        currentUrl: 'https://cdn.test/a',
        currentHeaders: const {},
        hasDirective: false,
      ).single;
      expect(offer.detail, contains('h265'));
      expect(offer.detail, contains('Dolby Vision'));
      expect(offer.detail, contains('Atmos'));
      expect(offer.detail, contains('16 GB'));
    });
  });

  group('headers travel with the offer', () {
    test("a sibling mirror gets its OWN headers, not the playing one's", () {
      // Mirrors gate on their own Referer. Sending the current stream's
      // headers to another host is how a picked download comes back 403.
      const mine = {'Referer': 'https://voe.test/'};
      final sources = [
        src('Voe · 720p'),
        VideoSourceEntity(
          quality: 'Dood · 1080p',
          videoUrl: 'https://cdn.test/dood',
          isDefault: false,
          accessible: true,
          headers: {'Referer': 'https://dood.test/'},
        ),
      ];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: sources[0].videoUrl,
        currentHeaders: mine,
        hasDirective: false,
      );
      expect(offers.first.headers, mine);
      expect(offers.last.headers, {'Referer': 'https://dood.test/'});
    });

    test('the playing offer carries the RESOLVED headers', () {
      // Post-sniff headers are the ones the CDN actually gated on, so they
      // must win over whatever the source entry declared.
      const resolved = {'Referer': 'https://sniffed.test/', 'Cookie': 'a=1'};
      final sources = [src('Voe · 720p')];
      final offers = DownloadChoices.from(
        sources: sources,
        currentIndex: 0,
        currentUrl: 'https://cdn.test/sniffed.m3u8',
        currentHeaders: resolved,
        hasDirective: true,
      );
      expect(offers.single.headers, resolved);
    });
  });

  group('isDownloadableUrl', () {
    test('a plain resolved url is downloadable', () {
      expect(
        DownloadChoices.isDownloadableUrl(
            url: 'https://cdn.test/a.mp4', type: 'mp4', hasDirective: false),
        isTrue,
      );
    });

    test('an iframe url is an embed page, not a file', () {
      expect(
        DownloadChoices.isDownloadableUrl(
            url: 'https://host.test/embed/abc',
            type: 'iframe',
            hasDirective: true),
        isFalse,
      );
    });

    test('an hls manifest is downloadable even with a fallback directive', () {
      // THE REGRESSION THIS PINS. videasy and rareanimes attach an extractor
      // block as a fallback while still returning a real manifest. Refusing on
      // the directive alone stopped downloads that had always worked.
      expect(
        DownloadChoices.isDownloadableUrl(
            url: 'https://cdn.test/master.m3u8',
            type: 'hls',
            hasDirective: true),
        isTrue,
      );
    });

    test('an unknown kind plus an expected sniff is refused', () {
      // Nothing else to go on, so the directive decides.
      expect(
        DownloadChoices.isDownloadableUrl(
            url: 'https://host.test/watch/1', type: null, hasDirective: true),
        isFalse,
      );
      expect(
        DownloadChoices.isDownloadableUrl(
            url: 'https://cdn.test/a.mp4', type: null, hasDirective: false),
        isTrue,
      );
    });

    test('an empty url is never downloadable', () {
      expect(
        DownloadChoices.isDownloadableUrl(
            url: '', type: 'hls', hasDirective: false),
        isFalse,
      );
    });
  });

  group('formatSize', () {
    test('scales and rounds readably', () {
      expect(DownloadChoices.formatSize(900), '900 B');
      expect(DownloadChoices.formatSize(1024), '1.0 KB');
      expect(DownloadChoices.formatSize(1536 * 1024), '1.5 MB');
      expect(DownloadChoices.formatSize(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('an unstated or nonsense size is simply absent', () {
      expect(DownloadChoices.formatSize(null), isNull);
      expect(DownloadChoices.formatSize(0), isNull);
      expect(DownloadChoices.formatSize(-1), isNull);
    });
  });
}
