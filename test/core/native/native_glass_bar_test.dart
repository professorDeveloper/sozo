import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/native_bar_layout.dart';
import 'package:soplay/core/native/native_glass_bar.dart';
import 'package:soplay/core/system/platform_utils.dart';

import 'bar_harness.dart';
import 'fake_native_host.dart';

class _Calls {
  int play = 0;
  int hold = 0;
  int pageTaps = 0;
}

/// A transport cluster centred on a page that toggles on a tap.
Widget _page(
  _Calls calls, {
  bool shown = true,
  bool enabled = true,
  bool active = false,
  double width = 280,
}) => Stack(
  children: [
    Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => calls.pageTaps++,
      ),
    ),
    Center(
      child: SizedBox(
        width: width,
        child: NativeGlassBar(
          look: NativeBarLook.cluster,
          spread: BarSpread.even,
          shown: shown,
          fallback: (_) => const Text('fallback'),
          items: [
            const NativeBarItem(
              id: 'rewind',
              symbol: 'gobackward.10',
              semanticLabel: 'Rewind',
              extent: 52,
            ),
            NativeBarItem(
              id: 'play',
              symbol: 'play.fill',
              semanticLabel: 'Play',
              extent: 72,
              prominent: true,
              enabled: enabled,
              active: active,
              onPressed: () => calls.play++,
              onLongPress: () => calls.hold++,
            ),
            const NativeBarItem(
              id: 'forward',
              symbol: 'goforward.10',
              semanticLabel: 'Forward',
              extent: 52,
            ),
          ],
        ),
      ),
    ),
  ],
);

void main() {
  testOnIPhone('one hosted view for the whole cluster', (tester) async {
    final host = FakeNativeHost();
    await tester.pumpWidget(barHarness(_page(_Calls()), host: host));
    expect(host.views, hasLength(1));
    final items = host.views.single.params['items']! as List;
    expect(
      [for (final i in items) (i as Map)['symbol']],
      ['gobackward.10', 'play.fill', 'goforward.10'],
    );
    expect(find.text('fallback'), findsNothing);
  });

  testOnIPhone('each slot says its label, enabled and selected state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final calls = _Calls();
    await tester.pumpWidget(
      barHarness(_page(calls, active: true), host: FakeNativeHost()),
    );
    final play = tester.getSemantics(find.bySemanticsLabel('Play'));
    expect(
      play,
      matchesSemantics(
        label: 'Play',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Play'));
    tester.semantics.longPress(find.semantics.byLabel('Play'));
    expect(calls.play, 1);
    expect(calls.hold, 1);

    await tester.pumpWidget(
      barHarness(_page(calls, enabled: false), host: FakeNativeHost()),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Play')),
      matchesSemantics(
        label: 'Play',
        isButton: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
    semantics.dispose();
  });

  testOnIPhone('a tap in a gap is the page, a tap on a slot is UIKit', (
    tester,
  ) async {
    final host = FakeNativeHost();
    final calls = _Calls();
    await tester.pumpWidget(barHarness(_page(calls), host: host));
    await tester.pump();
    final bar = tester.getRect(find.byType(NativeGlassBar));

    // Between rewind and play.
    final rewind = (host.views.single.params['items']! as List)[0] as Map;
    final rect = rewind['rect']! as List;
    final gap =
        bar.topLeft + Offset((rect[0] as double) + 52 + 4, bar.height / 2);
    await tester.tapAt(gap);
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.pageTaps, 1);
    expect(host.taps, 0);

    await tester.tapAt(bar.center);
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.pageTaps, 1, reason: 'the play slot took it');
    expect(host.taps, 1);

    host.views.single.hear('press', 'play');
    expect(calls.play, 1);
  });

  testOnIPhone('hiding fades in UIKit, then leaves the frame', (tester) async {
    final host = FakeNativeHost();
    final calls = _Calls();
    await tester.pumpWidget(barHarness(_page(calls), host: host));
    await tester.pump();
    final link = host.views.single.link;

    await tester.pumpWidget(barHarness(_page(calls, shown: false), host: host));
    await tester.pump();
    expect(link.of('setShown').single.arguments, {'shown': false, 'ms': 220});
    expect(
      tester.widget<Offstage>(find.byType(Offstage)).offstage,
      isFalse,
      reason: 'still fading',
    );
    await tester.pump(NativeGlassBar.fade);
    expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isTrue);
    expect(host.views, hasLength(1), reason: 'kept alive, not remade');

    // Hidden, a tap is the page's.
    await tester.tapAt(tester.getCenter(find.byType(NativeGlassBar)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.pageTaps, 1);

    await tester.pumpWidget(barHarness(_page(calls), host: host));
    await tester.pump();
    expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isFalse);
    expect(link.of('setShown').last.arguments, {'shown': true, 'ms': 220});
  });

  testOnIPhone('no Flutter opacity stands over a native bar', (tester) async {
    await tester.pumpWidget(
      barHarness(_page(_Calls()), host: FakeNativeHost()),
    );
    expect(
      find.ancestor(
        of: find.byType(NativeGlassBar),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testOnIPhone('Reduce Motion hides at once', (tester) async {
    final host = FakeNativeHost();
    await tester.pumpWidget(
      barHarness(_page(_Calls()), host: host, disableAnimations: true),
    );
    await tester.pump();
    await tester.pumpWidget(
      barHarness(
        _page(_Calls(), shown: false),
        host: host,
        disableAnimations: true,
      ),
    );
    await tester.pump();
    expect(host.views.single.link.of('setShown').single.arguments, {
      'shown': false,
      'ms': 0,
    });
  });

  group('the Flutter fallback', () {
    testOnIPhone('without glassControls', (tester) async {
      final host = FakeNativeHost();
      await tester.pumpWidget(
        barHarness(
          _page(_Calls()),
          host: host,
          capability: NativeGlassCapability.absent,
        ),
      );
      expect(host.views, isEmpty);
      expect(find.text('fallback'), findsOneWidget);
    });

    testOnIPhone('under Reduce Transparency', (tester) async {
      final host = FakeNativeHost();
      await tester.pumpWidget(
        barHarness(_page(_Calls()), host: host, reduceTransparency: true),
      );
      expect(host.views, isEmpty);
      expect(find.text('fallback'), findsOneWidget);
    });

    testOnIPhone('on a desktop', (tester) async {
      final host = FakeNativeHost();
      await tester.pumpWidget(barHarness(_page(_Calls()), host: host));
      expect(host.views, isEmpty);
    }, desktop: true);

    testOnIPhone('on Android', (tester) async {
      final host = FakeNativeHost();
      await tester.pumpWidget(barHarness(_page(_Calls()), host: host));
      expect(host.views, isEmpty);
    }, platform: TargetPlatform.android);

    testOnIPhone('on a television', (tester) async {
      debugSetTvPlatform(true);
      try {
        final host = FakeNativeHost();
        await tester.pumpWidget(barHarness(_page(_Calls()), host: host));
        expect(host.views, isEmpty);
      } finally {
        debugSetTvPlatform(false);
      }
    });

    testOnIPhone('for the one bar that does not fit', (tester) async {
      final host = FakeNativeHost();
      await tester.pumpWidget(
        barHarness(
          Column(
            children: [
              SizedBox(width: 120, child: _page(_Calls(), width: 120)),
              SizedBox(width: 400, height: 100, child: _page(_Calls())),
            ],
          ),
          host: host,
        ),
      );
      expect(find.text('fallback'), findsOneWidget);
      expect(host.views, hasLength(1));
    });
  });
}
