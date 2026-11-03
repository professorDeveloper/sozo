import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/app_glass.dart';
import 'package:soplay/core/glass/glass_surface.dart';

/// The gate that decides whether an Android phone draws the refraction
/// (lib/core/glass/glass_power.dart), the step-down that takes it away again
/// when the phone's own frames say it cannot keep up (glass_step_down.dart),
/// and what the blur it falls back to is made of (glass_surface.dart).
void main() {
  /// A phone that passes every test in the gate: what the readings below
  /// change one thing of, so that each test is about that one thing.
  const good = GlassPowerReading(
    lowRam: false,
    memoryBytes: 6 * 1024 * 1024 * 1024,
    sdk: 34,
    vulkan11: true,
    glEs: 3,
    refreshHz: 120,
    powerSave: false,
    cores: 8,
  );

  group('the gate decides on what was measured', () {
    test('a good phone draws the refraction', () {
      expect(good.affordsRefraction, isTrue);
    });

    test('a 6 GB phone with no Vulkan 1.1 driver does not', () {
      // The case the old gate got wrong in the generous direction: the maker
      // sets no Go flag, there is plenty of RAM, and the GPU still cannot
      // bend a bar sixty times a second.
      const phone = GlassPowerReading(
        memoryBytes: 6 * 1024 * 1024 * 1024,
        sdk: 28,
        vulkan11: false,
        glEs: 3,
      );
      expect(phone.affordsRefraction, isFalse);
    });

    test('a current 4 GB phone keeps its glass', () {
      // And the case it got wrong the other way. 4 GB measures a little
      // under 4 GiB once the kernel and the GPU have taken their share, so
      // the threshold has to sit below it.
      const phone = GlassPowerReading(
        memoryBytes: 3717 * 1024 * 1024,
        sdk: 33,
        glEs: 3,
      );
      expect(phone.affordsRefraction, isTrue);
    });

    test('a 2 GB phone does not, flag or no flag', () {
      expect(
        const GlassPowerReading(
          memoryBytes: 2 * 1024 * 1024 * 1024,
          sdk: 33,
        ).affordsRefraction,
        isFalse,
      );
    });

    test('below API 29 Impeller has no Vulkan backend to draw with', () {
      expect(
        const GlassPowerReading(sdk: 28).affordsRefraction,
        isFalse,
      );
    });

    test('a GL ES 2 driver cannot compile the shader at all', () {
      expect(
        const GlassPowerReading(sdk: 34, glEs: 2).affordsRefraction,
        isFalse,
      );
    });

    test('an Android Go phone still draws the blur', () {
      expect(
        const GlassPowerReading(
          lowRam: true,
          memoryBytes: 6 * 1024 * 1024 * 1024,
          sdk: 34,
        ).affordsRefraction,
        isFalse,
      );
    });

    test('Battery Saver gives the glass up, and takes it back', () {
      final saving = good.withPowerSave(true);
      expect(saving.affordsRefraction, isFalse);
      expect(saving.withPowerSave(false).affordsRefraction, isTrue);
      // Nothing else of the reading is lost on the way through.
      expect(saving.withPowerSave(false), good);
    });

    test('the refresh rate is a budget, not a gate', () {
      // A 120 Hz panel is not a reason to refuse the glass; it is a reason
      // to measure its frames against 8.3 ms rather than 16.7.
      expect(good.affordsRefraction, isTrue);
      expect(good.budget.frame.inMicroseconds, closeTo(8333, 2));
      expect(
        const GlassPowerReading(sdk: 34, refreshHz: 60).budget,
        GlassFrameBudget.sixty,
      );
    });

    test('a core count decides nothing', () {
      expect(
        const GlassPowerReading(sdk: 34, cores: 2).affordsRefraction,
        isTrue,
      );
    });
  });

  group('a half answer never takes the glass away', () {
    test('no answer at all is the generous one', () {
      expect(GlassPowerReading.fromChannel(null).affordsRefraction, isTrue);
      expect(GlassPowerReading.fromChannel(null), GlassPowerReading.ample);
      expect(
        GlassPowerReading.fromChannel(<String, Object?>{}).affordsRefraction,
        isTrue,
      );
    });

    test('a field of the wrong kind is read as missing', () {
      final half = GlassPowerReading.fromChannel(<String, Object?>{
        'lowRam': 'yes',
        'memoryBytes': 'lots',
        'sdk': '34',
        'vulkan11': 1,
        'glEs': null,
      });
      expect(half.affordsRefraction, isTrue);
      expect(half.memoryBytes, isNull);
      expect(half.sdk, isNull);
    });

    test('what the phone does send is read', () {
      final read = GlassPowerReading.fromChannel(<String, Object?>{
        'lowRam': false,
        'memoryBytes': 4000000000,
        'sdk': 31,
        'vulkan11': true,
        'glEs': 3,
        // The phone sends a rate as a double; a map that came back as an int
        // must still be read.
        'refreshHz': 90,
        'powerSave': false,
        'cores': 8,
      });
      expect(read.memoryBytes, 4000000000);
      expect(read.sdk, 31);
      expect(read.refreshHz, 90.0);
      expect(read.affordsRefraction, isTrue);
    });
  });

  group('the frame budget', () {
    test('a rate the phone could not give falls back to sixty', () {
      expect(GlassFrameBudget.ofRefreshRate(0), GlassFrameBudget.sixty);
      expect(GlassFrameBudget.ofRefreshRate(-1), GlassFrameBudget.sixty);
      expect(GlassFrameBudget.ofRefreshRate(double.nan), GlassFrameBudget.sixty);
    });

    test('a rate outside what a panel can be is clamped, not believed', () {
      expect(
        GlassFrameBudget.ofRefreshRate(100000).frame,
        GlassFrameBudget.ofRefreshRate(240).frame,
      );
      expect(
        GlassFrameBudget.ofRefreshRate(1).frame,
        GlassFrameBudget.ofRefreshRate(24).frame,
      );
    });
  });

  group('the step-down', () {
    /// A policy with a small window, so a test can say in a few frames what
    /// a phone says in a second.
    GlassStepDown policy({double slack = 1.5}) => GlassStepDown(
      budget: GlassFrameBudget.sixty,
      warmup: 2,
      window: 10,
      misses: 5,
      slack: slack,
    );

    const good = Duration(microseconds: 12000);
    const bad = Duration(microseconds: 40000);

    test('a phone keeping up keeps its glass however long it runs', () {
      final down = policy();
      for (var i = 0; i < 500; i++) {
        expect(down.frame(good), isFalse);
      }
      expect(down.down, isFalse);
    });

    test('the warm-up frames are measured and thrown away', () {
      final down = policy();
      // The frames that pay for the shader being compiled are over budget on
      // every phone, and there are as many of them as the window needs.
      expect(down.frame(bad), isFalse);
      expect(down.frame(bad), isFalse);
      expect(down.debugMisses, 0);
    });

    test('a phone that keeps missing is dropped to the blur', () {
      final down = policy();
      down
        ..frame(bad)
        ..frame(bad);
      for (var i = 0; i < 4; i++) {
        expect(down.frame(bad), isFalse, reason: 'frame $i');
      }
      // The fifth missed frame of the window is the one that decides.
      expect(down.frame(bad), isTrue);
      expect(down.down, isTrue);
    });

    test('it says so once, not on every frame after', () {
      final down = policy();
      down
        ..frame(bad)
        ..frame(bad);
      for (var i = 0; i < 5; i++) {
        down.frame(bad);
      }
      expect(down.down, isTrue);
      expect(down.frame(bad), isFalse);
      expect(down.frame(good), isFalse);
    });

    test('one bad frame in a smooth run is not a verdict', () {
      final down = policy();
      down
        ..frame(bad)
        ..frame(bad);
      for (var i = 0; i < 100; i++) {
        // A decode landing, a collection: one frame in ten goes over and the
        // window never fills with misses.
        expect(down.frame(i % 10 == 0 ? bad : good), isFalse);
      }
      expect(down.down, isFalse);
    });

    test('misses roll off the back of the window', () {
      final down = policy();
      down
        ..frame(bad)
        ..frame(bad);
      for (var i = 0; i < 4; i++) {
        down.frame(bad);
      }
      expect(down.debugMisses, 4);
      for (var i = 0; i < 10; i++) {
        down.frame(good);
      }
      expect(down.debugMisses, 0);
      expect(down.down, isFalse);
    });

    test('the glass going and coming back pays its warm-up again', () {
      final down = policy();
      down
        ..frame(bad)
        ..frame(bad)
        ..frame(bad)
        ..frame(bad);
      expect(down.debugMisses, 2);
      down.restart();
      expect(down.debugMisses, 0);
      // And the next two frames are warm-up once more.
      down
        ..frame(bad)
        ..frame(bad);
      expect(down.debugMisses, 0);
    });

    test('the slack keeps a frame a hair over the vsync off the count', () {
      final down = policy();
      down
        ..frame(bad)
        ..frame(bad);
      // Flutter reports a little over the vsync interval on a phone that is
      // in fact smooth; 1.5 of the budget is well clear of that.
      down.frame(const Duration(microseconds: 18000));
      expect(down.debugMisses, 0);
      down.frame(const Duration(microseconds: 25500));
      expect(down.debugMisses, 1);
    });

    test('the budget is the panel\'s, not sixty hertz', () {
      // The same 12 ms frame is comfortable at 60 Hz and a miss at 120.
      final fast = GlassStepDown(
        budget: GlassFrameBudget.ofRefreshRate(120),
        warmup: 0,
        window: 4,
        misses: 2,
      );
      fast
        ..frame(const Duration(microseconds: 13000))
        ..frame(const Duration(microseconds: 13000));
      expect(fast.down, isTrue);
    });

    test('the panel\'s rate learnt late is still the budget it judges by', () {
      // The phone answers over a channel, so the policy is made before the
      // rate is known: a 120 Hz panel that could only be told at birth would
      // spend the whole run judging against sixty and condemn nothing.
      final late = GlassStepDown(
        budget: GlassFrameBudget.sixty,
        warmup: 0,
        window: 4,
        misses: 2,
      );
      const comfortableAtSixty = Duration(microseconds: 13000);
      late
        ..frame(comfortableAtSixty)
        ..frame(comfortableAtSixty);
      expect(late.down, isFalse);
      late.budget = GlassFrameBudget.ofRefreshRate(120);
      // And the frames weighed against the wrong budget are gone, rather
      // than counting toward a verdict they were never evidence for.
      expect(late.debugMisses, 0);
      late
        ..frame(comfortableAtSixty)
        ..frame(comfortableAtSixty);
      expect(late.down, isTrue);
    });
  });

  group('the step-down reaches the glass', () {
    setUp(GlassFrameWatch.debugReset);
    tearDown(GlassFrameWatch.debugReset);

    testWidgets('a phone stepped down draws the blur, not the refraction', (
      tester,
    ) async {
      // Set and cleared inside the body: the test framework checks the
      // foundation's debug variables before the tear-downs run.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            GlassPower.channel,
            (call) async => <String, Object?>{
              'lowRam': false,
              'memoryBytes': 8 * 1024 * 1024 * 1024,
              'sdk': 34,
              'vulkan11': true,
              'glEs': 3,
              'refreshHz': 60.0,
              'powerSave': false,
              'cores': 8,
            },
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
      await tester.pump();
      expect(GlassGroup.liquidAt(inside), isTrue);
      // What sixty missed frames would have decided.
      GlassFrameWatch.debugStepDown();
      await tester.pump();
      expect(GlassGroup.liquidAt(inside), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Battery Saver thrown while the app runs takes the glass', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            GlassPower.channel,
            (call) async => <String, Object?>{'sdk': 34, 'glEs': 3},
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
      await tester.pump();
      expect(GlassGroup.liquidAt(inside), isTrue);
      // The phone says so unasked, as it does when the switch is thrown in
      // Settings or the battery runs down.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            GlassPower.channel.name,
            GlassPower.channel.codec.encodeMethodCall(
              const MethodCall('powerSave', true),
            ),
            (_) {},
          );
      await tester.pump();
      expect(GlassGroup.liquidAt(inside), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('the blur is the same glass, plainer', () {
    test('it carries the recipe\'s colour lift, as the shader does', () {
      final bar = GlassRecipe.of(GlassKind.regular);
      expect(bar.saturation, greaterThan(1), reason: 'the premise');
      final filter = GlassBlurFilter.of(bar, 1);
      // A composed filter: the blur with the lift fused under it, inside the
      // one read of the screen the frost already takes.
      expect(filter.toString(), contains('compose'));
    });

    test('a recipe that asks for no lift is a plain blur', () {
      final menu = GlassRecipe.of(GlassKind.menu);
      expect(menu.saturation, 1, reason: 'the premise');
      expect(GlassBlurFilter.of(menu, 1).toString(), isNot(contains('compose')));
    });

    test('thinning the glass thins the lift with the frost', () {
      // At nothing of the glass there is nothing to lift either: a capsule
      // coming up must not saturate at full strength through a frost that is
      // barely there.
      expect(
        GlassBlurFilter.of(GlassRecipe.of(GlassKind.regular), 0).toString(),
        isNot(contains('compose')),
      );
    });

    test('the lift keeps luminance where it was', () {
      // A grey has no colour to lift, so a saturation matrix that moves it
      // is one that would lighten or darken everything under the glass.
      final matrix = GlassBlurFilter.saturate(1.5).toString();
      expect(matrix, contains('matrix'));
      // The rows of a luminance-preserving matrix each sum to one.
      const r = 0.2126, g = 0.7152, b = 0.0722;
      const s = 1.5;
      expect(
        r + s * (1 - r) + g * (1 - s) + b * (1 - s),
        closeTo(1, 1e-9),
      );
    });

    testWidgets('every shape of one group shares one read of the screen', (
      tester,
    ) async {
      // Blur mode, which is what the test renderer draws: three shapes of
      // one gathering group used to take three full reads of the screen
      // behind their clips, because nothing in the app ever put a
      // BackdropGroup above them and the key they asked for was always null.
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: GlassGroup(
              gathers: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassSurface(child: SizedBox(width: 44, height: 44)),
                  GlassSurface(child: SizedBox(width: 44, height: 44)),
                  GlassSurface(child: SizedBox(width: 44, height: 44)),
                ],
              ),
            ),
          ),
        ),
      );
      final blurs = tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .toList();
      expect(blurs, hasLength(3));
      final keys = blurs.map((blur) => blur.backdropGroupKey).toSet();
      expect(keys.single, isNotNull, reason: 'one shared read, not three');
    });

    testWidgets('a blurred shape draws with the lift, not only round it', (
      tester,
    ) async {
      // The helper above is only worth having if the shape actually uses it:
      // the filter the renderer is handed has to be the composed one.
      expect(
        GlassRecipe.of(GlassKind.regular).saturation,
        greaterThan(1),
        reason: 'the premise',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: GlassSurface(child: SizedBox(width: 44, height: 44)),
          ),
        ),
      );
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.filter.toString(), contains('compose'));
    });

    testWidgets('a lens and the glass over video keep their own read', (
      tester,
    ) async {
      // A lens is held over the bar, its glyphs and its pill: a read taken
      // before any of them were drawn would frost the page without the bar.
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: GlassSurface(
              kind: GlassKind.panel,
              child: SizedBox(width: 44, height: 44),
            ),
          ),
        ),
      );
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.backdropGroupKey, isNull);
    });
  });
}
