import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/presentation/widgets/player_transport_row.dart';

void main() {
  for (final width in [320.0, 412.0, 800.0]) {
    for (final previous in [true, false]) {
      testWidgets('next stays right of seek-forward at width $width, previous=$previous', (tester) async {
        tester.view.physicalSize = Size(width, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget button(String key, {bool large = false}) => SizedBox(key: ValueKey(key), width: large ? 72 : 52, height: large ? 72 : 52);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlayerTransportRow(
          previous: previous ? button('previous') : null,
          next: button('next'), rewind: button('rewind'),
          playPause: button('play', large: true), forward: button('forward'),
        ))));
        expect(tester.takeException(), isNull);
        double x(String key) => tester.getCenter(find.byKey(ValueKey(key))).dx;
        expect(x('play'), closeTo(width / 2, 0.01));
        expect(x('next'), greaterThan(x('forward')));
        expect(x('forward'), greaterThan(x('play')));
        expect(x('rewind'), lessThan(x('play')));
        if (previous) expect(x('previous'), lessThan(x('rewind')));
      });
    }
  }
}
