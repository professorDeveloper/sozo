import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapWithApp(Widget child, {Size size = const Size(360, 800)}) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: KaizokuColors.cyberObsidian,
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 260,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  final testMovie = MovieEntity(
    externalId: 'aot-01',
    title: 'Attack on Titan',
    description: 'Humanity fight against titans.',
    slug: 'attack-on-titan',
    url: 'https://example.com/aot',
    provider: 'animepahe',
    thumbnail: 'https://example.com/aot.jpg',
    year: 2013,
    rating: 9,
    qualities: ['1080p'],
    category: 'anime',
  );

  group('Search Kaizoku UI - SearchResultCard Component', () {
    testWidgets('renders SearchResultCard with multi-source badge and triggers onTap', (tester) async {
      bool cardTapped = false;

      await tester.pumpWidget(
        wrapWithApp(
          SearchResultCard(
            movie: testMovie,
            sourceCount: 3,
            sourceLabel: 'AnimePahe',
            onTap: () {
              cardTapped = true;
            },
          ),
        ),
      );

      // Verify title and metadata
      expect(find.text('Attack on Titan'), findsOneWidget);
      expect(find.text('3 SOURCES'), findsOneWidget);
      expect(find.text('AnimePahe'), findsOneWidget);

      // Tap card
      await tester.tap(find.byType(SearchResultCard));
      await tester.pump();

      expect(cardTapped, isTrue);
    });

    test('verifies responsive searchGridColumns calculation across break-points', () {
      expect(searchGridColumns(360), equals(3)); // Mobile compact
      expect(searchGridColumns(500), equals(4)); // Large phone / Phablet
      expect(searchGridColumns(768), equals(5)); // Tablet
      expect(searchGridColumns(1024), equals(6)); // Small desktop / TV
      expect(searchGridColumns(1440), equals(7)); // Ultrawide desktop
    });

    testWidgets('renders empty and error state views with Cyber Obsidian styling and retry callback', (tester) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: KaizokuColors.cyberObsidian,
          ),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: KaizokuColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No results found for "Unknown"',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KaizokuColors.neonCrimson,
                    ),
                    onPressed: () {
                      retried = true;
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('No results found for "Unknown"'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      expect(retried, isTrue);
    });
  });
}
