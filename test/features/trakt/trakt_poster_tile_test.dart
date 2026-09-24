// A two-line title under a Trakt poster fits its grid cell at any width and
// text size — the cell is measured from the tile's own text block.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_hub_models.dart';
import 'package:soplay/features/trakt/presentation/trakt_hub_widgets.dart';

void main() {
  const entry = TraktEntry(
    media: TraktMedia(
      kind: 'movie',
      traktId: 1,
      title: 'Death Note Relight 1: Visions of a God and a Very Long Name',
      year: 2007,
    ),
  );

  for (final width in [320.0, 360.0, 411.0, 800.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('fits at ${width}px, text x$scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    SliverLayoutBuilder(
                      builder: (context, constraints) {
                        const maxTile = 132.0;
                        const gap = 12.0;
                        final w = constraints.crossAxisExtent;
                        final columns = ((w + gap) / (maxTile + gap))
                            .ceil()
                            .clamp(2, 12);
                        final tile = (w - gap * (columns - 1)) / columns;
                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: gap,
                                mainAxisExtent:
                                    tile * 1.5 +
                                    TraktPosterTile.textBlockHeight(
                                      MediaQuery.textScalerOf(context),
                                    ),
                              ),
                          itemCount: 6,
                          itemBuilder: (_, _) =>
                              TraktPosterTile(entry: entry, onTap: () {}),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
