import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/data/tmdb_relations.dart';

/// Answers each TMDB path from [routes]; anything else is a 404.
class _Tmdb implements HttpClientAdapter {
  _Tmdb(this.routes);
  final Map<String, Object> routes;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options.path);
    final body = routes[options.path];
    return ResponseBody.fromString(
      jsonEncode(body ?? {}),
      body == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

TmdbRelations _with(_Tmdb tmdb) =>
    TmdbRelations(Dio()..httpClientAdapter = tmdb);

void main() {
  test(
    "Grey's Anatomy: the show, then what TMDB recommends after it",
    () async {
      final tmdb = _Tmdb({
        '/tmdb/search/multi': {
          'results': [
            {
              'id': 9,
              'media_type': 'tv',
              'name': 'Anatomy',
              'first_air_date': '2020-01-01',
            },
            {
              'id': 1416,
              'media_type': 'tv',
              'name': "Grey's Anatomy",
              'first_air_date': '2005-03-27',
              'genre_ids': [18],
              'original_language': 'en',
            },
          ],
        },
        '/tmdb/tv/1416/recommendations': {
          'results': [
            {
              'id': 2,
              'name': 'ER',
              'first_air_date': '1994-09-19',
              'poster_path': '/er.jpg',
            },
            {'id': 3, 'name': 'Chicago Med', 'first_air_date': '2015-11-17'},
          ],
        },
      });
      final service = _with(tmdb);
      final title = await service.find(
        "Grey's Anatomy",
        year: 2005,
        isSerial: true,
      );
      expect(title?.id, 1416);
      expect(title?.isAnime, isFalse);
      final relations = await service.relationsOf(title!);
      expect([for (final r in relations) r.title], ['ER', 'Chicago Med']);
      expect(relations.first.relationType, TmdbRelations.recommended);
      expect(relations.first.coverImage, endsWith('/er.jpg'));
      expect(relations.first.year, 1994);
    },
  );

  test('a film: the rest of its franchise first, in release order', () async {
    final tmdb = _Tmdb({
      '/tmdb/movie/2': {
        'belongs_to_collection': {'id': 77},
      },
      '/tmdb/collection/77': {
        'parts': [
          {'id': 3, 'title': 'Part 3', 'release_date': '2010-01-01'},
          {'id': 2, 'title': 'Part 2', 'release_date': '2005-01-01'},
          {'id': 1, 'title': 'Part 1', 'release_date': '2001-01-01'},
        ],
      },
      '/tmdb/movie/2/recommendations': {
        'results': [
          {'id': 3, 'title': 'Part 3'},
          {'id': 50, 'title': 'Something else'},
        ],
      },
    });
    final relations = await _with(
      tmdb,
    ).relationsOf(const TmdbTitle(id: 2, isTv: false, title: 'Part 2'));
    expect(
      [for (final r in relations) r.title],
      ['Part 1', 'Part 3', 'Something else'],
    );
    expect(relations.first.relationType, TmdbRelations.collection);
    expect(relations.last.relationType, TmdbRelations.recommended);
  });

  test('a title nothing matches well is no title at all', () async {
    final tmdb = _Tmdb({
      '/tmdb/search/multi': {
        'results': [
          {'id': 5, 'media_type': 'movie', 'title': 'The Return of the King'},
        ],
      },
    });
    expect(await _with(tmdb).find('Return of the Blossoming Blade'), isNull);
  });

  test('Japanese animation is left to AniList', () async {
    final tmdb = _Tmdb({
      '/tmdb/search/multi': {
        'results': [
          {
            'id': 46260,
            'media_type': 'tv',
            'name': 'Naruto',
            'genre_ids': [16],
            'original_language': 'ja',
          },
        ],
      },
    });
    final title = await _with(tmdb).find('Naruto');
    expect(title?.isAnime, isTrue);
  });
}
