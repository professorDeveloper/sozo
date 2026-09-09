import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/poster_hero.dart';

void main() {
  group('PosterHero', () {
    testWidgets('no tag means no Hero at all', (tester) async {
      // A detail page opened from a deeplink, a search result or the player
      // has nothing to fly from, and a Hero with no partner is a wasted
      // layer at best.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosterHero(tag: null, url: 'x', child: Text('poster')),
          ),
        ),
      );
      expect(find.byType(Hero), findsNothing);
      expect(find.text('poster'), findsOneWidget);
    });

    testWidgets('the flight is off, so a tag builds no Hero either',
        (tester) async {
      // `flightEnabled` is false: the shuttle is a full-resolution poster and
      // the detail page does its first layout, decode and request in the same
      // frames, so the glide arrived as a stall and a jump. The tags are still
      // threaded from thirty-odd call sites — turning the flight back on is
      // one word here, and this test is what says which state we are in.
      expect(PosterHero.flightEnabled, isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosterHero(tag: 'poster:trending:3', url: 'x', child: Text('p')),
          ),
        ),
      );
      expect(find.byType(Hero), findsNothing);
      expect(find.text('p'), findsOneWidget);
    });

    testWidgets('both ends still render their own poster with no flight',
        (tester) async {
      // What used to be guarded here is that the two ends agree on the tag and
      // the poster travels. With the flight off, what matters instead is that
      // opening the second page is uneventful: each end draws its own child,
      // nothing is left behind in the overlay, and no Hero asserts about a
      // partner it cannot find.
      const tag = 'poster:trending:0';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 118,
                  height: 155,
                  child: PosterHero(
                    tag: tag,
                    url: null,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: SizedBox(
                              height: 440,
                              child: PosterHero(
                                tag: tag,
                                url: null,
                                child: ColoredBox(color: Color(0xFF123456)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Hero), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(Hero), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('detailHeroHeight', () {
    testWidgets('is clamped rather than a bare fraction of the screen',
        (tester) async {
      // 0.55 of a tall phone is a header taller than the content under it;
      // 0.55 of a short one leaves no room for the poster.
      late double tall;
      late double short;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 1200)),
          child: Builder(builder: (c) {
            tall = detailHeroHeight(c);
            return const SizedBox();
          }),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 500)),
          child: Builder(builder: (c) {
            short = detailHeroHeight(c);
            return const SizedBox();
          }),
        ),
      );

      expect(tall, 440.0);
      expect(short, 320.0);
    });

    testWidgets('includes the status bar inset', (tester) async {
      // The loaded page adds topPad to expandedHeight. When the loading page
      // did not, the header jumped by the height of the status bar the moment
      // the response landed.
      late double withInset;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 24),
          ),
          child: Builder(builder: (c) {
            withInset = detailHeroHeight(c);
            return const SizedBox();
          }),
        ),
      );
      // 800 * 0.55 = 440 (at the clamp) + 24
      expect(withInset, 464.0);
    });
  });
}
