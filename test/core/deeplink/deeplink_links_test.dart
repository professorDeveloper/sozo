import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/deeplink/deeplink_links.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

DetailArgs _detail(String link) {
  final target = parseDeeplink(Uri.parse(link));
  expect(target, isNotNull, reason: link);
  expect(target!.location, '/detail');
  return target.extra! as DetailArgs;
}

void main() {
  group('parseDeeplink', () {
    test('/detail opens the title with its provider, nothing more', () {
      final args = _detail(
        'https://sozo.azamov.me/detail?url=https%3A%2F%2Fx.test%2Fa&provider=hd',
      );
      expect(args.contentUrl, 'https://x.test/a');
      expect(args.provider, 'hd');
      expect(args.autoPlay, isFalse);
      expect(args.startEpisode, isNull);
      expect(args.startPositionMs, isNull);
    });

    test('/play keeps episode and position', () {
      final args = _detail(
        'https://sozo.azamov.me/play?url=u&provider=hd&ep=12&t=754',
      );
      expect(args.autoPlay, isTrue);
      expect(args.provider, 'hd');
      expect(args.startEpisode, 12);
      expect(args.startPositionMs, 754000);
      // The viewer's own history is not what a shared link resumes.
      expect(args.resumeEpisodeIndex, isNull);
    });

    test('custom scheme reads the route from the authority', () {
      final args = _detail('sozo://play?url=u&ep=2&t=1:05');
      expect(args.startEpisode, 2);
      expect(args.startPositionMs, 65000);
    });

    test('/player is an alias of /play', () {
      expect(_detail('sozo://player?url=u').autoPlay, isTrue);
    });

    test('bad ep and t are dropped, not guessed', () {
      final args = _detail('sozo://play?url=u&ep=zero&t=-4');
      expect(args.startEpisode, isNull);
      expect(args.startPositionMs, isNull);
      expect(_detail('sozo://play?url=u&ep=0').startEpisode, isNull);
    });

    test('an empty provider means none', () {
      expect(_detail('sozo://detail?url=u&provider=%20').provider, isNull);
    });

    test('/party/<code> opens the room with typed args', () {
      final target = parseDeeplink(
        Uri.parse('https://sozo.azamov.me/party/ABC123'),
      )!;
      expect(target.location, '/watch-party');
      expect((target.extra! as WatchPartyArgs).code, 'ABC123');
    });

    test('/link and /pair open link-tv', () {
      expect(
        parseDeeplink(Uri.parse('sozo://link/XY12'))!.location,
        '/link-tv?code=XY12',
      );
      expect(parseDeeplink(Uri.parse('sozo://pair'))!.location, '/link-tv');
    });

    test('ignores other hosts, missing urls and unknown paths', () {
      expect(
        parseDeeplink(Uri.parse('https://evil.test/detail?url=u')),
        isNull,
      );
      expect(parseDeeplink(Uri.parse('sozo://detail')), isNull);
      expect(parseDeeplink(Uri.parse('sozo://play')), isNull);
      expect(parseDeeplink(Uri.parse('sozo://party')), isNull);
      expect(parseDeeplink(Uri.parse('sozo://nowhere?url=u')), isNull);
    });
  });

  group('parseStartSeconds', () {
    test('reads plain, clock and unit forms', () {
      expect(parseStartSeconds('90'), 90);
      expect(parseStartSeconds('12.5'), 12.5);
      expect(parseStartSeconds('1:30'), 90);
      expect(parseStartSeconds('1:00:05'), 3605);
      expect(parseStartSeconds('1h2m5s'), 3725);
      expect(parseStartSeconds('2m'), 120);
      expect(parseStartSeconds('45s'), 45);
    });

    test('rejects nonsense', () {
      for (final bad in [null, '', '0', '-3', 'abc', '1:x', 'h', '1:2:3:4']) {
        expect(parseStartSeconds(bad), isNull, reason: '$bad');
      }
    });
  });

  group('buildShareLink', () {
    test('a title alone shares /detail', () {
      final link = Uri.parse(buildShareLink(contentUrl: 'u', provider: 'hd'));
      expect(link.path, '/detail');
      expect(link.queryParameters, {'url': 'u', 'provider': 'hd'});
    });

    test('an episode and a position share /play, which parses back', () {
      final link = buildShareLink(
        contentUrl: 'u',
        provider: 'hd',
        episode: 4,
        position: const Duration(minutes: 3, seconds: 7),
      );
      expect(Uri.parse(link).path, '/play');
      final args = _detail(link);
      expect(args.startEpisode, 4);
      expect(args.startPositionMs, 187000);
      expect(args.provider, 'hd');
    });
  });
}
