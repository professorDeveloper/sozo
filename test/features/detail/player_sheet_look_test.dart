import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/presentation/widgets/player_sheet_look.dart';

Widget _app(Widget child, {TextDirection dir = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(body: child),
      ),
    );

class _Opener extends StatelessWidget {
  const _Opener({required this.ios});

  final bool ios;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showPlayerSheet<void>(
      context: context,
      ios: ios,
      builder: (_) => Builder(
        builder: (inner) =>
            Text(PlayerSheetLook.of(inner) ? 'ios rows' : 'flutter rows'),
      ),
    ),
    child: const Text('open'),
  );
}

/// An iPhone's screen: a wider one gets the iPad's centred dialog.
void _phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('a player sheet', () {
    testWidgets('off the iOS path is the sheet it always was', (tester) async {
      await tester.pumpWidget(_app(const _Opener(ios: false)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('flutter rows'), findsOneWidget);
      expect(find.byType(IosSheetFrame), findsNothing);
      expect(find.byType(IosSheetGrabber), findsNothing);
    });

    testWidgets('on the iOS path has the grabber, the corners and the look', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_app(const _Opener(ios: true)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('ios rows'), findsOneWidget);
      expect(find.byType(IosSheetFrame), findsOneWidget);
      expect(find.byType(IosSheetGrabber), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('an iOS row', () {
    testWidgets('a choice reads out as selected, one of a set', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(
          IosSheetGroup(
            children: [
              IosSheetRow(
                title: '1080p',
                accessory: IosRowAccessory.check,
                selected: true,
                choice: true,
                onTap: () => taps++,
              ),
              IosSheetRow(
                title: '720p',
                accessory: IosRowAccessory.check,
                choice: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('1080p')),
        matchesSemantics(
          label: '1080p',
          isButton: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('720p')),
        matchesSemantics(
          label: '720p',
          isButton: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(find.text('1080p'));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('a group draws one hairline between each two rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const IosSheetGroup(
            children: [
              IosSheetRow(title: 'a'),
              IosSheetRow(title: 'b'),
              IosSheetRow(title: 'c'),
            ],
          ),
        ),
      );
      final hairlines = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == IosSheet.separator,
      );
      expect(hairlines, findsNWidgets(2));
    });

    testWidgets('the check stands at the trailing edge, in RTL too', (
      tester,
    ) async {
      Future<double> checkX(TextDirection dir) async {
        await tester.pumpWidget(
          _app(
            const IosSheetRow(
              title: 'Auto',
              accessory: IosRowAccessory.check,
              selected: true,
              choice: true,
            ),
            dir: dir,
          ),
        );
        return tester.getCenter(find.byType(Icon)).dx;
      }

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(await checkX(TextDirection.ltr), greaterThan(width / 2));
      expect(await checkX(TextDirection.rtl), lessThan(width / 2));
    });

    testWidgets('a header closes through its own callback', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        _app(IosSheetHeader(title: 'Quality', onClose: () => closed++)),
      );
      expect(find.text('Quality'), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      expect(closed, 1);
    });
  });
}
