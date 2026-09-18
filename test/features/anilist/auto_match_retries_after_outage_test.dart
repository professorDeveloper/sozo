// A title is only given up on when AniList says so — never when it is silent.
//
// `_autoMatchFailed` is consulted before any lookup is attempted, so whatever
// goes into it is final for the life of the process. It used to be fed by a
// matcher that returned `null` both for "AniList has nothing like this" and for
// "the request never landed". One failed lookup — a tunnel, a rate limit, a
// 502 — therefore stopped the title auto-linking for the rest of the session,
// and no amount of connectivity afterwards brought it back.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// Counts searches, and answers each one however the test says to.
class _ScriptedApi implements AnilistApi {
  _ScriptedApi(this.answers);

  /// One entry per expected call. A thrown value stands for a request that
  /// never landed; a list stands for what AniList sent back.
  final List<Object> answers;
  final List<String> searched = [];

  @override
  Future<List<AnilistMedia>> searchMedia(
    String query, {
    int perPage = 20,
    String type = 'ANIME',
  }) async {
    searched.add(query);
    final answer = answers[searched.length - 1];
    if (answer is Exception) throw answer;
    return (answer as List).cast<AnilistMedia>();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Connected, with a scripted catalogue behind it. Subclassed rather than
/// faked whole: `isConnected` is the only thing the tracker asks it that a
/// test cannot set up honestly, because a real token only arrives through the
/// browser.
class _ConnectedService extends AnilistService {
  _ConnectedService({
    required super.backendDio,
    required super.hive,
    required super.links,
    required super.api,
  });

  @override
  bool get isConnected => true;
}

class _Hive implements HiveService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box box;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_automatch');
    box = await Hive.openBox('sozo_automatch_links');
  });

  tearDownAll(() async => Hive.close());

  setUp(() async => box.clear());

  AnilistTracker trackerOver(_ScriptedApi api) {
    final links = AnilistLinkStore(box: box);
    return AnilistTracker(
      service: _ConnectedService(
        backendDio: Dio(),
        hive: _Hive(),
        links: links,
        api: api,
      ),
      links: links,
    );
  }

  Future<void> watch(AnilistTracker tracker, int episode) => tracker
      .reportEpisode(
        provider: 'someext',
        contentUrl: 'https://example.test/frieren',
        title: 'Frieren',
        episodeNumber: episode,
      )
      .then((_) {});

  test('an outage does not make an unlinked title permanent', () async {
    // Episode 1 is watched offline; episode 2 with the connection back.
    final api = _ScriptedApi([
      Exception('SocketException: Failed host lookup'),
      <AnilistMedia>[],
    ]);
    final tracker = trackerOver(api);

    await watch(tracker, 1);
    await watch(tracker, 2);

    expect(
      api.searched,
      hasLength(2),
      reason:
          'the second episode never even asked — the first failure had been '
          'recorded as "this title has no match"',
    );
  });

  test('but a real miss is only paid for once', () async {
    // The optimisation the set exists for, which the fix must not undo:
    // AniList answered, nothing matched, and every later episode of the same
    // show skips the search.
    final api = _ScriptedApi([
      <AnilistMedia>[],
      <AnilistMedia>[], // never reached if the set works
    ]);
    final tracker = trackerOver(api);

    await watch(tracker, 1);
    await watch(tracker, 2);

    expect(api.searched, hasLength(1));
  });

  test('an answer that simply contains no match is settled too', () async {
    // AniList replied with results, none of which is this title. That is a
    // fact about the title, not about the network.
    final api = _ScriptedApi([
      const <AnilistMedia>[AnilistMedia(id: 1, romajiTitle: 'Something Else')],
      const <AnilistMedia>[],
    ]);
    final tracker = trackerOver(api);

    await watch(tracker, 1);
    await watch(tracker, 2);

    expect(api.searched, hasLength(1));
  });

  test('and a title that matches is linked and not searched again', () async {
    final api = _ScriptedApi([
      const <AnilistMedia>[AnilistMedia(id: 52991, romajiTitle: 'Frieren')],
      const <AnilistMedia>[],
    ]);
    final tracker = trackerOver(api);

    await watch(tracker, 1);

    expect(
      tracker.links.mediaIdFor('someext', 'https://example.test/frieren'),
      52991,
    );

    await watch(tracker, 2);
    expect(api.searched, hasLength(1), reason: 'the link answers from now on');
  });
}
