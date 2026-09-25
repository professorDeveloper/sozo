import 'dart:async';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/domain/repositories/my_list_repository.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

enum ImportSource { anilist, mal }

/// What an import will do: titles to follow and titles to put in My List.
class ImportPlan {
  const ImportPlan({
    this.follows = const [],
    this.listAdds = const [],
    this.unmatched = 0,
  });

  final List<FollowedTitle> follows;
  final List<FavoriteEntity> listAdds;

  /// Rows that could not be tied to an AniList title and were left out.
  final int unmatched;

  int get length => follows.length + listAdds.length;
}

/// One step of a running import, for the screen showing it.
class ImportProgress {
  const ImportProgress({
    required this.total,
    required this.done,
    required this.followed,
    required this.listed,
    this.cover,
    this.title,
    this.finished = false,
    this.unmatched = 0,
  });

  final int total;
  final int done;

  /// Newly followed and newly listed; titles already there are not counted.
  final int followed;
  final int listed;
  final String? cover;
  final String? title;
  final bool finished;
  final int unmatched;
}

/// Where imported titles go. [FollowService] and My List in the app, a fake
/// in tests.
abstract class LibraryImportSink {
  bool isFollowed(String contentUrl);
  Future<void> follow(FollowedTitle title);
  bool isListed(String contentUrl);
  Future<void> addToList(FavoriteEntity entry);
}

class AppLibraryImportSink implements LibraryImportSink {
  AppLibraryImportSink({
    required this.follows,
    required this.myList,
    required this.myListLocal,
  });

  final FollowService follows;
  final MyListRepository myList;
  final MyListLocalDataSource myListLocal;

  @override
  bool isFollowed(String contentUrl) => follows.isFollowed(contentUrl);

  @override
  Future<void> follow(FollowedTitle title) => follows.follow(title);

  @override
  bool isListed(String contentUrl) => myListLocal.isFavoriteByUrl(contentUrl);

  @override
  Future<void> addToList(FavoriteEntity entry) => myList.addFavorite(entry);
}

bool _following(String status) => status == 'CURRENT' || status == 'REPEATING';

/// The catalogue an AniList entry opens in, by its shelf.
Catalogue anilistCatalogueFor(AnilistMedia media) {
  if (!media.isManga) return Catalogue.anilist;
  return media.format == 'NOVEL'
      ? Catalogue.anilistNovel
      : Catalogue.anilistManga;
}

String anilistUrlFor(AnilistMedia media) {
  final site = media.siteUrl;
  if (site != null && site.isNotEmpty) return site;
  return 'https://anilist.co/${media.isManga ? 'manga' : 'anime'}/${media.id}';
}

FollowedTitle _followFor(AnilistMedia m, int now) {
  final catalogue = anilistCatalogueFor(m);
  return FollowedTitle(
    contentUrl: anilistUrlFor(m),
    provider: catalogue.id,
    title: m.displayTitle,
    thumbnail: m.coverImage ?? '',
    year: m.seasonYear,
    addedAt: now,
    anilistId: m.id,
    mode: catalogue.mode.id,
  );
}

FavoriteEntity _listEntryFor(AnilistMedia m) => FavoriteEntity(
  provider: anilistCatalogueFor(m).id,
  contentUrl: anilistUrlFor(m),
  title: m.displayTitle,
  thumbnail: m.coverImage ?? '',
);

/// AniList's lists as follows and My List entries.
///
/// Watching or rewatching is followed, planning goes to My List, and the rest
/// — completed, paused, dropped — is history rather than something to be told
/// about, so it is left alone.
ImportPlan planAnilistImport(
  Iterable<AnilistListEntry> entries, {
  bool allowAdult = false,
  int? now,
}) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  final follows = <String, FollowedTitle>{};
  final adds = <String, FavoriteEntity>{};
  for (final e in entries) {
    final m = e.media;
    if (m.id <= 0 || (m.isAdult && !allowAdult)) continue;
    final url = anilistUrlFor(m);
    if (_following(e.status)) {
      follows.putIfAbsent(url, () => _followFor(m, at));
    } else if (e.status == 'PLANNING') {
      adds.putIfAbsent(url, () => _listEntryFor(m));
    }
  }
  for (final url in follows.keys) {
    adds.remove(url);
  }
  return ImportPlan(
    follows: follows.values.toList(),
    listAdds: adds.values.toList(),
  );
}

/// MyAnimeList's anime list, tied to AniList through `idMal` so every title
/// opens in the AniList catalogue and carries its AniList id. A row AniList
/// has no match for is counted in [ImportPlan.unmatched] and skipped: without
/// it there is no catalogue page to open.
ImportPlan planMalImport(
  Iterable<MalListEntry> entries,
  Map<int, AnilistMedia> byMalId, {
  bool allowAdult = false,
  int? now,
}) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  final follows = <String, FollowedTitle>{};
  final adds = <String, FavoriteEntity>{};
  var unmatched = 0;
  for (final e in entries) {
    final watching = e.status == MalStatus.watching || e.isRewatching;
    final planning = e.status == MalStatus.planToWatch;
    if (!watching && !planning) continue;
    final m = byMalId[e.anime.id];
    if (m == null) {
      unmatched++;
      continue;
    }
    if (m.isAdult && !allowAdult) continue;
    final url = anilistUrlFor(m);
    if (watching) {
      follows.putIfAbsent(url, () => _followFor(m, at));
    } else {
      adds.putIfAbsent(url, () => _listEntryFor(m));
    }
  }
  for (final url in follows.keys) {
    adds.remove(url);
  }
  return ImportPlan(
    follows: follows.values.toList(),
    listAdds: adds.values.toList(),
    unmatched: unmatched,
  );
}

/// Brings an AniList or MyAnimeList library into Sozo.
///
/// Safe to run again: a title already followed or already in My List is
/// passed over, so a second import only adds what is new on the tracker.
class LibraryImportService {
  LibraryImportService({
    required this.sink,
    required this.anilistLibrary,
    required this.malLibrary,
    required this.anilistByMalIds,
    this.allowAdult,
  });

  factory LibraryImportService.fromApp() {
    final anilist = getIt<AnilistService>();
    final mal = getIt<MalService>();
    final hive = getIt<HiveService>();
    return LibraryImportService(
      sink: AppLibraryImportSink(
        follows: getIt<FollowService>(),
        myList: getIt<MyListRepository>(),
        myListLocal: getIt<MyListLocalDataSource>(),
      ),
      anilistLibrary: (type) => anilist.library(type: type),
      malLibrary: () async {
        final token = mal.token;
        if (token == null) throw StateError('MyAnimeList is not connected');
        return mal.api.animeList(token);
      },
      anilistByMalIds: (ids) => anilist.api.mediaByMalIds(ids),
      allowAdult: () => hive.showAdultContent,
    );
  }

  final LibraryImportSink sink;
  final Future<List<AnilistListEntry>> Function(String type) anilistLibrary;
  final Future<List<MalListEntry>> Function() malLibrary;
  final Future<Map<int, AnilistMedia>> Function(List<int> malIds)
  anilistByMalIds;
  final bool Function()? allowAdult;

  Future<ImportPlan> plan(ImportSource source) async {
    final adult = allowAdult?.call() ?? false;
    switch (source) {
      case ImportSource.anilist:
        final lists = await Future.wait([
          anilistLibrary('ANIME'),
          anilistLibrary('MANGA'),
        ]);
        return planAnilistImport(lists.expand((l) => l), allowAdult: adult);
      case ImportSource.mal:
        final entries = await malLibrary();
        final wanted = [
          for (final e in entries)
            if (e.status == MalStatus.watching ||
                e.isRewatching ||
                e.status == MalStatus.planToWatch)
              e.anime.id,
        ];
        final byMal = wanted.isEmpty
            ? const <int, AnilistMedia>{}
            : await anilistByMalIds(wanted);
        return planMalImport(entries, byMal, allowAdult: adult);
    }
  }

  /// Runs [source]'s import, reporting each title as it lands. Errors reach
  /// the stream's listener; nothing is half-written, each title stands alone.
  Stream<ImportProgress> run(ImportSource source) async* {
    final plan = await this.plan(source);
    yield* apply(plan);
  }

  Stream<ImportProgress> apply(ImportPlan plan) async* {
    final total = plan.length;
    var done = 0;
    var followed = 0;
    var listed = 0;
    yield ImportProgress(
      total: total,
      done: 0,
      followed: 0,
      listed: 0,
      unmatched: plan.unmatched,
    );
    for (final f in plan.follows) {
      done++;
      if (!sink.isFollowed(f.contentUrl)) {
        await sink.follow(f);
        followed++;
      }
      yield ImportProgress(
        total: total,
        done: done,
        followed: followed,
        listed: listed,
        cover: f.thumbnail.isEmpty ? null : f.thumbnail,
        title: f.title,
        unmatched: plan.unmatched,
      );
    }
    for (final a in plan.listAdds) {
      done++;
      if (!sink.isListed(a.contentUrl) && !sink.isFollowed(a.contentUrl)) {
        await sink.addToList(a);
        listed++;
      }
      yield ImportProgress(
        total: total,
        done: done,
        followed: followed,
        listed: listed,
        cover: a.thumbnail.isEmpty ? null : a.thumbnail,
        title: a.title,
        unmatched: plan.unmatched,
      );
    }
    yield ImportProgress(
      total: total,
      done: total,
      followed: followed,
      listed: listed,
      finished: true,
      unmatched: plan.unmatched,
    );
  }
}
