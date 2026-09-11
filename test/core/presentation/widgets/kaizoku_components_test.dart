import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_badge.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_button.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_media_card.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';

void main() {
  group('KaizokuBadge', () {
    testWidgets('renders label in uppercase and applies variant', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KaizokuBadge(
              label: '4k uhd',
              variant: KaizokuBadgeVariant.amber,
            ),
          ),
        ),
      );

      expect(find.text('4K UHD'), findsOneWidget);
    });

    testWidgets('renders live badge indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KaizokuBadge(
              label: 'Live',
              variant: KaizokuBadgeVariant.live,
            ),
          ),
        ),
      );

      expect(find.text('LIVE'), findsOneWidget);
    });
  });

  group('KaizokuButton', () {
    testWidgets('fires onPressed when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaizokuButton(
              label: 'Play Now',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Play Now'));
      expect(tapped, isTrue);
    });

    testWidgets('shows loading indicator when loading is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaizokuButton(
              label: 'Save',
              loading: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });

  group('KaizokuMediaCard', () {
    testWidgets('renders title, subtitle, and badges', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KaizokuMediaCard(
              title: 'One Piece',
              subtitle: 'Episode 1115',
              imageUrl: null, // tests fallback gracefully
              badgeText: '1080P',
              tagText: 'ANIME',
              progress: 0.75,
            ),
          ),
        ),
      );

      expect(find.text('One Piece'), findsOneWidget);
      expect(find.text('Episode 1115'), findsOneWidget);
      expect(find.text('1080P'), findsOneWidget);
      expect(find.text('ANIME'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
