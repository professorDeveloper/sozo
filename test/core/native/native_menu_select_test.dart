import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/native/native_glass_bar.dart';

import 'bar_harness.dart';
import 'fake_native_host.dart';

Widget _speed(List<double> speeds, ValueChanged<int> onMenu) => Center(
  child: NativeGlassBar(
    look: NativeBarLook.capsule,
    fallback: (_) => const SizedBox(),
    items: [
      NativeBarItem(
        id: 'speed',
        symbol: 'gauge.with.dots.needle.67percent',
        semanticLabel: 'Speed',
        menu: [for (final s in speeds) NativeMenuRow(title: '${s}x', key: s)],
        onMenuSelected: onMenu,
      ),
    ],
  ),
);

void main() {
  testOnIPhone('a row is chosen by what the open menu showed', (tester) async {
    final host = FakeNativeHost();
    final picked = <int>[];
    await tester.pumpWidget(
      barHarness(_speed([1, 1.5, 2], picked.add), host: host),
    );
    await tester.pump();
    final view = host.views.single;
    expect((view.params['items']! as List).single['menu'], hasLength(3));

    view.hear('menuOpen', 'speed');
    // The rows change under the open menu: UIKit still shows the old ones.
    await tester.pumpWidget(
      barHarness(_speed([2, 1, 1.5], picked.add), host: host),
    );
    await tester.pump();
    view.hear('select', {'id': 'speed', 'row': 0});
    view.hear('menuClose', 'speed');
    // Row 0 was 1x when the menu opened; 1x is now index 1.
    expect(picked, [1]);

    // A menu opened after the change reads the new rows.
    view.hear('menuOpen', 'speed');
    view.hear('select', {'id': 'speed', 'row': 0});
    expect(picked, [1, 0]);
  });

  testOnIPhone('the menu holding open and closing is said', (tester) async {
    final host = FakeNativeHost();
    final said = <String>[];
    await tester.pumpWidget(
      barHarness(
        Center(
          child: NativeGlassBar(
            look: NativeBarLook.capsule,
            fallback: (_) => const SizedBox(),
            onMenuOpen: () => said.add('open'),
            onMenuClose: () => said.add('close'),
            items: const [
              NativeBarItem(
                id: 'fit',
                symbol: 'aspectratio',
                semanticLabel: 'Fit',
              ),
            ],
          ),
        ),
        host: host,
      ),
    );
    await tester.pump();
    host.views.single
      ..hear('menuOpen', 'fit')
      ..hear('menuClose', 'fit');
    expect(said, ['open', 'close']);
  });
}
