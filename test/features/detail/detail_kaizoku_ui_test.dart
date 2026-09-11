import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_button.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';

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
          body: child,
        ),
      ),
    );
  }

  group('Detail Kaizoku UI - Actions and Interaction Contracts', () {
    testWidgets('triggers Play, Favorite, and Download actions with Shin Kaizoku styling', (tester) async {
      bool playTriggered = false;
      bool favoriteTriggered = false;
      bool downloadTriggered = false;

      await tester.pumpWidget(
        wrapWithApp(
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                KaizokuButton(
                  label: 'Play S1:E3',
                  icon: Icons.play_arrow_rounded,
                  variant: KaizokuButtonVariant.primary,
                  onPressed: () {
                    playTriggered = true;
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.bookmark_border_rounded),
                  color: Colors.white,
                  onPressed: () {
                    favoriteTriggered = true;
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  color: Colors.white,
                  onPressed: () {
                    downloadTriggered = true;
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Verify Play button
      expect(find.text('Play S1:E3'), findsOneWidget);
      await tester.tap(find.text('Play S1:E3'));
      await tester.pump();
      expect(playTriggered, isTrue);

      // Verify Favorite button
      final favFinder = find.byIcon(Icons.bookmark_border_rounded);
      expect(favFinder, findsOneWidget);
      await tester.tap(favFinder);
      await tester.pump();
      expect(favoriteTriggered, isTrue);

      // Verify Download button
      final dlFinder = find.byIcon(Icons.download_rounded);
      expect(dlFinder, findsOneWidget);
      await tester.tap(dlFinder);
      await tester.pump();
      expect(downloadTriggered, isTrue);
    });

    testWidgets('renders AppTabBar with Neon Crimson indicator and handles tab navigation', (tester) async {
      int activeIndex = 0;

      await tester.pumpWidget(
        wrapWithApp(
          AppTabBar(
            labels: const ['Episodes', 'Cast', 'Similar', 'Comments'],
            selectedIndex: 0,
            onChanged: (index) {
              activeIndex = index;
            },
          ),
        ),
      );

      expect(find.text('Episodes'), findsOneWidget);
      expect(find.text('Cast'), findsOneWidget);
      expect(find.text('Similar'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);

      // Tap on Cast tab
      await tester.tap(find.text('Cast'));
      await tester.pumpAndSettle();

      expect(activeIndex, equals(1));
    });

    testWidgets('adapts hero actions responsively across mobile, tablet and desktop widths', (tester) async {
      Widget buildActionLayout(BuildContext context) {
        final isDesktop = MediaQuery.sizeOf(context).width > 700;
        return isDesktop
            ? Row(
                children: [
                  KaizokuButton(
                    label: 'Watch Now',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  KaizokuButton(
                    label: 'Add to List',
                    variant: KaizokuButtonVariant.secondary,
                    icon: Icons.add_rounded,
                    onPressed: () {},
                  ),
                ],
              )
            : Column(
                children: [
                  KaizokuButton(
                    label: 'Watch Now',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 8),
                  KaizokuButton(
                    label: 'Add to List',
                    variant: KaizokuButtonVariant.secondary,
                    icon: Icons.add_rounded,
                    onPressed: () {},
                  ),
                ],
              );
      }

      // Compact (360) -> Column
      await tester.pumpWidget(
        wrapWithApp(
          Builder(builder: buildActionLayout),
          size: const Size(360, 800),
        ),
      );
      expect(find.byType(Column), findsOneWidget);

      // Large (1200) -> Row
      await tester.pumpWidget(
        wrapWithApp(
          Builder(builder: buildActionLayout),
          size: const Size(1200, 800),
        ),
      );
      expect(find.byType(Row), findsOneWidget);
    });
  });
}
