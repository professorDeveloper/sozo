import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';

import 'jellyfin_fakes.dart';

String label(String key) => key;

Map<String, dynamic> movie(String id, {List<String>? backdrops}) => {
  'Id': id,
  'Name': 'Movie $id',
  'Type': 'Movie',
  'ProductionYear': 2013,
  'CommunityRating': 7.6,
  'ImageTags': {'Primary': 'p-$id'},
  'BackdropImageTags': backdrops ?? ['b-$id'],
};

Map<String, dynamic> episode(
  String id, {
  int? season,
  int? number,
  String location = 'FileSystem',
}) => {
  'Id': id,
  'Name': 'Ep $id',
  'Type': 'Episode',
  'SeriesId': 'series1',
  'SeriesName': 'Pioneer One',
  'SeriesPrimaryImageTag': 'sp',
  'ParentIndexNumber': ?season,
  'IndexNumber': ?number,
  'LocationType': location,
  'RunTimeTicks': 18963580000,
  'PremiereDate': '2010-06-16T00:00:00.0000000Z',
  'ImageTags': {'Primary': 'e-$id'},
};

void main() {
  group('cards', () {
    test('a movie maps to a playable card with poster and backdrop', () {
      final c = JellyfinBridge.card(testServer, movie('m1'));
      expect(c['provider'], 'jf:srv1');
      expect(c['contentUrl'], 'm1');
      expect(c['title'], 'Movie m1');
      expect(c['year'], 2013);
      expect(c['rating'], 8);
      expect(
        c['thumbnail'],
        'http://nas:8096/Items/m1/Images/Primary?maxWidth=400&quality=90&tag=p-m1',
      );
      expect(c['banner'], contains('/Items/m1/Images/Backdrop/0?'));
    });

    test('an episode card opens its series', () {
      final c = JellyfinBridge.card(
        testServer,
        episode('e1', season: 1, number: 2),
      );
      expect(c['contentUrl'], 'series1');
      expect(c['title'], 'Pioneer One');
      expect(c['description'], 'S1 E2 · Ep e1');
      expect(c['thumbnail'], contains('/Items/series1/Images/Primary'));
    });
  });

  test('home has resume, next up and one row per library', () {
    final map = JellyfinBridge.buildHome(
      testServer,
      libraries: [
        {'Id': 'lib1', 'Name': 'Movies', 'CollectionType': 'movies'},
        {'Id': 'lib2', 'Name': 'Shows', 'CollectionType': 'tvshows'},
      ],
      resume: [
        episode('e1', season: 1, number: 1),
        episode('e2', season: 1, number: 2),
      ],
      nextUp: const [],
      latest: [
        [movie('m1'), movie('m2')],
        const [],
      ],
      label: label,
    );
    final home = HomeDataModel.fromJson(map);
    expect(home.sections.map((s) => s.label), [
      'jellyfin.continue_watching',
      'Movies',
    ]);
    // Two episodes of one show are one card.
    expect(home.sections.first.items, hasLength(1));
    expect(home.sections.first.viewAll.slug, 'resume');
    expect(home.sections.last.viewAll.slug, 'lib:lib1');
    expect(home.sections.last.viewAll.type, 'jf');
    expect(home.banner.map((m) => m.url), ['m1', 'm2']);
    expect(map.containsKey('error'), isFalse);
  });

  test('an empty server says so instead of rendering nothing', () {
    final map = JellyfinBridge.buildHome(
      testServer,
      libraries: const [],
      resume: const [],
      nextUp: const [],
      latest: const [],
      label: label,
    );
    expect(map['error'], 'jellyfin.empty_server');
  });

  group('detail', () {
    test('a series flattens seasons in order, specials last', () {
      final map = JellyfinBridge.buildDetail(
        testServer,
        {
          'Id': 'series1',
          'Name': 'Pioneer One',
          'Type': 'Series',
          'Overview': 'A capsule falls.',
          'Genres': ['Drama'],
          'ProductionYear': 2010,
          'People': [
            {'Id': 'p1', 'Name': 'Jane', 'Type': 'Director'},
            {
              'Id': 'p2',
              'Name': 'Joe',
              'Type': 'Actor',
              'PrimaryImageTag': 't',
            },
          ],
          'ImageTags': {'Primary': 'x'},
        },
        episodes: [
          episode('s2e1', season: 2, number: 1),
          episode('sp1', season: 0, number: 1),
          episode('s1e2', season: 1, number: 2),
          episode('missing', season: 1, number: 3, location: 'Virtual'),
          episode('s1e1', season: 1, number: 1),
        ],
      );
      final detail = DetailModel.fromJson(map);
      expect(detail.isSerial, isTrue);
      expect(detail.director, 'Jane');
      expect(detail.cast.single.name, 'Joe');
      expect(detail.cast.single.image, contains('/Items/p2/Images/Primary'));

      final playback = PlaybackModel.fromJson(map);
      expect(playback.episodes.map((e) => e.mediaRef), [
        's1e1',
        's1e2',
        's2e1',
        'sp1',
      ]);
      expect(playback.episodes.map((e) => e.episode), [1, 2, 3, 4]);
      expect(playback.episodes.first.label, 'S1 E1 · Ep s1e1');
      expect(playback.episodes.last.label, 'SP E1 · Ep sp1');
      expect(playback.episodes.first.runtime, '31 min');
      expect(playback.episodes.first.airdate, '2010-06-16');
    });

    test('a movie is one episode pointing at itself', () {
      final map = JellyfinBridge.buildDetail(testServer, {
        ...movie('m1'),
        'RunTimeTicks': 61200000000,
        'ProductionLocations': ['Netherlands'],
      });
      final playback = PlaybackModel.fromJson(map);
      expect(playback.isSerial, isFalse);
      expect(playback.episodes.single.mediaRef, 'm1');
      expect(map['duration'], '1h 42m');
      expect(map['country'], 'Netherlands');
    });
  });

  group('links', () {
    Map<String, dynamic> info({
      bool direct = true,
      String? transcodingUrl,
      List<Map<String, dynamic>>? streams,
    }) => {
      'PlaySessionId': 'ps1',
      'MediaSources': [
        {
          'Id': 'm1',
          'Container': 'mkv',
          'Size': 1234,
          'SupportsDirectPlay': direct,
          'SupportsDirectStream': direct,
          'TranscodingUrl': ?transcodingUrl,
          'DefaultAudioStreamIndex': 1,
          'DefaultSubtitleStreamIndex': 3,
          'MediaStreams':
              streams ??
              [
                {'Type': 'Video', 'Index': 0, 'Codec': 'hevc', 'Height': 720},
                {'Type': 'Audio', 'Index': 1, 'Codec': 'eac3'},
                {
                  'Type': 'Subtitle',
                  'Index': 2,
                  'Codec': 'PGSSUB',
                  'IsTextSubtitleStream': false,
                  'DisplayTitle': 'English PGS',
                },
                {
                  'Type': 'Subtitle',
                  'Index': 3,
                  'Codec': 'subrip',
                  'IsTextSubtitleStream': true,
                  'DisplayTitle': 'English',
                },
                {
                  'Type': 'Subtitle',
                  'Index': 4,
                  'Codec': 'ass',
                  'IsExternal': true,
                  'IsTextSubtitleStream': true,
                  'Language': 'uzb',
                  'DeliveryUrl': '/Videos/m1/m1/Subtitles/4/0/Stream.ass',
                },
              ],
        },
      ],
    };

    ({Map<String, dynamic> links, JellyfinPlaySession? session}) build(
      Map<String, dynamic> info, {
      JellyfinServer server = testServer,
      Map<String, dynamic> item = const {},
    }) => JellyfinBridge.buildLinks(
      server,
      itemId: 'm1',
      info: info,
      item: item,
      deviceId: 'dev1',
      authHeader: 'MediaBrowser Token="tok123"',
      label: label,
    );

    test('direct file first, then transcodes stepping down', () {
      final media = MediaResolveModel.fromJson(build(info()).links);
      final sources = media.videoSources;
      expect(sources.map((s) => s.quality), [
        '720p · jellyfin.quality_original',
        '720p · jellyfin.quality_transcode',
        '480p · jellyfin.quality_transcode',
      ]);
      expect(sources.first.isDefault, isTrue);
      expect(sources.first.type, 'mp4');
      expect(sources.first.codec, 'hevc');
      expect(sources.first.sizeBytes, 1234);
      expect(Uri.parse(sources.first.videoUrl).path, '/Videos/m1/stream.mkv');
      expect(sources[1].type, 'hls');
      expect(
        Uri.parse(sources[1].videoUrl).queryParameters['MaxHeight'],
        '720',
      );
      for (final s in sources) {
        expect(Uri.parse(s.videoUrl).queryParameters['ApiKey'], 'tok123');
        expect(Uri.parse(s.videoUrl).queryParameters['PlaySessionId'], 'ps1');
        expect(s.headers['Authorization'], contains('tok123'));
      }
      expect(media.videoUrl, sources.first.videoUrl);
    });

    test('a server-chosen transcode leads when direct play is refused', () {
      final media = MediaResolveModel.fromJson(
        build(
          info(
            direct: false,
            transcodingUrl:
                '/videos/m1/master.m3u8?PlaySessionId=ps1&ApiKey=tok123',
          ),
        ).links,
      );
      final first = media.videoSources.first;
      expect(first.quality, 'jellyfin.quality_auto');
      expect(first.isDefault, isTrue);
      expect(
        first.videoUrl,
        'http://nas:8096/videos/m1/master.m3u8?PlaySessionId=ps1&ApiKey=tok123',
      );
    });

    test('pre-10.9 servers get api_key', () {
      final links = build(
        info(),
        server: testServer.copyWith(version: '10.8.13'),
      ).links;
      final media = MediaResolveModel.fromJson(links);
      final q = Uri.parse(media.videoSources.first.videoUrl).queryParameters;
      expect(q['api_key'], 'tok123');
      expect(q.containsKey('ApiKey'), isFalse);
    });

    test('text subtitles are offered, image ones are not', () {
      final media = MediaResolveModel.fromJson(build(info()).links);
      expect(media.subtitles.map((s) => s.label), ['English', 'uzb']);
      expect(
        media.subtitles.first.file,
        'http://nas:8096/Videos/m1/m1/Subtitles/3/0/Stream.vtt?ApiKey=tok123',
      );
      expect(media.subtitles.first.isDefault, isTrue);
      expect(
        media.subtitles.last.file,
        'http://nas:8096/Videos/m1/m1/Subtitles/4/0/Stream.ass?ApiKey=tok123',
      );
    });

    test('the session carries the resume point from user data', () {
      final session = build(
        info(),
        item: {
          'UserData': {'PlaybackPositionTicks': 12914650830, 'Played': false},
        },
      ).session!;
      expect(session.playSessionId, 'ps1');
      expect(session.mediaSourceId, 'm1');
      expect(session.resumeAt, const Duration(milliseconds: 1291465));

      final watched = build(
        info(),
        item: {
          'UserData': {'PlaybackPositionTicks': 0, 'Played': true},
        },
      ).session!;
      expect(watched.resumeAt, Duration.zero);
    });

    test('no media sources is an error, not an empty player', () {
      final built = build({'ErrorCode': 'NoCompatibleStream'});
      expect(built.session, isNull);
      expect(built.links['error'], contains('NoCompatibleStream'));
    });

    test('play method follows the url', () {
      expect(
        JellyfinPlaySession.playMethodFor(
          'http://h/Videos/x/stream.mkv?static=true',
        ),
        'DirectPlay',
      );
      expect(
        JellyfinPlaySession.playMethodFor('http://h/Videos/x/master.m3u8?a=1'),
        'Transcode',
      );
    });
  });

  group('against a server', () {
    test('home, detail and links go through the right routes', () async {
      final adapter = FakeJellyfinAdapter({
        // An old server: /UserViews is missing and the legacy route answers.
        '/Users/u1/Views': (_) => {
          'Items': [
            {'Id': 'lib1', 'Name': 'Movies', 'CollectionType': 'movies'},
            {'Id': 'music', 'Name': 'Music', 'CollectionType': 'music'},
          ],
        },
        '/UserItems/Resume': (_) => {'Items': []},
        '/Shows/NextUp': (_) => {'Items': []},
        '/Items/Latest': (_) => [movie('m1')],
        '/Items/m1': (_) => {
          ...movie('m1'),
          'UserData': {'PlaybackPositionTicks': 600000000},
        },
        '/Items/m1/Similar': (_) => {
          'Items': [movie('m2')],
        },
        '/Items/m1/PlaybackInfo': (_) => {
          'PlaySessionId': 'ps9',
          'MediaSources': [
            {
              'Id': 'm1',
              'Container': 'mp4',
              'SupportsDirectPlay': true,
              'MediaStreams': [
                {'Type': 'Video', 'Index': 0, 'Height': 1080},
              ],
            },
          ],
        },
      });
      final store = await storeWith([testServer]);
      final bridge = JellyfinBridge(
        api: fakeApi(adapter),
        store: store,
        label: label,
      );

      expect(bridge.listProviders().single['id'], 'jf:srv1');

      final home = await bridge.getMainPage('srv1');
      expect(home['error'], isNull);
      expect(
        (home['sections'] as List).map((s) => s['label']),
        ['Movies'],
        reason: 'music libraries are not for the video player',
      );

      final detail = await bridge.load('srv1', 'm1');
      expect((detail['related'] as List).single['contentUrl'], 'm2');

      final links = await bridge.loadLinks('srv1', 'm1');
      final url = (links['videoSources'] as List).first['videoUrl'] as String;
      final session = bridge.sessionFor(url)!;
      expect(session.playSessionId, 'ps9');
      expect(session.resumeAt, const Duration(minutes: 1));

      final auth = adapter.requests.first.headers['Authorization'] as String;
      expect(auth, contains('Client="Sozo"'));
      expect(auth, contains('DeviceId="dev1"'));
      expect(auth, contains('Token="tok123"'));

      final playbackInfo = adapter.requests.firstWhere(
        (r) => r.uri.path.endsWith('/PlaybackInfo'),
      );
      expect(playbackInfo.method, 'POST');
      expect(playbackInfo.uri.queryParameters['userId'], 'u1');
      expect((playbackInfo.data as Map)['DeviceProfile'], isA<Map>());
    });

    test('an unreachable server reports why', () async {
      final bridge = JellyfinBridge(
        api: fakeApi(FakeJellyfinAdapter({'/UserViews': (_) => 401})),
        store: await storeWith([testServer]),
        label: label,
      );
      final home = await bridge.getMainPage('srv1');
      expect(home['error'], 'jellyfin.error_session');
    });

    test('a removed server is an error on every path', () async {
      final bridge = JellyfinBridge(
        api: fakeApi(FakeJellyfinAdapter({})),
        store: await storeWith(const []),
        label: label,
      );
      expect(
        (await bridge.getMainPage('gone'))['error'],
        'jellyfin.error_server_removed',
      );
      expect(
        (await bridge.loadLinks('gone', 'x'))['error'],
        'jellyfin.error_server_removed',
      );
    });

    test('search maps episodes to their shows and pages', () async {
      final adapter = FakeJellyfinAdapter({
        '/Items': (r) => {
          'Items': [
            episode('e1', season: 1, number: 1),
            episode('e2', season: 1, number: 2),
            movie('m1'),
          ],
          'TotalRecordCount': 90,
        },
      });
      final bridge = JellyfinBridge(
        api: fakeApi(adapter),
        store: await storeWith([testServer]),
        label: label,
      );
      final res = await bridge.search('srv1', 'pio', page: 2);
      expect((res['items'] as List).map((i) => i['contentUrl']), [
        'series1',
        'm1',
      ]);
      expect(res['totalPages'], 3);
      final q = adapter.requests.single.uri.queryParameters;
      expect(q['searchTerm'], 'pio');
      expect(q['StartIndex'], '${JellyfinBridge.pageSize}');
    });
  });
}
