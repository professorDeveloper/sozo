import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/native/native_glass_bar.dart';

import 'bar_harness.dart';
import 'fake_native_host.dart';

Widget _bar({bool active = false, VoidCallback? onPressed, String? title}) =>
    Center(
      child: NativeGlassBar(
        look: NativeBarLook.capsule,
        fallback: (_) => const Text('fallback'),
        items: [
          NativeBarItem(
            id: 'stats',
            symbol: 'info.circle',
            semanticLabel: 'Stats',
            active: active,
            title: title,
            onPressed: onPressed,
          ),
          const NativeBarItem(
            id: 'settings',
            symbol: 'gearshape',
            semanticLabel: 'Settings',
          ),
        ],
      ),
    );

void main() {
  testOnIPhone('the view is made with everything and told nothing twice', (
    tester,
  ) async {
    final host = FakeNativeHost();
    await tester.pumpWidget(barHarness(_bar(), host: host));
    await tester.pump();
    final view = host.views.single;
    expect(view.type, NativeGlassBar.viewType);
    expect((view.params['items']! as List), hasLength(2));
    expect(view.params['look'], 'capsule');
    // `made:` counts the creation params as told: linking sends nothing.
    expect(view.link.said, isEmpty);

    await tester.pumpWidget(barHarness(_bar(), host: host));
    await tester.pump();
    expect(view.link.said, isEmpty, reason: 'same items, nothing to say');
  });

  testOnIPhone('a changed field is sent alone, as setItem', (tester) async {
    final host = FakeNativeHost();
    await tester.pumpWidget(barHarness(_bar(), host: host));
    await tester.pump();
    final link = host.views.single.link;

    await tester.pumpWidget(barHarness(_bar(active: true), host: host));
    await tester.pump();
    expect(link.said, hasLength(1));
    expect(link.said.single.method, 'setItem');
    expect(link.said.single.arguments, {'id': 'stats', 'active': true});
  });

  testOnIPhone('a slot that moves is sent as a whole setItems', (tester) async {
    final host = FakeNativeHost();
    await tester.pumpWidget(barHarness(_bar(), host: host));
    await tester.pump();
    final link = host.views.single.link;

    await tester.pumpWidget(barHarness(_bar(title: 'Long words'), host: host));
    await tester.pump();
    expect(link.of('setItems'), hasLength(1));
    expect(link.of('setItem'), isEmpty);
  });

  testOnIPhone('UIKit is not heard once the bar has gone', (tester) async {
    final host = FakeNativeHost();
    var pressed = 0;
    await tester.pumpWidget(
      barHarness(_bar(onPressed: () => pressed++), host: host),
    );
    await tester.pump();
    final view = host.views.single;
    view.hear('press', 'stats');
    expect(pressed, 1);

    await tester.pumpWidget(barHarness(const SizedBox(), host: host));
    view.hear('press', 'stats');
    expect(pressed, 1);
    expect(view.link.disposed, isTrue);
  });
}
