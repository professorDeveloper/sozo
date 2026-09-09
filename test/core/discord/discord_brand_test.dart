import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/discord/discord_brand.dart';

/// The mark is an inline SVG path written by hand. A path with one bad
/// character still parses into *something* — usually a blank or a smear — and
/// nothing in a build would say so. These render it and look at the result.
void main() {
  test('the SVG parses into a real drawing', () async {
    // The mark is an inline path written by hand, and a path with one bad
    // character still yields *something* — usually blank — that lays out at
    // the requested size and finds an SvgPicture. So the check is on the
    // parsed vector, not on the widget.
    //
    // Rasterising it would be the strongest check and is not available here:
    // toImage() inside the test binding waits on a raster thread that never
    // runs, and the test hangs rather than fails.
    final info = await vg.loadPicture(
      SvgStringLoader(DiscordBrand.svgForTest(Colors.white)),
      null,
    );
    addTearDown(info.picture.dispose);

    // The published mark's viewBox. A path that failed to parse leaves the
    // size at zero.
    expect(info.size.width, closeTo(127.14, 0.01));
    expect(info.size.height, closeTo(96.36, 0.01));
  });

  testWidgets('renders at every size it is used at', (tester) async {
    for (final size in [15.0, 22.0, 26.0, 34.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: DiscordBrand.mark(size: size))),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'failed at $size');
    }
  });

  test('the brand colours are Discord\'s published values', () {
    // Wrong-coloured Discord chrome reads as a counterfeit, which is the last
    // impression a screen asking for a credential should give.
    expect(DiscordBrand.blurple, const Color(0xFF5865F2));
    expect(DiscordBrand.online, const Color(0xFF23A55A));
    expect(DiscordBrand.offline, const Color(0xFF80848E));
  });
}
