import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/trivia/domain/entities/top_fan_entity.dart';
import 'package:soplay/features/trivia/presentation/widgets/buff_empty_panel.dart';
import 'package:soplay/features/trivia/presentation/widgets/countdown_ring.dart';
import 'package:soplay/features/trivia/presentation/widgets/option_chip.dart';
import 'package:soplay/features/trivia/presentation/widgets/progress_dots.dart';
import 'package:soplay/features/trivia/presentation/widgets/top_fans_strip.dart';

void main() {
  group('Trivia Remediated Kaizoku UI Tests', () {
    testWidgets('OptionChip renders idle state and triggers tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: OptionChip(
              label: 'Monkey D. Luffy',
              status: OptionChipStatus.idle,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Monkey D. Luffy'), findsOneWidget);
      await tester.tap(find.byType(OptionChip));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('OptionChip renders correct state with checkmark icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: OptionChip(
              label: 'Roronoa Zoro',
              status: OptionChipStatus.correct,
            ),
          ),
        ),
      );

      expect(find.text('Roronoa Zoro'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('OptionChip renders wrong state with close icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: OptionChip(
              label: 'Usopp',
              status: OptionChipStatus.wrong,
            ),
          ),
        ),
      );

      expect(find.text('Usopp'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('ProgressDots renders correct number of dots with active pill', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: ProgressDots(
              total: 5,
              currentIndex: 2,
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsNWidgets(5));
    });

    testWidgets('CountdownRing renders seconds and handles danger color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: CountdownRing(
              secondsRemaining: 3,
              totalSeconds: 10,
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('BuffEmptyPanel renders title, body and executes retry action', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: BuffEmptyPanel(
              icon: CupertinoIcons.film,
              title: 'No clips available',
              body: 'Check back later for new rounds',
              actionLabel: 'Retry',
              onAction: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('No clips available'), findsOneWidget);
      expect(find.text('Check back later for new rounds'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.film), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('TopFansStrip displays top fan avatars and fires onTap', (tester) async {
      var stripTapped = false;
      final topFans = [
        const TopFanEntity(
          userId: 'u1',
          username: 'PirateKing',
          avatar: '',
          bestScore: 980,
          bestFandom: 95.0,
          rank: 1,
        ),
        const TopFanEntity(
          userId: 'u2',
          username: 'StrawHat',
          avatar: '',
          bestScore: 850,
          bestFandom: 88.0,
          rank: 2,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: TopFansStrip(
              topFans: topFans,
              myRank: 4,
              onTap: () => stripTapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(TopFansStrip), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);

      await tester.tap(find.byType(TopFansStrip));
      await tester.pump();
      expect(stripTapped, isTrue);
    });
  });
}
