import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/detail/domain/entities/cast_entity.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_cast_tab.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_empty_state.dart';
import 'package:soplay/features/detail/presentation/widgets/player_engine_sheet.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

void main() {
  group('Milestone 2.5 Playback & Manga Reader UI Tests', () {
    testWidgets('DetailEmptyState renders correctly with Kaizoku muted theme tokens', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DetailEmptyState(
              icon: Icons.movie_outlined,
              message: 'No media available right now',
            ),
          ),
        ),
      );

      // Verify the icon and message
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      expect(find.text('No media available right now'), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.movie_outlined));
      expect(iconWidget.color, KaizokuColors.textMuted);
      expect(iconWidget.size, 48);

      final textWidget = tester.widget<Text>(find.text('No media available right now'));
      expect(textWidget.style?.color, KaizokuColors.textSecondary);
    });

    testWidgets('DetailCastTab renders cast members and director correctly', (tester) async {
      const sampleCast = [
        CastEntity(
          id: '1',
          name: 'Monkey D. Luffy',
          image: '',
        ),
        CastEntity(
          id: '2',
          name: 'Roronoa Zoro',
          image: '',
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: SingleChildScrollView(
              child: DetailCastTab(
                cast: sampleCast,
                director: 'Eiichiro Oda',
              ),
            ),
          ),
        ),
      );

      // Verify director name
      expect(find.text('Eiichiro Oda'), findsOneWidget);

      // Verify cast member names
      expect(find.text('Monkey D. Luffy'), findsOneWidget);
      expect(find.text('Roronoa Zoro'), findsOneWidget);
    });

    testWidgets('NovelText renders headings and paragraphs correctly in manga reader', (tester) async {
      const htmlContent = '''
        <h1>Chapter 1: Dawn of Adventure</h1>
        <p>He set out to the open ocean in a tiny boat.</p>
        <hr />
        <p>The sky was illuminated in crimson hues.</p>
      ''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: SingleChildScrollView(
              child: NovelText(
                html: htmlContent,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Chapter 1: Dawn of Adventure'), findsOneWidget);
      expect(find.text('He set out to the open ocean in a tiny boat.'), findsOneWidget);
      expect(find.text('The sky was illuminated in crimson hues.'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    test('PlayerEngine mapping helpers are exhaustive for all engines', () {
      for (final engine in PlayerEngine.values) {
        final icon = playerEngineIcon(engine);
        final titleKey = playerEngineTitleKey(engine);
        final descKey = playerEngineDescKey(engine);

        expect(icon, isNotNull);
        expect(titleKey.isNotEmpty, isTrue);
        expect(descKey.isNotEmpty, isTrue);
      }
    });
  });
}
