// Zangetsu payloads: an 18+ device source's live answers with the titles
// replaced, and the server wrapper's metadata passthrough.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/data/models/view_all_paging_model.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/search/data/model/search_model.dart';

void main() {
  final payloads =
      jsonDecode(
            File('test/fixtures/zangetsu_payloads.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  // What WebKit hands the channel: every object a Map<Object?, Object?> and
  // every number a double.
  Object? doubles(Object? v) => switch (v) {
    final int n => n.toDouble(),
    final Map m => {for (final e in m.entries) e.key: doubles(e.value)},
    final List l => l.map(doubles).toList(),
    _ => v,
  };
  Object? overChannel(String key) => const StandardMessageCodec().decodeMessage(
    const StandardMessageCodec().encodeMessage(doubles(payloads[key])),
  );

  final arrivals = <String, Map<String, dynamic> Function(String)>{
    'JSON text': (key) => jsObjectFrom(jsonEncode(payloads[key]))!,
    'WebKit objects': (key) => jsObjectFrom(overChannel(key))!,
  };

  for (final MapEntry(key: how, value: read) in arrivals.entries) {
    group('device source, $how', () {
      test('home, view-all, search and an empty genre page', () {
        final home = HomeDataModel.fromJson(read('home'));
        expect(home.banner, hasLength(2));
        expect(home.sections.first.viewAll.slug, 'row-0');
        expect(home.sections.first.items.first.title, 'Title 1');

        final page = ViewAllPagingModel.fromJson(read('category'));
        expect(page.page, 1);
        expect(page.totalPages, 1);
        expect(page.items, hasLength(2));

        expect(SearchModel.fromJson(read('search')).items, hasLength(2));
        expect(ViewAllPagingModel.fromJson(read('genre')).items, isEmpty);
      });

      test('detail and episodes', () {
        final detail = DetailModel.fromJson(read('detail'));
        expect(detail.genres, ['Genre A', 'Genre B']);
        expect(detail.related, hasLength(2));
        expect(detail.cast, isEmpty);

        final eps = PlaybackModel.fromJson(read('episodes'));
        expect(eps.episodes.single.episode, 1);
        expect(eps.episodes.single.mediaRef, startsWith('sample:ep:'));
      });

      test('media keeps every source and its headers', () {
        final media = MediaResolveModel.fromJson(read('media'));
        expect(media.videoSources, hasLength(2));
        expect(
          media.videoSources.first.headers['Origin'],
          'https://site.invalid',
        );
        expect(media.headers['User-Agent'], 'UA');
      });
    });
  }

  test('WebKit numbers come back as ints', () {
    final page = jsObjectFrom(overChannel('category'))!;
    expect(page['page'], isA<int>());
    expect(jsObjectFrom({'r': 7.5})!['r'], 7.5);
  });

  group('server wrapper passthrough', () {
    Map<String, dynamic> overDio(String key) =>
        jsonDecode(jsonEncode(payloads[key])) as Map<String, dynamic>;

    test('screenshots as bare urls and cast with images', () {
      final detail = DetailModel.fromJson(overDio('server_detail'));
      expect(detail.screenshots.map((s) => s.full), [
        'https://img.invalid/9/1.jpg',
        'https://img.invalid/9/2.jpg',
      ]);
      expect(detail.screenshots.first.thumb, detail.screenshots.first.full);
      expect(detail.cast.map((c) => c.name), [
        'Performer One',
        'Performer Two',
      ]);
      expect(detail.cast.first.image, 'https://img.invalid/p1.jpg');
      expect(detail.cast.last.image, '');
      expect(detail.duration, '12 min');
      expect(detail.year, 2024);
    });

    test('odd cast, screenshot and count values are tolerated', () {
      final detail = DetailModel.fromJson({
        'cast': [
          'A Name',
          42,
          null,
          {'id': 7, 'name': 'B', 'avatar': 'x'},
        ],
        'screenshots': [
          {'full': 'f', 'thumb': 't'},
          '',
          3,
        ],
        'genres': [
          {'name': 'G'},
          'H',
        ],
        'duration': 840,
        'likes': '12',
        'year': '2020',
        'isSerial': 1,
      });
      expect(detail.cast.map((c) => c.name), ['A Name', '42', 'B']);
      expect(detail.cast.last.id, '7');
      expect(detail.cast.last.image, 'x');
      expect(detail.screenshots.single.thumb, 't');
      expect(detail.genres, ['G', 'H']);
      expect(detail.duration, isNull);
      expect(detail.likes, 12);
      expect(detail.year, 2020);
      expect(detail.isSerial, isTrue);
    });

    test('actor page', () {
      final page = ViewAllPagingModel.fromJson(overDio('server_actor'));
      expect(page.totalPages, 2);
      expect(page.items.single.provider, 'sample-server');
    });
  });

  group('stored and read back', () {
    test('a Hive map reads as Map<dynamic, dynamic>', () {
      final stored = Map<dynamic, dynamic>.from(
        overChannel('server_detail')! as Map,
      );
      final detail = DetailModel.fromJson(jsonMap(stored)!);
      expect(detail.screenshots, hasLength(2));
      expect(jsonMap('not a map'), isNull);
      expect(jsonMaps([stored, 'x', null]), hasLength(1));
    });

    test('favourite and history of a device title', () {
      final detail = DetailModel.fromJson(jsObjectFrom(overChannel('detail'))!);
      final fav = FavoriteModel(
        provider: detail.provider,
        contentUrl: detail.contentUrl,
        title: detail.title,
        thumbnail: detail.thumbnail ?? '',
        description: detail.description,
      );
      final favBack = FavoriteModel.fromJson(
        jsonDecode(jsonEncode(fav.toJson())) as Map<String, dynamic>,
      );
      expect(favBack.contentUrl, detail.contentUrl);

      final item = HistoryItem(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        title: detail.title,
        isSerial: detail.isSerial,
        episodeIndex: 0,
        episodeNumber: 1,
        positionMs: 1000,
        durationMs: 60000,
        watchedAt: 1,
      );
      final back = HistoryItem.fromJson(jsonMap(doubles(item.toJson()))!);
      expect(back.episodeNumber, 1);
      expect(back.positionMs, 1000);
      final asDoubles = HistoryItem.fromJson(
        (doubles(item.toJson())! as Map).cast<String, dynamic>(),
      );
      expect(asDoubles.durationMs, 60000);
    });
  });
}
