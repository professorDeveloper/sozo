import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_media_card.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/presentation/widgets/favorite_card.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

void main() {
  group('FavoriteCard Kaizoku UI & Behavior Tests', () {
    testWidgets('triggers onTap callback when tapped', (tester) async {
      var tapped = false;
      final item = FavoriteEntity(
        contentUrl: 'https://example.com/anime/1',
        title: 'Attack on Titan',
        provider: 'gogoanime',
        thumbnail: 'https://example.com/poster.jpg',
        description: 'Action / Dark Fantasy',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              height: 240,
              child: FavoriteCard(
                item: item,
                onTap: () => tapped = true,
                synced: false,
              ),
            ),
          ),
        ),
      );

      // Verify KaizokuMediaCard exists and receives properties
      expect(find.byType(KaizokuMediaCard), findsOneWidget);
      expect(find.text('Attack on Titan'), findsOneWidget);

      // Tap card and assert callback
      await tester.tap(find.byType(FavoriteCard));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('displays cloud done icon when synced is true', (tester) async {
      final item = FavoriteEntity(
        contentUrl: 'https://example.com/anime/2',
        title: 'Chainsaw Man',
        provider: 'zoro',
        thumbnail: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              height: 240,
              child: FavoriteCard(
                item: item,
                onTap: () {},
                synced: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    });

    testWidgets('displays cloud off icon when synced is false', (tester) async {
      final item = FavoriteEntity(
        contentUrl: 'https://example.com/anime/3',
        title: 'Jujutsu Kaisen',
        provider: 'zoro',
        thumbnail: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              height: 240,
              child: FavoriteCard(
                item: item,
                onTap: () {},
                synced: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });
  });

  group('SettingsNavTile & SettingsCard Behavior Tests', () {
    testWidgets('SettingsNavTile invokes onTap callback and displays value',
        (tester) async {
      var opened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              children: [
                SettingsNavTile(
                  icon: Icons.favorite_rounded,
                  title: 'Favorites',
                  value: '42',
                  onTap: () => opened = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.tap(find.byType(SettingsNavTile));
      await tester.pump();

      expect(opened, isTrue);
    });

    testWidgets('SettingsNavTile with destructive flag renders correctly',
        (tester) async {
      var cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsNavTile(
              icon: Icons.delete_outline_rounded,
              title: 'Clear Cache',
              destructive: true,
              onTap: () => cleared = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Clear Cache'));
      await tester.pump();

      expect(cleared, isTrue);
    });
  });
}
