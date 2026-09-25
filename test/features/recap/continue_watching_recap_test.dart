import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/presentation/widgets/home_history_section.dart';

HistoryItem _item(String url, {bool isSerial = true, int? episode}) =>
    HistoryItem(
      contentUrl: url,
      provider: 'asilmedia',
      title: 'Title $url',
      isSerial: isSerial,
      episodeNumber: episode,
      positionMs: 1000,
      durationMs: 100000,
      watchedAt: 1,
    );

Future<void> _longPress(WidgetTester tester, HistoryItem item) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: HistorySection(items: [item])),
    ),
  );
  await tester.longPress(find.text(item.title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a series part-way in offers a recap', (tester) async {
    await _longPress(tester, _item('a', episode: 4));
    expect(find.text('recap.action'), findsOneWidget);
    expect(find.text('player.resume'), findsOneWidget);
  });

  testWidgets('episode 1 has nothing to recap', (tester) async {
    await _longPress(tester, _item('b', episode: 1));
    expect(find.text('recap.action'), findsNothing);
    expect(find.text('player.resume'), findsOneWidget);
  });

  testWidgets('a film has no recap', (tester) async {
    await _longPress(tester, _item('c', isSerial: false));
    expect(find.text('recap.action'), findsNothing);
  });
}
