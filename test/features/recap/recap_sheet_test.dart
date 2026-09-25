import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/recap/data/recap_remote_data_source.dart';
import 'package:soplay/features/recap/domain/recap.dart';
import 'package:soplay/features/recap/presentation/recap_sheet.dart';

const _request = RecapRequest(
  provider: 'asilmedia',
  contentUrl: 'https://example.com/show',
  title: 'Local title',
  episode: 5,
);

const _recap = Recap(
  text: 'The crew escaped.\n\nThen the storm hit.',
  items: [
    RecapItem(season: 1, name: 'Season one', overview: 'Season blurb'),
    RecapItem(season: 2, episode: 4, name: 'Storm', overview: 'Storm blurb'),
  ],
  episode: 5,
  title: 'Server title',
  season: 2,
  upToEpisode: 4,
  attribution: 'TMDB',
  fromModel: true,
);

class _FakeSource extends RecapRemoteDataSource {
  _FakeSource() : super(dio: Dio());

  final List<Completer<Recap>> calls = [];

  @override
  Future<Recap> load(RecapRequest request, {required String lang}) {
    final c = Completer<Recap>();
    calls.add(c);
    return c.future;
  }
}

Future<void> _pump(WidgetTester tester, _FakeSource source) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecapSheet(request: _request, lang: 'en', source: source),
        ),
      ),
    );

void main() {
  testWidgets('loading, then the recap, what it covers and the credit', (
    tester,
  ) async {
    final source = _FakeSource();
    await _pump(tester, source);

    expect(find.text('recap.loading'), findsOneWidget);
    expect(find.text('Local title'), findsOneWidget);

    source.calls.single.complete(_recap);
    await tester.pumpAndSettle();

    expect(find.text('Server title'), findsOneWidget);
    expect(find.text('The crew escaped.'), findsOneWidget);
    expect(find.text('Then the storm hit.'), findsOneWidget);
    expect(find.text('recap.spoiler_safe'), findsOneWidget);
    expect(find.text('recap.covers'), findsOneWidget);
    expect(find.text('Season one'), findsOneWidget);
    expect(find.text('Storm'), findsOneWidget);
    expect(find.text('recap.source · recap.ai_note'), findsOneWidget);
    expect(find.text('recap.loading'), findsNothing);
  });

  testWidgets('no data is said plainly, with no retry', (tester) async {
    final source = _FakeSource();
    await _pump(tester, source);

    source.calls.single.completeError(const RecapUnavailable());
    await tester.pumpAndSettle();

    expect(find.text('recap.unavailable_title'), findsOneWidget);
    expect(find.text('general.retry'), findsNothing);
  });

  testWidgets('a failure offers a retry that asks again', (tester) async {
    final source = _FakeSource();
    await _pump(tester, source);

    source.calls.single.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('recap.error'), findsOneWidget);

    await tester.tap(find.text('general.retry'));
    await tester.pump();
    expect(source.calls, hasLength(2));
    expect(find.text('recap.loading'), findsOneWidget);

    source.calls.last.complete(_recap);
    await tester.pumpAndSettle();
    expect(find.text('The crew escaped.'), findsOneWidget);
  });
}
