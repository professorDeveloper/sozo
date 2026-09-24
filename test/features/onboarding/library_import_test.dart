import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/onboarding/data/library_import_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

Map<String, dynamic> _media(
  int id, {
  String type = 'ANIME',
  String? format,
  int? idMal,
  bool adult = false,
  bool site = true,
}) => {
  'id': id,
  'idMal': idMal,
  'type': type,
  'format': format ?? (type == 'ANIME' ? 'TV' : 'MANGA'),
  'seasonYear': 2020 + id % 5,
  'siteUrl': site
      ? 'https://anilist.co/${type == 'ANIME' ? 'anime' : 'manga'}/$id'
      : null,
  'title': {'english': 'Title $id', 'romaji': 'Romaji $id'},
  'coverImage': {'large': 'https://img.anili.st/$id.jpg'},
  'isAdult': adult,
};

AnilistListEntry _entry(
  int id,
  String status, {
  String type = 'ANIME',
  String? format,
  bool adult = false,
  bool site = true,
}) => AnilistListEntry.fromJson({
  'id': id * 10,
  'status': status,
  'progress': 3,
  'media': _media(id, type: type, format: format, adult: adult, site: site),
});

MalListEntry _mal(int id, String status, {bool rewatching = false}) =>
    MalListEntry.fromJson({
      'node': {
        'id': id,
        'title': 'MAL $id',
        'main_picture': {'large': 'https://cdn.myanimelist.net/$id.jpg'},
      },
      'list_status': {
        'status': status,
        'num_episodes_watched': 2,
        'is_rewatching': rewatching,
      },
    })!;

class _FakeSink implements LibraryImportSink {
  final follows = <FollowedTitle>[];
  final list = <FavoriteEntity>[];

  @override
  bool isFollowed(String contentUrl) =>
      follows.any((f) => f.contentUrl == contentUrl);

  @override
  Future<void> follow(FollowedTitle title) async => follows.add(title);

  @override
  bool isListed(String contentUrl) =>
      list.any((f) => f.contentUrl == contentUrl);

  @override
  Future<void> addToList(FavoriteEntity entry) async => list.add(entry);
}

void main() {
  final anime = [
    _entry(1, 'CURRENT'),
    _entry(2, 'REPEATING'),
    _entry(3, 'PLANNING'),
    _entry(4, 'COMPLETED'),
    _entry(5, 'DROPPED'),
    _entry(6, 'CURRENT', adult: true),
    _entry(7, 'CURRENT', site: false),
  ];
  final manga = [
    _entry(11, 'CURRENT', type: 'MANGA'),
    _entry(12, 'CURRENT', type: 'MANGA', format: 'NOVEL'),
    _entry(13, 'PLANNING', type: 'MANGA', format: 'NOVEL'),
    _entry(14, 'PAUSED', type: 'MANGA'),
  ];

  group('AniList', () {
    final plan = planAnilistImport([...anime, ...manga], now: 42);

    test('watching and rewatching are followed, planning goes to My List', () {
      expect(plan.follows.map((f) => f.anilistId), [1, 2, 7, 11, 12]);
      expect(plan.listAdds.map((a) => a.contentUrl), [
        'https://anilist.co/anime/3',
        'https://anilist.co/manga/13',
      ]);
    });

    test('an anime follow opens in the AniList catalogue', () {
      final f = plan.follows.first;
      expect(f.provider, 'cat:anilist');
      expect(f.contentUrl, 'https://anilist.co/anime/1');
      expect(f.title, 'Title 1');
      expect(f.thumbnail, 'https://img.anili.st/1.jpg');
      expect(f.year, 2021);
      expect(f.mode, 'video');
      expect(f.addedAt, 42);
    });

    test('manga and light novels go to their own shelves', () {
      final m = plan.follows.firstWhere((f) => f.anilistId == 11);
      expect(m.provider, 'cat:anilist-manga');
      expect(m.mode, 'manga');
      final n = plan.follows.firstWhere((f) => f.anilistId == 12);
      expect(n.provider, 'cat:anilist-novel');
      expect(n.mode, 'novel');
      expect(plan.listAdds.last.provider, 'cat:anilist-novel');
    });

    test('a title with no site url still gets its AniList address', () {
      final f = plan.follows.firstWhere((f) => f.anilistId == 7);
      expect(f.contentUrl, 'https://anilist.co/anime/7');
    });

    test('adult titles only with 18+ on', () {
      expect(plan.follows.any((f) => f.anilistId == 6), isFalse);
      final adult = planAnilistImport(anime, allowAdult: true);
      expect(adult.follows.any((f) => f.anilistId == 6), isTrue);
    });

    test('the follow record survives a round trip', () {
      final f = plan.follows.first;
      final back = FollowedTitle.fromJson(f.toJson());
      expect(back.anilistId, 1);
      expect(back.mode, 'video');
    });
  });

  group('MyAnimeList', () {
    final entries = [
      _mal(100, MalStatus.watching),
      _mal(101, MalStatus.completed, rewatching: true),
      _mal(102, MalStatus.planToWatch),
      _mal(103, MalStatus.dropped),
      _mal(104, MalStatus.watching),
    ];
    final byMal = {
      100: AnilistMedia.fromJson(_media(1, idMal: 100)),
      101: AnilistMedia.fromJson(_media(2, idMal: 101)),
      102: AnilistMedia.fromJson(_media(3, idMal: 102)),
    };

    test('is tied to AniList through idMal', () {
      final plan = planMalImport(entries, byMal);
      expect(plan.follows.map((f) => f.anilistId), [1, 2]);
      expect(plan.follows.first.provider, 'cat:anilist');
      expect(plan.follows.first.contentUrl, 'https://anilist.co/anime/1');
      expect(plan.listAdds.single.contentUrl, 'https://anilist.co/anime/3');
    });

    test('rows AniList does not know are counted and left out', () {
      expect(planMalImport(entries, byMal).unmatched, 1);
    });
  });

  group('running it', () {
    LibraryImportService service(_FakeSink sink) => LibraryImportService(
      sink: sink,
      anilistLibrary: (type) async => type == 'ANIME' ? anime : manga,
      malLibrary: () async => [
        _mal(100, MalStatus.watching),
        _mal(102, MalStatus.planToWatch),
      ],
      anilistByMalIds: (ids) async => {
        for (final id in ids)
          id: AnilistMedia.fromJson(_media(id - 99, idMal: id)),
      },
    );

    test('reports each title and finishes with the counts', () async {
      final sink = _FakeSink();
      final steps = await service(sink).run(ImportSource.anilist).toList();
      final last = steps.last;
      expect(last.finished, isTrue);
      expect(last.followed, 5);
      expect(last.listed, 2);
      expect(steps.where((s) => s.cover != null).length, 7);
    });

    test('running again adds nothing twice', () async {
      final sink = _FakeSink();
      final svc = service(sink);
      await svc.run(ImportSource.anilist).toList();
      final second = await svc.run(ImportSource.anilist).toList();
      expect(second.last.followed, 0);
      expect(second.last.listed, 0);
      expect(sink.follows.length, 5);
      expect(sink.list.length, 2);
    });

    test('AniList and MAL importing the same show follow it once', () async {
      final sink = _FakeSink();
      final svc = service(sink);
      await svc.run(ImportSource.anilist).toList();
      final mal = await svc.run(ImportSource.mal).toList();
      // MAL 100 is AniList 1 (already followed), MAL 102 is AniList 3
      // (already in My List).
      expect(mal.last.followed, 0);
      expect(mal.last.listed, 0);
      expect(sink.follows.length, 5);
    });

    test('a failed fetch reaches the listener', () async {
      final svc = LibraryImportService(
        sink: _FakeSink(),
        anilistLibrary: (_) async => throw StateError('offline'),
        malLibrary: () async => const [],
        anilistByMalIds: (_) async => const {},
      );
      expect(svc.run(ImportSource.anilist).toList(), throwsStateError);
    });
  });
}
