import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/glass_sense.dart';
import 'package:soplay/core/glass/native_glass.dart';

/// The phone's own glass, hosted as a UIKit view
/// (lib/core/glass/native_glass.dart).
///
/// What a hosted view actually *looks* like cannot be tested here at all: a
/// `UiKitView` renders nothing in the test renderer and nothing into a
/// golden. So what is tested is everything up to the pixels — the decision
/// between the system's glass, the system's blur material and the caller's
/// own fallback, and the reading of what the phone said — which is exactly
/// why that decision was pulled out of the widget as a function
/// ([nativeGlassDraw]). The pixels are checked on a device by
/// integration_test/native_glass_test.dart.
void main() {
  const glass27 = NativeGlassCapability(
    systemVersion: '27.0.1',
    majorVersion: 27,
    systemGlass: true,
    styles: {'regular', 'clear'},
    materials: {'thin', 'regular'},
    reduceTransparency: false,
  );
  const blurOnly = NativeGlassCapability(
    systemVersion: '18.5',
    majorVersion: 18,
    systemGlass: false,
    styles: {},
    materials: {'ultraThin', 'thin', 'regular', 'thick', 'chrome'},
    reduceTransparency: false,
  );

  group('what to draw', () {
    test('a phone with the glass effect gets the glass effect', () {
      expect(
        nativeGlassDraw(
          platform: TargetPlatform.iOS,
          capability: glass27,
          style: NativeGlassStyle.clear,
        ),
        NativeGlassDraw.systemGlass,
      );
    });

    test('an iPhone whose OS has no glass effect gets a real material', () {
      // Not the hand-drawn blur: UIKit's own thin material, which is a
      // material the platform maintains rather than one we approximate.
      expect(
        nativeGlassDraw(platform: TargetPlatform.iOS, capability: blurOnly),
        NativeGlassDraw.systemMaterial,
      );
    });

    test('a style the phone did not offer falls to the material', () {
      // The decision is by capability and not by version: a phone that
      // reports the glass effect but not the style being asked for must
      // degrade, because mounting a view for a style it has not got is the
      // blank rectangle this probe exists to prevent.
      const partial = NativeGlassCapability(
        systemVersion: '26.0',
        majorVersion: 26,
        systemGlass: true,
        styles: {'regular'},
        materials: {'thin'},
        reduceTransparency: false,
      );
      expect(
        nativeGlassDraw(
          platform: TargetPlatform.iOS,
          capability: partial,
          style: NativeGlassStyle.clear,
        ),
        NativeGlassDraw.systemMaterial,
      );
    });

    test('nothing is hosted where the phone said nothing', () {
      expect(
        nativeGlassDraw(
          platform: TargetPlatform.iOS,
          capability: NativeGlassCapability.absent,
        ),
        NativeGlassDraw.none,
      );
    });

    test('nothing is hosted on an Android phone, whatever it said', () {
      // The factory is registered in ios/Runner only, so the platform is
      // checked before the capability rather than trusting a stale probe
      // carried across a hot restart.
      expect(
        nativeGlassDraw(platform: TargetPlatform.android, capability: glass27),
        NativeGlassDraw.none,
      );
    });

    test('Reduce Transparency hosts nothing: the fill is painted', () {
      expect(
        nativeGlassDraw(
          platform: TargetPlatform.iOS,
          capability: glass27,
          reduceTransparency: true,
        ),
        NativeGlassDraw.none,
      );
    });
  });

  group('what the phone said', () {
    test('no answer at all is no glass, not an error', () {
      expect(NativeGlassCapability.fromChannel(null), NativeGlassCapability.absent);
    });

    test('a map missing keys degrades rather than throwing', () {
      // The Dart and the native halves are not always the same age on a
      // phone mid-update, so an answer from an older Swift side has to be
      // readable.
      final said = NativeGlassCapability.fromChannel(<String, Object?>{
        'systemVersion': '27.0.1',
      });
      expect(said.systemVersion, '27.0.1');
      expect(said.systemGlass, isFalse);
      expect(said.styles, isEmpty);
      expect(said.materials, isEmpty);
    });

    test('two readings of the same phone are the same answer', () {
      // Equality is by what was said, not by which object said it:
      // `NativeGlassScope` rebuilds every surface under it when the
      // capability it carries changes, so an answer that merely arrived
      // twice must not count as a change.
      final said = NativeGlassCapability.fromChannel(<String, Object?>{
        'systemVersion': '27.0',
        'majorVersion': 27,
        'systemGlass': true,
        'glassStyles': <Object?>['clear', 'regular'],
        'materials': <Object?>['thin'],
      });
      final again = NativeGlassCapability.fromChannel(<String, Object?>{
        'systemVersion': '27.0',
        'majorVersion': 27,
        'systemGlass': true,
        // The same set, in the order the channel happened to hand it over.
        'glassStyles': <Object?>['regular', 'clear'],
        'materials': <Object?>['thin'],
      });
      expect(said, again);
      expect(said.hashCode, again.hashCode);
      expect(said, isNot(NativeGlassCapability.absent));
      expect(
        NativeGlassCapability.fromChannel(<String, Object?>{}),
        NativeGlassCapability.absent,
      );
    });

    test('the lists are read as names, and non-names are dropped', () {
      final said = NativeGlassCapability.fromChannel(<String, Object?>{
        'systemGlass': true,
        'majorVersion': 27,
        'glassStyles': <Object?>['regular', 7, null, 'clear'],
        'materials': <Object?>['thin'],
      });
      expect(said.styles, {'regular', 'clear'});
      expect(said.materials, {'thin'});
      expect(said.majorVersion, 27);
    });
  });

  group('the widget', () {
    /// A hosted view asks the engine to make one, which no test engine does.
    /// The channel is answered so that mounting the view is not itself the
    /// thing that fails.
    void answerPlatformViews(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async => call.method == 'create' ? 1 : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
    }

    /// The platform override has to be put back inside the test body: the
    /// framework checks that no foundation debug variable is still set
    /// before `addTearDown` would run.
    Future<void> onIPhone(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Widget probe({
      required NativeGlassCapability capability,
      bool reduceTransparency = false,
      required ValueChanged<NativeGlassDraw> onDraw,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: GlassSenseScope(
        reduceTransparency: reduceTransparency,
        child: NativeGlassScope(
          capability: capability,
          child: NativeGlass(
            borderRadius: BorderRadius.circular(22),
            onDraw: onDraw,
            fallback: (_) => const SizedBox(key: Key('fallback')),
          ),
        ),
      ),
    );

    testWidgets('a phone with no glass gets the caller\'s own glass', (
      tester,
    ) async {
      NativeGlassDraw? drawn;
      await tester.pumpWidget(
        probe(
          capability: NativeGlassCapability.absent,
          onDraw: (draw) => drawn = draw,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('fallback')), findsOneWidget);
      expect(drawn, NativeGlassDraw.none);
    });

    testWidgets('an iPhone with the glass effect hosts the view', (
      tester,
    ) async {
      answerPlatformViews(tester);
      await onIPhone(() async {
        NativeGlassDraw? drawn;
        await tester.pumpWidget(
          probe(capability: glass27, onDraw: (draw) => drawn = draw),
        );
        await tester.pump();
        expect(find.byType(UiKitView), findsOneWidget);
        expect(find.byKey(const Key('fallback')), findsNothing);
        expect(drawn, NativeGlassDraw.systemGlass);
      });
    });

    testWidgets('Reduce Transparency takes the hosted view away', (
      tester,
    ) async {
      answerPlatformViews(tester);
      await onIPhone(() async {
        NativeGlassDraw? drawn;
        await tester.pumpWidget(
          probe(
            capability: glass27,
            reduceTransparency: true,
            onDraw: (draw) => drawn = draw,
          ),
        );
        await tester.pump();
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byKey(const Key('fallback')), findsOneWidget);
        expect(drawn, NativeGlassDraw.none);
      });
    });

    testWidgets('the largest corner crosses the channel, not a zero', (
      tester,
    ) async {
      answerPlatformViews(tester);
      await onIPhone(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: NativeGlassScope(
              capability: glass27,
              child: const NativeGlass(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                tint: Color(0x66101010),
                fallback: _nothing,
              ),
            ),
          ),
        );
        await tester.pump();
        final view = tester.widget<UiKitView>(find.byType(UiKitView));
        final params = view.creationParams as Map<String, Object?>;
        expect(params['cornerRadius'], 28.0);
        expect(params['style'], 'regular');
        expect(params['material'], 'thin');
        expect(params['tint'], 0x66101010);
        expect(params['interactive'], isFalse);
      });
    });
  });
}

Widget _nothing(BuildContext context) => const SizedBox.shrink();
