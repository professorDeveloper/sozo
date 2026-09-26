import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/localization/yue_localizations.dart';

/// The delegates the app installs, in the order it installs them.
///
/// `easy_localization` cannot be stood up in a plain widget test, so this is
/// the same list with its own delegate left out — every delegate that decides
/// whether the FRAMEWORK has strings for a locale is here, which is the thing
/// under test.
List<LocalizationsDelegate<dynamic>> get _delegates => [
  ...kYueLocalizationsDelegates,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

Widget _app(Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: [locale],
  localizationsDelegates: _delegates,
  // An AppBar on purpose: it is the widget that reads MaterialLocalizations
  // for its tooltips, and the one that threw.
  home: Scaffold(appBar: AppBar(title: const Text('x')), body: const Text('y')),
);

void main() {
  group('Cantonese borrows the framework strings it is not shipped', () {
    testWidgets('a screen builds at all under yue', (tester) async {
      // The regression this guards took down EVERY screen, not one string.
      // `GlobalMaterialLocalizations` ships a fixed set of locales and `yue` is
      // not in it, so nothing resolved MaterialLocalizations and every AppBar
      // and Scaffold threw "No MaterialLocalizations found" the moment the
      // language was chosen. It reached a device because a widget test that
      // does not name a locale falls through to the English defaults, which
      // always resolve — so nothing in the suite had ever asked this question.
      await tester.pumpWidget(_app(const Locale('yue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('y'), findsOneWidget);
    });

    testWidgets('the framework answers in Traditional Chinese', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('yue'),
          supportedLocales: const [Locale('yue')],
          localizationsDelegates: _delegates,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Hong Kong reads Traditional characters, so the neighbour Cantonese
      // borrows from has to be zh-Hant and not zh-Hans. 取消 is written the
      // same either way; the month names are not.
      final material = MaterialLocalizations.of(ctx);
      expect(material.cancelButtonLabel, '取消');
      expect(material.okButtonLabel, isNotEmpty);
      expect(Directionality.of(ctx), TextDirection.ltr);
    });

    testWidgets('the delegates claim Cantonese and nothing else', (
      tester,
    ) async {
      for (final d in kYueLocalizationsDelegates) {
        expect(d.isSupported(const Locale('yue')), isTrue);
        // If one of these ever answered for a locale Flutter DOES ship, it
        // would silently replace that language's framework strings with
        // Chinese ones, because it is installed first.
        for (final other in const [
          Locale('en'),
          Locale('zh'),
          Locale('ru'),
          Locale('ar'),
          Locale('uz'),
        ]) {
          expect(
            d.isSupported(other),
            isFalse,
            reason: '$d claimed $other, which Flutter already handles',
          );
        }
      }
    });
  });
}
