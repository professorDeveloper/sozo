// The mark, as geometry rather than as a picture.
//
// The splash draws the letter by travelling its stroke, which is only possible
// because the asset carries a centreline as well as a silhouette. These are the
// facts that make that work — if any of them stops being true the splash
// degrades silently to a flat logo, which is exactly the failure the whole
// thing exists to replace.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/brand/sozo_mark_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SozoMarkGeometry geometry;

  setUpAll(() async {
    await SozoMarkGeometry.precache();
    // Image decoding completes on a real event loop, not the fake one.
    final value = SozoMarkGeometry.value;
    expect(value, isNotNull, reason: 'the asset did not parse');
    geometry = value!;
  });

  test('the asset carries both parts', () {
    expect(geometry.body.computeMetrics().isNotEmpty, isTrue);
    expect(geometry.spineLength, greaterThan(400));
    // A spine as long as the outline would mean it had ringed the shape rather
    // than run through it.
    expect(geometry.spineLength, lessThan(900));
  });

  test('and the spine runs inside the body, end to end', () {
    // The property the fill depends on: the ribbon is the spine dilated by
    // half its width, so a spine that wandered outside would leave the fill
    // spilling in one place and short in another.
    var outside = 0;
    for (var i = 0; i < SozoMarkGeometry.spineSamples; i++) {
      final p = ui.Offset(geometry.spineX[i], geometry.spineY[i]);
      if (!geometry.body.contains(p)) outside++;
    }
    expect(
      outside,
      lessThanOrEqualTo(2),
      reason:
          'the spine left the silhouette at $outside of '
          '${SozoMarkGeometry.spineSamples} samples',
    );
  });

  test('and it is written from one terminal to the other', () {
    final first = ui.Offset(geometry.spineX.first, geometry.spineY.first);
    final last = ui.Offset(
      geometry.spineX[SozoMarkGeometry.spineSamples - 1],
      geometry.spineY[SozoMarkGeometry.spineSamples - 1],
    );
    // Not a closed loop and not a stub: the two ends are most of the mark
    // apart, which is what "the pen writes the letter" requires.
    expect((first - last).distance, greaterThan(200));
  });

  group('the outline samples', () {
    test('are all populated', () {
      var zero = 0;
      for (var i = 0; i < SozoMarkGeometry.outlineSamples; i++) {
        if (geometry.outlineX[i] == 0 && geometry.outlineY[i] == 0) zero++;
      }
      expect(zero, 0, reason: '$zero samples never got a position');
    });

    test('and their normals are unit length', () {
      for (var i = 0; i < SozoMarkGeometry.outlineSamples; i++) {
        final n = ui.Offset(geometry.normalX[i], geometry.normalY[i]).distance;
        expect(n, closeTo(1.0, 0.001), reason: 'sample $i');
      }
    });

    test('and they point OUT of the fill, not into it', () {
      // The whole stir depends on this sign. Inward normals make the mark
      // shrink where it should swell, which at a glance reads as the logo
      // being eaten rather than breathing.
      var wrong = 0;
      for (var i = 0; i < SozoMarkGeometry.outlineSamples; i++) {
        final out = ui.Offset(
          geometry.outlineX[i] + geometry.normalX[i] * 5,
          geometry.outlineY[i] + geometry.normalY[i] * 5,
        );
        if (geometry.body.contains(out)) wrong++;
      }
      // Not zero: at a terminal a five-unit step crosses the opposite edge,
      // and there are two of them. A globally inverted sign fails this by two
      // orders of magnitude.
      expect(
        wrong,
        lessThan(SozoMarkGeometry.outlineSamples ~/ 8),
        reason:
            '$wrong of ${SozoMarkGeometry.outlineSamples} normals pointed '
            'into the fill',
      );
    });
  });

  test('the bounds are the mark, not the viewBox', () {
    // The splash centres on these. Centring on the 512 box instead puts the
    // mark visibly high and left, on the one frame everybody sees.
    expect(geometry.bounds.width, lessThan(512));
    expect(geometry.bounds.height, lessThan(512));
    expect(geometry.bounds.width, greaterThan(200));
  });

  test('and asking twice does the work once', () async {
    final first = SozoMarkGeometry.value;
    await SozoMarkGeometry.precache();
    expect(identical(SozoMarkGeometry.value, first), isTrue);
  });

  group('the artwork', () {
    // The logo is not its outline. A splash that filled the outline with one
    // colour drew the only part of the logo that is not the logo, so the
    // artwork decoding is a precondition, not a nicety.
    testWidgets('decodes', (tester) async {
      await tester.runAsync(SozoMarkGeometry.precache);
      final art = SozoMarkGeometry.art;
      expect(art, isNotNull, reason: 'the logo artwork did not decode');
      // Twice the 512 box the paths live in, so one scale registers it.
      expect(art!.width, 1024);
      expect(art.height, 1024);
    });
  });
}
