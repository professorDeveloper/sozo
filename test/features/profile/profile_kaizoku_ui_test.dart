import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/discord/discord_activity.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:soplay/features/profile/presentation/widgets/discord_preview_card.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_calendar_heatmap.dart';

void main() {
  group('Milestone 2.2 Profile & Settings Widgets', () {
    testWidgets('SettingsNavTile renders title, value and executes onTap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: SettingsNavTile(
              icon: Icons.history_rounded,
              title: 'Watch History',
              value: '14',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Watch History'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);

      await tester.tap(find.byType(SettingsNavTile));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('SettingsSwitchTile toggles value and triggers callback', (tester) async {
      var switched = false;
      bool currentValue = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                backgroundColor: KaizokuColors.cyberObsidian,
                body: SettingsSwitchTile(
                  icon: Icons.notifications_active_rounded,
                  title: 'Push Notifications',
                  value: currentValue,
                  onChanged: (val) {
                    switched = true;
                    setState(() => currentValue = val);
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Push Notifications'), findsOneWidget);
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(switched, isTrue);
      expect(currentValue, isTrue);
    });
  });

  group('Milestone 2.2 Auth Widgets (Kaizoku Theme)', () {
    testWidgets('AuthTextField updates controller and handles input', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: AuthTextField(
              controller: controller,
              hint: 'Enter your username',
              icon: Icons.person_outline_rounded,
            ),
          ),
        ),
      );

      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pirate_king');
      await tester.pump();

      expect(controller.text, equals('pirate_king'));
    });

    testWidgets('AuthErrorBanner renders error message and hides when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: Column(
              children: [
                AuthErrorBanner(message: 'Invalid credentials'),
                AuthErrorBanner(message: null),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Invalid credentials'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('AuthPrimaryButton displays label and responds to tap', (tester) async {
      var submitted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: AuthPrimaryButton(
              label: 'Sign In',
              onPressed: () => submitted = true,
            ),
          ),
        ),
      );

      expect(find.text('Sign In'), findsOneWidget);
      await tester.tap(find.byType(AuthPrimaryButton));
      await tester.pump();

      expect(submitted, isTrue);
    });
  });

  group('Milestone 2.2 Discord & Streak Widgets', () {
    testWidgets('DiscordPreviewCard renders Kaizoku branding and connection status', (tester) async {
      final activity = DiscordActivity(
        title: 'One Piece',
        subtitle: 'Episode 1071',
        startedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DiscordPreviewCard(
              activity: activity,
              connected: true,
              appName: 'Kaizoku',
            ),
          ),
        ),
      );

      expect(find.text('Kaizoku'), findsOneWidget);
      expect(find.text('One Piece'), findsOneWidget);
      expect(find.text('Episode 1071'), findsOneWidget);
    });

    testWidgets('StreakCalendarHeatmap renders 35 heatmap cells', (tester) async {
      final sampleDays = [
        StreakDay(date: '2026-03-01', active: true),
        StreakDay(date: '2026-03-02', active: false),
        StreakDay(date: '2026-03-03', active: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: StreakCalendarHeatmap(days: sampleDays),
          ),
        ),
      );

      expect(find.byType(StreakCalendarHeatmap), findsOneWidget);
      // Heatmap renders an AspectRatio per day cell (35 total: 5 rows x 7 cols)
      expect(find.byType(AspectRatio), findsNWidgets(35));
    });
  });
}
