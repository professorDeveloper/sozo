import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_badge.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_media_card.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/home_movie_section.dart';

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
          body: SingleChildScrollView(
            child: child,
          ),
        ),
      ),
    );
  }

  final testMovie = MovieEntity(
    externalId: 'test-123',
    title: 'One Piece Film: Red',
    description: 'Uta, the most beloved singer in the world.',
    slug: 'one-piece-film-red',
    url: 'https://example.com/stream/op-red',
    provider: 'animepahe',
    thumbnail: 'https://example.com/onepiece.jpg',
    year: 2022,
    rating: 9,
    qualities: ['1080p', '720p'],
    category: 'anime',
  );

  group('Home Kaizoku UI - MovieSection Component', () {
    testWidgets('renders MovieSection with real MovieEntity, header action, and KaizokuMediaCard', (tester) async {
      bool seeAllTapped = false;

      await tester.pumpWidget(
        wrapWithApp(
          MovieSection(
            title: 'Trending Anime',
            type: 'trending',
            slug: 'anime',
            movies: [testMovie],
            onSeeAll: () {
              seeAllTapped = true;
            },
          ),
        ),
      );

      // Verify section header with title
      expect(find.text('Trending Anime'), findsOneWidget);

      // Verify KaizokuMediaCard inside section
      expect(find.byType(KaizokuMediaCard), findsOneWidget);
      expect(find.text('One Piece Film: Red'), findsOneWidget);

      // Tap header "See all" target
      await tester.tap(find.text('Trending Anime'));
      await tester.pump();

      expect(seeAllTapped, isTrue);
    });

    testWidgets('adapts responsively across compact, medium and large widths', (tester) async {
      // Mobile compact width (360)
      await tester.pumpWidget(
        wrapWithApp(
          MovieSection(
            title: 'Popular',
            type: 'popular',
            slug: 'popular',
            movies: [testMovie],
          ),
          size: const Size(360, 800),
        ),
      );
      expect(find.text('Popular'), findsOneWidget);

      // Tablet / Medium width (768)
      await tester.pumpWidget(
        wrapWithApp(
          MovieSection(
            title: 'Popular',
            type: 'popular',
            slug: 'popular',
            movies: [testMovie],
          ),
          size: const Size(768, 1024),
        ),
      );
      expect(find.text('Popular'), findsOneWidget);

      // Desktop / Ultra width (1440)
      await tester.pumpWidget(
        wrapWithApp(
          MovieSection(
            title: 'Popular',
            type: 'popular',
            slug: 'popular',
            movies: [testMovie],
          ),
          size: const Size(1440, 900),
        ),
      );
      expect(find.text('Popular'), findsOneWidget);
    });
  });

  group('Home Kaizoku UI - History / Continue Watching Presentation', () {
    testWidgets('renders backdrop ratio with Neon Crimson progress bar and episode subtitle', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          const KaizokuMediaCard(
            title: 'Jujutsu Kaisen',
            subtitle: 'Episode 24 • 18m left',
            imageUrl: 'https://example.com/jjk_thumb.jpg',
            ratio: KaizokuCardRatio.backdrop,
            progress: 0.72,
            badgeText: 'RESUME',
            badgeVariant: KaizokuBadgeVariant.crimson,
          ),
          size: const Size(400, 800),
        ),
      );

      expect(find.text('Jujutsu Kaisen'), findsOneWidget);
      expect(find.text('Episode 24 • 18m left'), findsOneWidget);
      expect(find.text('RESUME'), findsOneWidget);

      // Verify progress indicator is rendered
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, equals(0.72));
    });
  });
}
