import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/native_controls_gate.dart';
import 'package:soplay/core/native/player_controls_style.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/presentation/widgets/native_controls_offer.dart';

const _ios26 = NativeGlassCapability(
  systemVersion: '26.0',
  majorVersion: 26,
  systemGlass: true,
  styles: {'regular', 'clear'},
  materials: {'thin'},
  reduceTransparency: false,
  glassControls: true,
);

/// No translations are loaded, so every `.tr()` renders as its own key.
void main() {
  late HiveService hive;

  setUp(() async {
    // In memory: real file writes never finish inside a widget test.
    await Hive.openBox(AppConstants.authBox, bytes: Uint8List(0));
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
    hive = HiveService();
  });

  tearDown(() async {
    await Hive.close();
  });

  final answers = <PlayerControlsStyle>[];

  /// On an iPhone, reset before the test ends as the binding insists.
  void iosTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        debugNativeControlsDesktopOverride = false;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          debugNativeControlsDesktopOverride = null;
        }
      });

  /// Stands in for the player: each tap asks the gate the player asks, and
  /// presents the offer when it says so.
  Future<void> pumpHost(WidgetTester tester) async {
    answers.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeGlassScope(
          capability: _ios26,
          child: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  if (!NativeControls.shouldOffer(
                    context,
                    stored: hive.storedPlayerControlsStyle,
                    alreadyOffered: hive.nativeControlsOffered,
                  )) {
                    return;
                  }
                  answers.add(await presentNativeControlsOffer(context, hive));
                },
                child: const Text('controls'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> reveal(WidgetTester tester) async {
    await tester.tap(find.text('controls'));
    await tester.pumpAndSettle();
  }

  final card = find.text('player.native_offer_title');

  iosTest('Try it stores native', (tester) async {
    await pumpHost(tester);
    await reveal(tester);
    expect(card, findsOneWidget);
    expect(hive.nativeControlsOffered, isTrue);
    await tester.tap(find.byKey(const ValueKey('native-offer-try')));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(answers, [PlayerControlsStyle.native]);
    expect(hive.storedPlayerControlsStyle, PlayerControlsStyle.native);
  });

  iosTest('Not now stores classic', (tester) async {
    await pumpHost(tester);
    await reveal(tester);
    await tester.tap(find.byKey(const ValueKey('native-offer-not-now')));
    await tester.pumpAndSettle();
    expect(answers, [PlayerControlsStyle.classicGlass]);
    expect(hive.storedPlayerControlsStyle, PlayerControlsStyle.classicGlass);
  });

  iosTest('a barrier tap counts as Not now', (tester) async {
    await pumpHost(tester);
    await reveal(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(hive.storedPlayerControlsStyle, PlayerControlsStyle.classicGlass);
  });

  iosTest('the card appears once', (tester) async {
    await pumpHost(tester);
    await reveal(tester);
    expect(card, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('native-offer-not-now')));
    await tester.pumpAndSettle();
    await reveal(tester);
    expect(card, findsNothing);
    await reveal(tester);
    expect(card, findsNothing);
    expect(answers, hasLength(1));
  });

  iosTest('shown once even if it was never answered', (tester) async {
    await pumpHost(tester);
    await reveal(tester);
    expect(card, findsOneWidget);
    // The app dies with the card up: the settings survive, the answer not.
    await tester.pumpWidget(const SizedBox());
    await pumpHost(tester);
    await reveal(tester);
    expect(card, findsNothing);
  });
}
