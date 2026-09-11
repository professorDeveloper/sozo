import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  Map<String, dynamic> Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (handler != null) {
      final res = handler!(options);
      return ResponseBody.fromString(
        jsonEncode(res),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('LiveProgramme', () {
    test('parses full json accurately', () {
      final now = DateTime.utc(2026, 9, 10, 12, 0);
      final stop = DateTime.utc(2026, 9, 10, 13, 0);
      final json = {
        'id': 'prog-1',
        'title': 'Grand Adventure',
        'subtitle': 'Episode 1',
        'description': 'A bold journey begins.',
        'category': 'Anime',
        'icon': 'https://example.com/poster.jpg',
        'season': 1,
        'episode': 1,
        'start': now.toIso8601String(),
        'stop': stop.toIso8601String(),
      };

      final prog = LiveProgramme.fromJson(json);
      expect(prog, isNotNull);
      expect(prog!.id, 'prog-1');
      expect(prog.title, 'Grand Adventure');
      expect(prog.subtitle, 'Episode 1');
      expect(prog.description, 'A bold journey begins.');
      expect(prog.category, 'Anime');
      expect(prog.icon, 'https://example.com/poster.jpg');
      expect(prog.season, 1);
      expect(prog.episode, 1);
      expect(prog.hasWindow, isTrue);
      expect(prog.duration, const Duration(hours: 1));
      expect(prog.episodeLabel, 'S1 E1');
    });

    test('returns null if title is missing or empty', () {
      expect(LiveProgramme.fromJson({'title': ''}), isNull);
      expect(LiveProgramme.fromJson({'id': '123'}), isNull);
      expect(LiveProgramme.fromJson(null), isNull);
      expect(LiveProgramme.fromJson('invalid'), isNull);
    });

    test('parses start and stop from epoch seconds and milliseconds', () {
      const startSec = 1700000000;
      const stopSec = 1700003600;
      final prog = LiveProgramme.fromJson({
        'title': 'News at Ten',
        'start': startSec,
        'stop': stopSec,
      });

      expect(prog, isNotNull);
      expect(prog!.hasWindow, isTrue);
      expect(prog.start?.isUtc, isFalse); // toLocal was invoked
      expect(prog.duration, const Duration(seconds: 3600));
    });

    test('calculates progress clamped between 0.0 and 1.0', () {
      final start = DateTime(2026, 9, 10, 10, 0);
      final stop = DateTime(2026, 9, 10, 11, 0);
      final prog = LiveProgramme(title: 'Show', start: start, stop: stop);

      // Before start
      expect(prog.progressAt(DateTime(2026, 9, 10, 9, 30)), 0.0);
      // Halfway
      expect(prog.progressAt(DateTime(2026, 9, 10, 10, 30)), 0.5);
      // At stop
      expect(prog.progressAt(DateTime(2026, 9, 10, 11, 0)), 1.0);
      // After stop
      expect(prog.progressAt(DateTime(2026, 9, 10, 12, 0)), 1.0);
    });

    test('calculates remaining duration correctly without negative', () {
      final start = DateTime(2026, 9, 10, 10, 0);
      final stop = DateTime(2026, 9, 10, 11, 0);
      final prog = LiveProgramme(title: 'Show', start: start, stop: stop);

      expect(
        prog.remainingAt(DateTime(2026, 9, 10, 10, 15)),
        const Duration(minutes: 45),
      );
      expect(
        prog.remainingAt(DateTime(2026, 9, 10, 11, 30)),
        Duration.zero,
      );
    });

    test('evaluates isBarWorthy based on duration thresholds', () {
      final start = DateTime(2026, 9, 10, 10, 0);
      // 4 minutes: too short (< 5 min)
      final tooShort = LiveProgramme(
        title: 'Bumper',
        start: start,
        stop: start.add(const Duration(minutes: 4)),
      );
      expect(tooShort.isBarWorthy, isFalse);

      // 30 minutes: worthy
      final normal = LiveProgramme(
        title: 'Sitcom',
        start: start,
        stop: start.add(const Duration(minutes: 30)),
      );
      expect(normal.isBarWorthy, isTrue);

      // 7 hours: too long (> 360 min)
      final tooLong = LiveProgramme(
        title: 'Marathon',
        start: start,
        stop: start.add(const Duration(hours: 7)),
      );
      expect(tooLong.isBarWorthy, isFalse);
    });

    test('formats episode labels with various combinations', () {
      expect(const LiveProgramme(title: 'A', season: 2, episode: 4).episodeLabel, 'S2 E4');
      expect(const LiveProgramme(title: 'A', episode: 4).episodeLabel, 'E4');
      expect(const LiveProgramme(title: 'A', season: 2).episodeLabel, 'S2');
      expect(const LiveProgramme(title: 'A').episodeLabel, '');
    });
  });

  group('LiveChannel', () {
    test('parses channel json with headers, guide and category', () {
      final json = {
        'id': 'ch-anime',
        'name': 'Anime Central',
        'streamUrl': 'https://stream.example.com/live.m3u8',
        'logoUrl': 'https://stream.example.com/logo.png',
        'country': 'JP',
        'language': 'ja',
        'category': 'Animation',
        'headers': {'User-Agent': 'Kaizoku/1.0', 'Referer': 'https://example.com'},
        'now': {'title': 'Current Show'},
        'next': {'title': 'Upcoming Show'},
      };

      final ch = LiveChannel.fromJson(json);
      expect(ch, isNotNull);
      expect(ch!.id, 'ch-anime');
      expect(ch.name, 'Anime Central');
      expect(ch.streamUrl, 'https://stream.example.com/live.m3u8');
      expect(ch.headers['User-Agent'], 'Kaizoku/1.0');
      expect(ch.hasGuide, isTrue);
      expect(ch.now?.title, 'Current Show');
      expect(ch.next?.title, 'Upcoming Show');
    });

    test('returns null when id, streamUrl, or name is missing', () {
      expect(LiveChannel.fromJson({'name': 'Test', 'streamUrl': 'http://x'}), isNull);
      expect(LiveChannel.fromJson({'id': '1', 'streamUrl': ''}), isNull);
      expect(LiveChannel.fromJson({'id': '1', 'name': ''}), isNull);
    });

    test('slotAt transitions from now to next when now expires', () {
      final t1 = DateTime(2026, 9, 10, 10, 0);
      final t2 = DateTime(2026, 9, 10, 11, 0);
      final t3 = DateTime(2026, 9, 10, 12, 0);

      final ch = LiveChannel(
        id: '1',
        name: 'Ch',
        streamUrl: 'http://test',
        now: LiveProgramme(title: 'Morning Show', start: t1, stop: t2),
        next: LiveProgramme(title: 'Midday News', start: t2, stop: t3),
      );

      expect(ch.slotAt(DateTime(2026, 9, 10, 10, 30))?.title, 'Morning Show');
      expect(ch.slotAt(DateTime(2026, 9, 10, 11, 15))?.title, 'Midday News');
      expect(ch.slotAt(DateTime(2026, 9, 10, 12, 30)), isNull);
    });

    test('withGuide immutably clones channel with new slots', () {
      const ch = LiveChannel(id: '1', name: 'Ch', streamUrl: 'http://test');
      final updated = ch.withGuide(
        const LiveProgramme(title: 'New Now'),
        const LiveProgramme(title: 'New Next'),
      );

      expect(ch.now, isNull);
      expect(updated.now?.title, 'New Now');
      expect(updated.next?.title, 'New Next');
    });
  });

  group('LiveSchedule', () {
    test('sorts programmes chronologically with untimed at end', () {
      final t1 = DateTime(2026, 9, 10, 8, 0);
      final t2 = DateTime(2026, 9, 10, 10, 0);
      final json = {
        'channel': {'id': 'ch-1', 'name': 'Channel 1'},
        'programmes': [
          {'title': 'Untimed Late Entry'},
          {'title': 'Mid Morning', 'start': t2.toIso8601String()},
          {'title': 'Early Morning', 'start': t1.toIso8601String()},
        ],
      };

      final schedule = LiveSchedule.fromJson(json, fallbackId: 'fallback');
      expect(schedule.channelId, 'ch-1');
      expect(schedule.channelName, 'Channel 1');
      expect(schedule.programmes.length, 3);
      expect(schedule.programmes[0].title, 'Early Morning');
      expect(schedule.programmes[1].title, 'Mid Morning');
      expect(schedule.programmes[2].title, 'Untimed Late Entry');
    });

    test('currentAt, nextAfter, and from filter according to timestamp', () {
      final t1 = DateTime(2026, 9, 10, 8, 0);
      final t2 = DateTime(2026, 9, 10, 10, 0);
      final t3 = DateTime(2026, 9, 10, 12, 0);

      final schedule = LiveSchedule(
        channelId: '1',
        channelName: 'Test',
        programmes: [
          LiveProgramme(title: 'P1', start: t1, stop: t2),
          LiveProgramme(title: 'P2', start: t2, stop: t3),
        ],
      );

      final queryTime = DateTime(2026, 9, 10, 9, 0);
      expect(schedule.currentAt(queryTime)?.title, 'P1');
      expect(schedule.nextAfter(queryTime)?.title, 'P2');

      final fromList = schedule.from(queryTime);
      expect(fromList.map((e) => e.title), ['P1', 'P2']);

      final afterP1 = schedule.from(DateTime(2026, 9, 10, 10, 30));
      expect(afterP1.map((e) => e.title), ['P2']);
    });
  });

  group('LiveTvService HTTP Integration', () {
    late Dio dio;
    late _FakeDioAdapter adapter;
    late LiveTvService service;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://test.api'));
      adapter = _FakeDioAdapter();
      dio.httpClientAdapter = adapter;
      service = LiveTvService(dio: dio);
    });

    test('index() returns parsed folders and countries', () async {
      adapter.handler = (options) {
        expect(options.path, '/channels/categories');
        return {
          'categories': [
            {'name': 'Movies', 'count': 42, 'logoUrl': 'http://img/movies.png'},
            {'name': 'Sports', 'count': 18},
          ],
          'countries': [
            {'code': 'JP', 'count': 25},
            {'code': 'US', 'count': 35},
          ],
        };
      };

      final index = await service.index();
      expect(index.folders.length, 2);
      expect(index.folders[0].name, 'Movies');
      expect(index.folders[0].count, 42);
      expect(index.countries.length, 2);
      expect(index.countries[0].code, 'JP');
      expect(index.countries[0].count, 25);
    });

    test('browse() sends filters and paginates channels', () async {
      adapter.handler = (options) {
        expect(options.path, '/channels/browse');
        expect(options.queryParameters['page'], 2);
        expect(options.queryParameters['limit'], 20);
        expect(options.queryParameters['category'], 'Anime');
        expect(options.queryParameters['country'], 'JP');
        expect(options.queryParameters['search'], 'Action');

        return {
          'page': 2,
          'total': 100,
          'hasMore': true,
          'channels': [
            {
              'id': 'ch-action',
              'name': 'Action TV',
              'streamUrl': 'https://action.stream/live.m3u8',
            }
          ],
        };
      };

      final page = await service.browse(
        category: 'Anime',
        country: 'JP',
        search: 'Action',
        page: 2,
        limit: 20,
      );

      expect(page.page, 2);
      expect(page.total, 100);
      expect(page.hasMore, isTrue);
      expect(page.channels.length, 1);
      expect(page.channels[0].name, 'Action TV');
    });

    test('schedule() encodes channelId and parses response', () async {
      adapter.handler = (options) {
        expect(options.path, '/channels/ch.custom%2F1/epg');
        expect(options.queryParameters['hours'], 48);
        return {
          'channel': {'id': 'ch.custom/1', 'name': 'Custom Channel'},
          'programmes': [
            {'title': 'Program 1'},
          ],
        };
      };

      final sched = await service.schedule('ch.custom/1', hours: 48);
      expect(sched.channelId, 'ch.custom/1');
      expect(sched.channelName, 'Custom Channel');
      expect(sched.programmes.length, 1);
    });

    test('schedule() returns empty schedule on empty channel id without request', () async {
      bool called = false;
      adapter.handler = (_) {
        called = true;
        return {};
      };

      final sched = await service.schedule('   ');
      expect(called, isFalse);
      expect(sched.isEmpty, isTrue);
    });
  });
}
