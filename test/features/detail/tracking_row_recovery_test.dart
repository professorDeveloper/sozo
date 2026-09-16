import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/record_info.dart';
import 'package:soplay/features/detail/presentation/widgets/tracking_row.dart';
import 'package:soplay/features/mal/data/mal_api.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';

/// A tracker that is reachable or not, on demand, and that can be left
/// mid-write — the two states the row used to have no way of showing.
class _Api implements AnilistApi {
  int reads = 0;
  bool readFails = false;
  Completer<AnilistSaveResult>? pendingWrite;

  @override
  Future<AnilistEntryState?> entryState({
    required String token,
    required int mediaId,
  }) async {
    reads++;
    if (readFails) throw Exception('no route to host');
    return const AnilistEntryState(
      onList: true,
      progress: 3,
      status: 'CURRENT',
      totalEpisodes: 12,
    );
  }

  @override
  Future<AnilistSaveResult> saveProgress({
    required String token,
    required int mediaId,
    int? progress,
    String? status,
    int? score,
  }) {
    final completer = Completer<AnilistSaveResult>();
    pendingWrite = completer;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Anilist implements AnilistService {
  _Anilist(this.api);

  @override
  final AnilistApi api;

  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  String? get token => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The MyAnimeList half of the row is a second copy of the same shape, down to
/// the retry, so it is worth its own reachable-or-not tracker.
class _MalApi implements MalApi {
  int reads = 0;
  bool readFails = false;

  @override
  Future<MalEntryState?> entryState({
    required String token,
    required int animeId,
  }) async {
    reads++;
    if (readFails) throw Exception('no route to host');
    return const MalEntryState(
      watchedEpisodes: 3,
      status: MalStatus.watching,
      totalEpisodes: 12,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mal implements MalService {
  _Mal(this.api);

  @override
  final MalApi api;

  bool connected = false;

  @override
  bool get isConnected => connected;

  @override
  String? get token => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _detail = DetailEntity(
  provider: 'fixture',
  contentId: '1',
  contentUrl: 'https://example.invalid/1',
  title: 'Fixture',
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
  isSerial: true,
  isFavorited: null,
  screenshots: [],
  related: [],
  record: RecordInfo(anilistId: 42, malId: 7),
);

Future<void> _pumpRow(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: TrackingRow(detail: _detail),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The row itself, not the − + buttons inside it: the whole line is the tap
/// target, and in the failed state it is the only one.
final _row = find.byType(InkWell).first;

/// The tracker's own line, located by what it says rather than by widget
/// order, because MyAnimeList's logo is itself a scrap of text.
Finder _line(String name) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().startsWith(name),
);

/// Everything a screen reader would read out for the row, one announcement per
/// line.
List<String> _spokenRow(WidgetTester tester, String name) =>
    tester.getSemantics(_line(name)).label.split('\n');

/// What the line actually paints.
///
/// Read off the span rather than through `find.text`, which matches only Text
/// and EditableText: the name and the status are two spans of one RichText, so
/// a find.text assertion about this line passes whatever the line says — including
/// against the very code it is meant to catch.
String _printedLine(WidgetTester tester, String name) =>
    tester.widget<RichText>(_line(name)).text.toPlainText();

void main() {
  late _Api api;
  late _MalApi malApi;
  late _Anilist anilist;
  late _Mal mal;

  setUp(() {
    api = _Api();
    malApi = _MalApi();
    anilist = _Anilist(api);
    mal = _Mal(malApi);
    getIt.registerSingleton<AnilistService>(anilist);
    getIt.registerSingleton<MalService>(mal);
  });
  tearDown(() async => getIt.reset());

  testWidgets('a row whose state failed to load offers the read again', (
    tester,
  ) async {
    api.readFails = true;
    await _pumpRow(tester);
    expect(api.reads, 1);
    // The name and nothing else. The em-dash this used to print was a status
    // nobody could act on, and tapping it opened a sheet built on nothing; the
    // separator goes with it, because "AniList  ·  " promises a value the row
    // has not got.
    expect(_printedLine(tester, 'AniList'), 'AniList');
    // No counter either — there is no position to step from.
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);

    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(api.reads, 2, reason: 'the row is the retry');
  });

  testWidgets('a failed row claims no position it does not have', (
    tester,
  ) async {
    api.readFails = true;
    await _pumpRow(tester);
    // The em-dash was a value: a screen reader read the row as though it knew
    // where the viewer was on this title, which is the one thing it did not.
    // What is left is the tracker's name and the way to try again.
    // The tracker's name and nothing after it: a status appended here reads as
    // "AniList, Watching 5 of 12", which is exactly the claim the row cannot
    // make when the read never landed.
    final spoken = _spokenRow(tester, 'AniList');
    expect(spoken, contains('AniList'));
    expect(spoken.join(), isNot(contains('—')));
    expect(spoken.join(), isNot(contains('·')));
  });

  testWidgets('a retry that succeeds leaves the row on the real number', (
    tester,
  ) async {
    api.readFails = true;
    await _pumpRow(tester);
    api.readFails = false;

    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(find.text('3/12'), findsOneWidget);
  });

  testWidgets('an in-flight write is visible on the row', (tester) async {
    await _pumpRow(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    // Optimistic: the number has already moved, and the hairline under it is
    // what says AniList has not agreed yet.
    expect(find.text('4/12'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    api.pendingWrite!.complete(
      const AnilistSaveResult(progress: 4, status: 'CURRENT'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('4/12'), findsOneWidget);
  });

  group('MyAnimeList', () {
    // One row on screen, not two: the MAL line is the one under test, and the
    // AniList line would otherwise be the first InkWell every tap lands on.
    setUp(() {
      anilist.connected = false;
      mal.connected = true;
    });

    testWidgets('a row whose state failed to load offers the read again', (
      tester,
    ) async {
      malApi.readFails = true;
      await _pumpRow(tester);
      expect(malApi.reads, 1);
      expect(_printedLine(tester, 'MyAnimeList'), 'MyAnimeList');
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_rounded), findsNothing);

      await tester.tap(_row);
      await tester.pumpAndSettle();
      expect(malApi.reads, 2, reason: 'the row is the retry');
    });

    testWidgets('a failed row claims no position it does not have', (
      tester,
    ) async {
      malApi.readFails = true;
      await _pumpRow(tester);
      final spoken = _spokenRow(tester, 'MyAnimeList');
      expect(spoken, contains('MyAnimeList'));
      expect(spoken.join(), isNot(contains('—')));
      expect(spoken.join(), isNot(contains('·')));
    });

    testWidgets('a retry that succeeds leaves the row on the real number', (
      tester,
    ) async {
      malApi.readFails = true;
      await _pumpRow(tester);
      malApi.readFails = false;

      await tester.tap(_row);
      await tester.pumpAndSettle();
      expect(find.text('3/12'), findsOneWidget);
    });
  });
}
