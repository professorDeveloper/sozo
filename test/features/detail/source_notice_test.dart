// What the app does with a source that says, in a field, that it cannot play a
// title. Verified against production on 2026-11-02: both bodies below are the
// live ones, copied from
//   GET /api/contents/episodes?provider=asilmedia&url=.../18717-apokalipsis-z-...
//   GET /api/contents/media?provider=asilmedia&ref=.../18717-apokalipsis-z-...
// so the parsing here is tested against the shape that actually arrives rather
// than against a shape this test invented.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/detail/data/repositories/detail_repository_impl.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/source_notice.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_info.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/core/trailer/trailer_query.dart';
import 'package:soplay/core/trailer/trailer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Hive implements HiveService {
  @override
  String getCurrentProvider() => 'asilmedia';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mangayomi implements MangayomiBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements HistoryService {
  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  @override
  HistoryItem? get(String contentUrl, {int? episodeIndex, int? episodeNumber}) =>
      null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The header carries a tracking row and a trailer button, neither of which is
/// what this test is about: connected to nothing, they draw nothing.
class _Anilist implements AnilistService {
  @override
  bool get isConnected => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mal implements MalService {
  @override
  bool get isConnected => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Trailer implements TrailerService {
  @override
  Future<TrailerResult?> resolveFor(TrailerQuery query) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers every request with [status] and [body], so the repository meets the
/// error the live API returns rather than a Dio timeout.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Map<String, Object?> body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

DetailRepositoryImpl _repo(int status, Map<String, Object?> body) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'))
    ..httpClientAdapter = _Adapter(status, body);
  return DetailRepositoryImpl(
    DetailDataSource(dio: dio),
    hive: _Hive(),
    mangayomi: _Mangayomi(),
  );
}

const _detail = DetailEntity(
  provider: 'asilmedia',
  contentId: '18717',
  contentUrl: 'https://asilmedia.org/18717-apokalipsis-z',
  title: 'Apokalipsis Z',
  description: '',
  thumbnail: null,
  year: null,
  duration: null,
  country: null,
  director: null,
  genres: [],
  cast: [],
  likes: 0,
  dislikes: 0,
  isSerial: false,
  isFavorited: null,
  screenshots: [],
  related: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('reading the reason', () {
    test('a bare code and a code at the head of a message are the same '
        'reason', () {
      // The episodes response sends the code in a field; a failed resolve has
      // to carry it at the head of `message`, because the API's error handler
      // serialises only that. One reader, both shapes.
      expect(SourceNotice.read('SOURCE_MOVED_TO_APP'), SourceNotice.movedToApp);
      expect(
        SourceNotice.read(
          'SOURCE_MOVED_TO_APP: asilmedia serves this title only in its own app',
        ),
        SourceNotice.movedToApp,
      );
      expect(SourceNotice.read('SOURCE_NO_PLAYER'), SourceNotice.noPlayer);
      expect(
        SourceNotice.read(
          'SOURCE_IS_SERIES: this asilmedia page is a series; ask '
          '/contents/episodes for an episode ref',
        ),
        SourceNotice.isSeries,
      );
    });

    test('anything else is no reason at all', () {
      // Better the plain failure than a confident wrong explanation.
      expect(SourceNotice.read(null), isNull);
      expect(SourceNotice.read(''), isNull);
      expect(SourceNotice.read('Video URL aniqlanmadi'), isNull);
      expect(SourceNotice.read('SOURCE_SOMETHING_NEW: whatever'), isNull);
    });

    test('a series still plays; the two dead ends do not', () {
      expect(SourceNotice.isSeries.playable, isTrue);
      expect(SourceNotice.movedToApp.playable, isFalse);
      expect(SourceNotice.noPlayer.playable, isFalse);
    });
  });

  test('an episodes response that says "not playable" arrives saying so', () {
    final playback = PlaybackModel.fromJson({
      'provider': 'asilmedia',
      'contentUrl': 'https://asilmedia.org/18717-apokalipsis-z',
      'isSerial': false,
      'videoSources': <Object?>[],
      'playerSrc': null,
      'playable': false,
      'playableReason': 'SOURCE_MOVED_TO_APP',
      'noticeCode': 'SOURCE_MOVED_TO_APP',
      'providerNotice':
          "asilmedia: Ushbu filmni Yangi TV ilovasidan O'zbek tilida tomosha "
          'qiling.',
      'episodes': <Object?>[],
    });
    expect(playback.playable, isFalse);
    expect(playback.notice, SourceNotice.movedToApp);
    // The ordering a sort does must not lose it: the page reads `playable` off
    // whatever the repository hands back, which is the sorted copy.
    expect(playback.copyWithEpisodes(const []).playable, isFalse);
    expect(playback.copyWithEpisodes(const []).notice, SourceNotice.movedToApp);
  });

  test('a source that says nothing is a source with nothing wrong', () {
    final playback = PlaybackModel.fromJson({
      'provider': 'kinoshka',
      'contentUrl': 'https://example.invalid/1',
      'isSerial': false,
      'playerSrc': 'https://cdn.example.invalid/v.mp4',
      'episodes': <Object?>[],
    });
    expect(playback.playable, isTrue);
    expect(playback.notice, isNull);
  });

  test('a failed resolve comes back with the reason, not with "Video URL '
      'aniqlanmadi"', () async {
    final result = await _repo(422, {
      'message': 'SOURCE_MOVED_TO_APP: asilmedia serves this title only in '
          'its own app',
      'providerNotice': 'asilmedia: Ushbu filmni Yangi TV ilovasidan ...',
    }).resolveMedia(ref: 'https://asilmedia.org/18717', provider: 'asilmedia');

    final error = (result as Failure).error;
    expect(error, isA<SourceNoticeException>());
    expect((error as SourceNoticeException).notice, SourceNotice.movedToApp);
    expect(error.providerNotice, contains('Yangi TV'));
  });

  test('a 422 with no reason in it is still the plain failure', () async {
    final result = await _repo(422, {
      'message': 'no stream',
    }).resolveMedia(ref: 'x', provider: 'asilmedia');
    final error = (result as Failure).error;
    expect(error, isNot(isA<SourceNoticeException>()));
  });

  testWidgets('a title the source called unplayable offers another source '
      'instead of Play', (tester) async {
    getIt.registerSingleton<HistoryService>(_History());
    getIt.registerSingleton<AnilistService>(_Anilist());
    getIt.registerSingleton<MalService>(_Mal());
    getIt.registerSingleton<TrailerService>(_Trailer());
    addTearDown(getIt.reset);

    Future<void> pump(SourceNotice? unplayable) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          startLocale: const Locale('en'),
          path: 'assets/translations',
          assetLoader: const _Translations(),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DetailContentHeader(
                    detail: _detail,
                    onPrimaryAction: () {},
                    playButtonKey: const Key('play'),
                    onFindSource: () {},
                    unplayable: unplayable,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await pump(null);
    expect(find.text('Play'), findsOneWidget);

    await pump(SourceNotice.movedToApp);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Find other sources'), findsOneWidget);
    expect(
      find.textContaining('moved this title into its own app'),
      findsOneWidget,
    );
  });
}
