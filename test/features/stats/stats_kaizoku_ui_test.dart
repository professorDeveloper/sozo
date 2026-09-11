import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/stats/presentation/watch_stats_page.dart';

void main() {
  group('Stats Remediated Kaizoku UI Tests', () {
    testWidgets('WatchStatsPage renders empty view when total seconds is zero', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: WatchStatsPage(),
          ),
        ),
      );

      expect(find.byType(WatchStatsPage), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
    });
  });
}
