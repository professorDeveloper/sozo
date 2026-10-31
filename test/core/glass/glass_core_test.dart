import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/app_glass.dart';
import 'package:soplay/core/glass/glass_sense.dart';
import 'package:soplay/core/glass/glass_surface.dart';
import 'package:soplay/core/glass/media_glass.dart';

/// The glass primitive (lib/core/glass/glass_surface.dart), its recipes
/// (app_glass.dart) and the two things the phone says about it: Reduce
/// Transparency (glass_sense.dart) and whether an Android phone can spend
/// the refraction (glass_power.dart).
void main() {
  Color over(Color tint, Color under) => Color.alphaBlend(tint, under);

  group('the recipes', () {
    test('the glass lifts black to a grey, not a dark disc', () {
      // The system's dark glass over black reads #1F1F1F (31).
      final on = over(GlassRecipe.of(GlassKind.regular).tint, Colors.black);
      expect((on.r * 255).round(), inInclusiveRange(26, 36), reason: '$on');
    });

    test('clear glass leaves the video its colour and frosts nothing', () {
      final clear = GlassRecipe.of(GlassKind.clear);
      expect(clear.clear, isTrue);
      expect(clear.frost, 0);
      expect(clear.blurFrost, 0);
      // A red frame under it stays red, not pink.
      final on = over(clear.tint, const Color(0xFFE11D2E));
      expect((on.g * 255).round(), lessThan(45), reason: '$on');
      expect(clear.lift, isEmpty);
    });

    test('a small shape alone is frosted more and a lighter grey', () {
      final bar = GlassRecipe.of(GlassKind.regular);
      final small = GlassRecipe.of(GlassKind.regular, compact: true);
      expect(small.frost, greaterThan(bar.frost));
      expect(small.tint.a, greaterThan(bar.tint.a));
    });

    test('every glass bends gently at its rim', () {
      for (final kind in GlassKind.values) {
        final r = GlassRecipe.of(kind);
        expect(r.thickness, inInclusiveRange(6, 14), reason: '$kind');
        expect(r.refraction, inInclusiveRange(1.1, 1.4), reason: '$kind');
        expect(r.dispersion, 0, reason: '$kind');
      }
    });
  });

  group('how the glass is drawn', () {
    Future<void> pump(
      WidgetTester tester, {
      GlassKind kind = GlassKind.regular,
      bool reduce = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: GlassSenseScope(
          reduceTransparency: reduce,
          child: Center(
            child: SizedBox(
              width: 44,
              height: 44,
              child: GlassSurface(kind: kind, child: const SizedBox.expand()),
            ),
          ),
        ),
      ),
    );

    testWidgets('without the shader the regular glass is a blur', (
      tester,
    ) async {
      await pump(tester);
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.enabled, isTrue);
    });

    testWidgets('clear glass over video falls back to its tint, never a blur', (
      tester,
    ) async {
      await pump(tester, kind: GlassKind.clear);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('Reduce Transparency: an opaque fill, nothing through it', (
      tester,
    ) async {
      await pump(tester, kind: GlassKind.clear, reduce: true);
      expect(find.byType(BackdropFilter), findsNothing);
      final fill = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassShape),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final color = (fill.decoration as ShapeDecoration).color!;
      expect(color.a, 1.0);
    });

    testWidgets('glass on glass is refused', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GlassGroup(
            child: GlassGroup(child: SizedBox(width: 10, height: 10)),
          ),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('the glass is held while its page is pushed', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const GlassPickScope(
            pick: GlassPick.liquid,
            child: Center(
              child: SizedBox(
                width: 44,
                height: 44,
                child: GlassSurface(child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(GlassShape));
      expect(GlassGroup.holdOf(context)!.value, isEmpty);
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        GlassGroup.holdOf(context)!.value,
        contains(GlassHoldReason.route),
      );
      await tester.pumpAndSettle();
    });
  });

  group('what the phone says', () {
    testWidgets('an iPhone with Reduce Transparency turns the glass opaque', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(GlassSense.channel, (call) async => true);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(GlassSense.channel, null),
      );
      late BuildContext inside;
      await tester.pumpWidget(
        GlassSense(
          child: Builder(
            builder: (context) {
              inside = context;
              GlassSense.reduceTransparencyOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      expect(GlassSense.reduceTransparencyOf(inside), isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('an Android Go phone draws the blur, not the refraction', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            GlassPower.channel,
            (call) async => {'lowRam': true},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(GlassPower.channel, null),
      );
      late BuildContext inside;
      await tester.pumpWidget(
        GlassPower(
          child: GlassPickScope(
            pick: GlassPick.liquid,
            child: Builder(
              builder: (context) {
                inside = context;
                GlassGroup.liquidAt(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(GlassGroup.liquidAt(inside), isTrue);
      await tester.pump();
      expect(GlassGroup.liquidAt(inside), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    test('a half answer never takes the glass away', () {
      expect(GlassPowerReading.fromChannel(null).affordsRefraction, isTrue);
      expect(
        GlassPowerReading.fromChannel({'lowRam': 'yes'}).affordsRefraction,
        isTrue,
      );
    });
  });

  group('controls over video', () {
    Widget row() => const MaterialApp(
      home: Center(
        child: MediaGlassLayer(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaGlass(child: SizedBox(width: 38, height: 38)),
              MediaGlass(child: SizedBox(width: 38, height: 38)),
              MediaGlass(radius: 10, child: SizedBox(width: 80, height: 44)),
            ],
          ),
        ),
      ),
    );

    testWidgets('on an iPhone a row is one read of the picture', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(row());
      expect(find.byType(GlassShape), findsNWidgets(3));
      expect(find.byType(GlassGroup), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a piece standing alone is a group of its own', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: MediaGlass(child: SizedBox(width: 38, height: 38)),
          ),
        ),
      );
      expect(find.byType(GlassGroup), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('elsewhere it is the black disc it always was', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(row());
      expect(find.byType(GlassShape), findsNothing);
      expect(find.byType(GlassGroup), findsNothing);
      final plate = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final decoration = plate.decoration as ShapeDecoration;
      expect(decoration.color, Colors.black.withValues(alpha: 0.45));
      expect(decoration.shape, isA<StadiumBorder>());
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
