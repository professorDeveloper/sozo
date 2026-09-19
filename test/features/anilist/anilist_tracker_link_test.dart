import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// What an automatic link records as the title's total.
///
/// AniList fills `episodes` for anime only: for everything that is read it is
/// null and the count lives in `chapters`. A link that stored `episodes` alone
/// therefore saved null for every manga, and the tracking row then read "0 of
/// 0" forever — no error anywhere, just a progress bar that never moved. The
/// rule is one line (`episodes ?? chapters`) and it is invisible when wrong,
/// which is exactly why it is worth a test.
void main() {
  group('the total an auto-match stores', () {
    test('is the chapter count for a title that is read', () async {
      final store = _store();
      final api = _Api(
        const AnilistMedia(
          id: 30002,
          type: 'MANGA',
          romajiTitle: 'Berserk',
          chapters: 380,
        ),
      );

      final id = await _tracker(api, store).reportEpisode(
        provider: 'mn:mangadex',
        contentUrl: 'https://mangadex.org/title/berserk',
        title: 'Berserk',
        episodeNumber: 1,
      );

      expect(id, 30002);
      final link = store.get('mn:mangadex', 'https://mangadex.org/title/berserk');
      expect(
        link?.totalEpisodes,
        380,
        reason: 'a manga counts in chapters, or the row reads 0 of 0 forever',
      );
      expect(
        api.searchedType,
        'MANGA',
        reason: 'a reader title is not in the anime index at all',
      );
    });

    test('is the episode count for a title that is watched', () async {
      final store = _store();
      final api = _Api(
        const AnilistMedia(
          id: 1,
          type: 'ANIME',
          romajiTitle: 'Cowboy Bebop',
          episodes: 26,
        ),
      );

      await _tracker(api, store).reportEpisode(
        provider: 'cloudstream',
        contentUrl: 'https://x.com/cowboy-bebop',
        title: 'Cowboy Bebop',
        episodeNumber: 1,
      );

      expect(
        store.get('cloudstream', 'https://x.com/cowboy-bebop')?.totalEpisodes,
        26,
      );
      expect(api.searchedType, 'ANIME');
    });

    test('prefers episodes when AniList happens to carry both', () async {
      // An anime with a manga's chapter count attached is rare but real, and
      // progress on a linked anime is counted in episodes — so the fallback
      // must stay a fallback rather than becoming a preference.
      final store = _store();
      final api = _Api(
        const AnilistMedia(
          id: 21,
          type: 'ANIME',
          romajiTitle: 'One Piece',
          episodes: 1122,
          chapters: 1100,
        ),
      );

      await _tracker(api, store).reportEpisode(
        provider: 'cloudstream',
        contentUrl: 'https://x.com/one-piece',
        title: 'One Piece',
        episodeNumber: 1,
      );

      expect(
        store.get('cloudstream', 'https://x.com/one-piece')?.totalEpisodes,
        1122,
      );
    });

    test('stays null when AniList knows neither count', () async {
      // Berserk really is filed with both fields empty. Null means "unknown"
      // and the row hides the total; a 0 would claim the title has no chapters.
      final store = _store();
      final api = _Api(
        const AnilistMedia(id: 30002, type: 'MANGA', romajiTitle: 'Berserk'),
      );

      await _tracker(api, store).reportEpisode(
        provider: 'mn:mangadex',
        contentUrl: 'https://mangadex.org/title/berserk',
        title: 'Berserk',
        episodeNumber: 1,
      );

      final link = store.get('mn:mangadex', 'https://mangadex.org/title/berserk');
      expect(link, isNotNull, reason: 'the link itself is still worth having');
      expect(link?.totalEpisodes, isNull);
    });
  });
}

AnilistLinkStore _store() => AnilistLinkStore(box: _Box());

AnilistTracker _tracker(_Api api, AnilistLinkStore store) =>
    AnilistTracker(service: _Service(api), links: store);

/// Answers one search with one title, and remembers which index was asked for.
class _Api implements AnilistApi {
  _Api(this.media);

  final AnilistMedia media;
  String? searchedType;

  @override
  Future<List<AnilistMedia>> searchMedia(
    String query, {
    int perPage = 20,
    String type = 'ANIME',
  }) async {
    searchedType = type;
    return [media];
  }

  /// Not on the list yet — the shape that lets the write through.
  @override
  Future<AnilistEntryState?> entryState({
    required String token,
    required int mediaId,
  }) async => null;

  @override
  Future<AnilistSaveResult> saveProgress({
    required String token,
    required int mediaId,
    int? progress,
    String? status,
    int? score,
  }) async => AnilistSaveResult(
    progress: progress ?? 0,
    status: status ?? AnilistStatus.current.value,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A connected account, without the Hive box and backend Dio a real one needs.
class _Service implements AnilistService {
  _Service(this._api);

  final AnilistApi _api;

  @override
  AnilistApi get api => _api;

  @override
  bool get isConnected => true;

  @override
  String? get token => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The two string values the link store keeps, held in memory.
class _Box implements Box<dynamic> {
  final Map<dynamic, dynamic> _values = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => _values[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
