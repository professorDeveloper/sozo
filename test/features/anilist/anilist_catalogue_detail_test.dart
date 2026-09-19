import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/detail/presentation/blocs/detail_bloc/detail_bloc.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

/// That the three AniList shelves all reach AniList.
///
/// The mapping from an AniList record to a page was already covered, and it
/// passed for manga and novels the whole time the pages were blank — because
/// the record was never fetched. What was missing is the step before it: the
/// detail bloc matched only the ANIME shelf, so a manga or a light novel fell
/// through to "find me a source" and died there as `catalogue.no_source`.
/// These tests watch the branch, not the mapping.
void main() {
  group('a catalogue title from an AniList reader shelf', () {
    test('asks AniList for the manga record, with no source installed', () async {
      final anilist = _Api();
      final bloc = _bloc(anilist);

      final state = await _settle(
        bloc,
        const DetailLoad(
          'https://anilist.co/manga/30002',
          provider: 'cat:anilist-manga',
        ),
      );

      expect(
        anilist.asked,
        [(30002, 'MANGA')],
        reason: 'MANGA, not ANIME: that id under ANIME is a 404',
      );
      expect(
        state,
        isA<DetailLoaded>(),
        reason: 'the record is the page; a missing source only costs Play',
      );
      expect((state as DetailLoaded).detail.title, 'Berserk');
      expect(state.via, isNull);
      await bloc.close();
    });

    test('a light novel is MANGA to AniList, and reaches it too', () async {
      // AniList has no NOVEL type — a light novel is MANGA with format NOVEL,
      // so the novel shelf must not invent a third type to ask for.
      final anilist = _Api();
      final bloc = _bloc(anilist);

      final state = await _settle(
        bloc,
        const DetailLoad(
          'https://anilist.co/manga/86635',
          provider: 'cat:anilist-novel',
        ),
      );

      expect(anilist.asked, [(86635, 'MANGA')]);
      expect(state, isA<DetailLoaded>());
      await bloc.close();
    });

    test('the anime shelf still asks for ANIME', () async {
      final anilist = _Api();
      final bloc = _bloc(anilist);

      await _settle(
        bloc,
        const DetailLoad(
          'https://anilist.co/anime/154587',
          provider: 'cat:anilist',
        ),
      );

      expect(anilist.asked, [(154587, 'ANIME')]);
      await bloc.close();
    });
  });

  group('searchMedia', () {
    test('searches the manga index when a reader asks', () async {
      final adapter = _Adapter(body: jsonEncode({'data': {'Page': {'media': []}}}));
      final api = AnilistApi(dio: Dio()..httpClientAdapter = adapter);

      await api.searchMedia('Berserk', type: 'MANGA');

      expect(_variables(adapter.requests.single)['type'], 'MANGA');
    });

    test('stays on anime for a caller that did not ask to widen', () async {
      // The skip-times lookup and the search suggestions both pass an id on to
      // something that only knows anime. A default of "both" would hand them a
      // manga's id looking exactly like an anime's.
      final adapter = _Adapter(body: jsonEncode({'data': {'Page': {'media': []}}}));
      final api = AnilistApi(dio: Dio()..httpClientAdapter = adapter);

      await api.searchMedia('Berserk');

      expect(_variables(adapter.requests.single)['type'], 'ANIME');
    });
  });

  group('the author line', () {
    Future<String?> authorOf(List<(String, String)> staff) async {
      final adapter = _Adapter(
        body: jsonEncode({
          'data': {
            'Media': {
              'id': 1,
              'staff': {
                'edges': [
                  for (final (role, name) in staff)
                    {
                      'role': role,
                      'node': {
                        'name': {'full': name},
                      },
                    },
                ],
              },
            },
          },
        }),
      );
      final api = AnilistApi(dio: Dio()..httpClientAdapter = adapter);
      return (await api.mediaDetail(1))?.author;
    }

    // Every role string below is quoted from a live
    // `staff(sort: RELEVANCE)` reply, qualifiers and stray spaces included —
    // invented ones would only prove the test agrees with itself.

    test('a manga is credited to whoever wrote it', () async {
      // Berserk (30002), verbatim: AniList hangs the volume range off the
      // credit, so the role never arrives as the bare word.
      expect(
        await authorOf([
          ('Story & Art (vols 1-41)', 'Kentarou Miura'),
          ('Story & Art (vols 41- )', 'Studio Gaga'),
          ('Supervisor (vols 41- )', 'Kouji Mori'),
        ]),
        'Kentarou Miura',
      );
      // A light novel's writer is filed as "Story" — with a trailing space on
      // Mushoku Tensei and Re:Zero, which a set lookup only survives if the
      // role is trimmed first.
      expect(
        await authorOf([
          ('Story ', 'Rifujin na Magonote'),
          ('Illustration', 'Sirotaka'),
        ]),
        'Rifujin na Magonote',
      );
      // The artist of somebody else's story is not its author, and the story
      // credit wins wherever AniList happened to sort it.
      expect(
        await authorOf([('Art', 'Fukui Takumi'), ('Story', 'Maruyama Kugane')]),
        'Maruyama Kugane',
      );
    });

    test('an anime names the book it came from, never its director', () async {
      // One Piece (21), verbatim.
      expect(
        await authorOf([
          ('Original Creator', 'Eiichirou Oda'),
          ('Director (eps 1-278)', 'Kounosuke Uda'),
          ('Character Design (eps 385-891)', 'Kazuya Hisada'),
        ]),
        'Eiichirou Oda',
      );
      // Cowboy Bebop (1), verbatim: an anime written for the screen still has
      // an Original Creator — Sunrise's house pen name — and "Series
      // Composition" sitting under it is the near miss that must lose.
      expect(
        await authorOf([
          ('Original Creator', 'Hajime Yatate'),
          ('Director', 'Shinichirou Watanabe'),
          ('Series Composition', 'Keiko Nobumoto'),
        ]),
        'Hajime Yatate',
      );
      // With no creator credited at all there is no author, and the most
      // relevant name is the director — exactly the name this must not print.
      expect(
        await authorOf([
          ('Director', 'Shinichirou Watanabe'),
          ('Original Character Design', 'Toshihiro Kawamoto'),
        ]),
        isNull,
      );
    });

    test('a job done on somebody else\'s story is not a writing credit', () async {
      // The whole point of matching the credit exactly. Every one of these
      // contains "story" or "original", and a substring test printed whichever
      // came first as the Author.
      for (final role in const [
        'Storyboard (OP1, eps 1, 25)', // Shingeki no Kyojin, verbatim
        'Story Board',
        'Story Composition',
        'Series Composition',
        'Story Editor',
        'Story Supervisor',
        'Original Character Design',
        'Original Work Assistance',
      ]) {
        expect(
          await authorOf([(role, 'Somebody Else'), ('Director', 'A Director')]),
          isNull,
          reason: '"$role" was taken for a writing credit',
        );
      }
    });

    test('the writer beats the assistant AniList ranks above them', () async {
      // The order AniList really returns for The Promised Neverland: the
      // helper first, the writer second.
      expect(
        await authorOf([
          ('Original Work Assistance', 'Sugita Taku'),
          ('Original Story', 'Shirai Kaiu'),
        ]),
        'Shirai Kaiu',
      );
    });
  });
}

DetailBloc _bloc(_Api anilist) => DetailBloc(
  useCase: const GetDetailUseCase(_Repository()),
  resolver: _NoSource(),
  anilist: anilist,
);

/// Runs one load and returns the state it settles on.
Future<DetailState> _settle(DetailBloc bloc, DetailLoad event) {
  final settled = bloc.stream.firstWhere((s) => s is! DetailLoading);
  bloc.add(event);
  return settled;
}

Map<String, dynamic> _variables(RequestOptions request) =>
    ((request.data as Map)['variables'] as Map).cast<String, dynamic>();

/// Records what was asked for, and answers with a manga.
class _Api implements AnilistApi {
  final List<(int, String?)> asked = [];

  @override
  Future<AnilistMediaDetail?> mediaDetail(int id, {String? type}) async {
    asked.add((id, type));
    return AnilistMediaDetail(
      media: AnilistMedia(
        id: id,
        type: 'MANGA',
        romajiTitle: 'Berserk',
        chapters: 380,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Nothing installed has the title — the normal case for a manga, and the one
/// that used to leave the page empty.
class _NoSource implements CatalogueResolver {
  @override
  Future<CatalogueLink?> resolve({
    required String catalogueId,
    required String contentUrl,
    required MovieEntity? hint,
  }) async => null;

  // The bloc asks `locate` rather than `resolve` so it can say WHY nothing was
  // found. `notCarried` is the case this fake stands for: sources of the right
  // kind were asked and none of them lists the title.
  @override
  Future<CatalogueResolution> locate({
    required String catalogueId,
    required String contentUrl,
    required MovieEntity? hint,
  }) async => CatalogueResolution(
    catalogue: Catalogue.fromId(catalogueId),
    miss: CatalogueMiss.notCarried,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails loudly: reaching the source path at all is the bug under test.
class _Repository implements DetailRepository {
  const _Repository();

  @override
  Future<Result<DetailEntity>> getDetail(
    String contentUrl, {
    String? provider,
  }) async => Failure(Exception('the source page was asked for'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers every request with one body, and keeps what it was asked.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.body = ''});

  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
