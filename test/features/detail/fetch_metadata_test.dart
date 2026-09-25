// A player that never sends fetch metadata gets refused where a browser is let
// through.
//
// The report was "AnimeAV1 will not play": the master playlist returned 200 and
// every segment returned a Cloudflare 403 — the same block whatever
// User-Agent, Referer or cookie jar was sent. Measured against the live CDN,
// the single header that cleared it was `Sec-Fetch-Site`. The rule is looking
// for fetch metadata, which every real browser attaches to every subresource
// request and no bare HTTP client sends at all, so the player was refused on a
// request the same device's browser is allowed to make.
//
// The value has to be computed rather than pinned. `same-origin` is a claim
// about the relationship between the page and the request, and a CDN on another
// host is genuinely cross-site — stating otherwise is the same kind of lie a
// hard-coded User-Agent is.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/fetch_metadata.dart';

void main() {
  group('Sec-Fetch-Site says where the request came from', () {
    test('the page and the file on one host is same-origin', () {
      // The AnimeAV1 case: referer https://player.zilla-networks.com/ and a
      // segment under the same host. This is the value that unblocked it.
      expect(
        fetchSite(
          'https://player.zilla-networks.com/',
          Uri.parse('https://player.zilla-networks.com/segs/x/init.html'),
        ),
        'same-origin',
      );
    });

    test('a sibling host on the same domain is same-site', () {
      expect(
        fetchSite(
          'https://www.example.com/watch',
          Uri.parse('https://cdn.example.com/seg.ts'),
        ),
        'same-site',
      );
    });

    test('a different domain is cross-site', () {
      expect(
        fetchSite(
          'https://player.example.com/',
          Uri.parse('https://cdn.othercdn.net/seg.ts'),
        ),
        'cross-site',
      );
    });

    test('no referer at all is none', () {
      expect(fetchSite(null, Uri.parse('https://cdn.test/seg.ts')), 'none');
      expect(fetchSite('', Uri.parse('https://cdn.test/seg.ts')), 'none');
    });

    test('a scheme change is not the same origin', () {
      // http -> https is a different origin even on one host, which is exactly
      // what the header exists to report.
      expect(
        fetchSite(
          'http://example.com/',
          Uri.parse('https://example.com/seg.ts'),
        ),
        'same-site',
      );
    });

    test('a malformed referer does not throw', () {
      expect(
        fetchSite('not a url', Uri.parse('https://cdn.test/seg.ts')),
        'none',
      );
    });
  });

  group('the trio is attached to stream headers', () {
    test('all three, describing a script-driven media fetch', () {
      final h = <String, String>{
        'Referer': 'https://player.zilla-networks.com/',
      };
      addFetchMetadata(h, Uri.parse('https://player.zilla-networks.com/s/x'));

      expect(h['Sec-Fetch-Dest'], 'empty');
      expect(h['Sec-Fetch-Mode'], 'cors');
      expect(h['Sec-Fetch-Site'], 'same-origin');
    });

    test('a source that sets its own is left alone', () {
      // A provider that has worked out what its CDN wants knows better than a
      // default, and half-overwriting the set is its own fingerprint.
      final h = <String, String>{
        'Referer': 'https://example.com/',
        'Sec-Fetch-Site': 'cross-site',
      };
      addFetchMetadata(h, Uri.parse('https://example.com/seg.ts'));

      expect(h['Sec-Fetch-Site'], 'cross-site');
      expect(h.containsKey('Sec-Fetch-Dest'), isFalse);
    });

    test('and a header set with no referer still gets the trio', () {
      final h = <String, String>{};
      addFetchMetadata(h, Uri.parse('https://cdn.test/seg.ts'));

      expect(h['Sec-Fetch-Site'], 'none');
      expect(h['Sec-Fetch-Dest'], 'empty');
    });
  });
}
