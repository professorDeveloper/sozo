import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:soplay/core/localization/borrowed_localizations.dart';

/// The delegates the app installs, in the order it installs them.
///
/// `easy_localization` cannot be stood up in a plain widget test, so this is
/// the same list with its own delegate left out — every delegate that decides
/// whether the FRAMEWORK has strings for a locale is here, which is the thing
/// under test.
List<LocalizationsDelegate<dynamic>> get _delegates => [
  ...kBorrowedLocalizationsDelegates,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

Widget _app(Locale locale, {required WidgetBuilder builder}) => MaterialApp(
  locale: locale,
  supportedLocales: [locale],
  localizationsDelegates: _delegates,
  // An AppBar on purpose: it is the widget that reads MaterialLocalizations
  // for its tooltips, and the one that threw.
  home: Scaffold(
    appBar: AppBar(title: const Text('x')),
    body: Builder(builder: builder),
  ),
);

void main() {
  test('the borrowed set is Cantonese and both Kurdish languages', () {
    expect(kBorrowedLanguages.toSet(), {'yue', 'ku', 'ckb'});
  });

  for (final (code, cancel, direction) in const [
    // Hong Kong reads Traditional characters, so the neighbour Cantonese
    // borrows from has to be zh-Hant and not zh-Hans.
    ('yue', '取消', TextDirection.ltr),
    ('ku', 'Cancel', TextDirection.ltr),
    // Sorani is written in Arabic script: English words, mirrored layout.
    ('ckb', 'Cancel', TextDirection.rtl),
  ]) {
    group(code, () {
      testWidgets('a screen builds, reads $direction, and borrows its words', (
        tester,
      ) async {
        // The regression this guards took down EVERY screen, not one string.
        // `GlobalMaterialLocalizations` ships a fixed set of locales, and a
        // language outside it resolved no MaterialLocalizations at all, so
        // every AppBar and Scaffold threw "No MaterialLocalizations found" the
        // moment the language was chosen. It reached a device because a
        // widget test that does not name a locale falls through to the English
        // defaults, which always resolve.
        late BuildContext ctx;
        await tester.pumpWidget(
          _app(
            Locale(code),
            builder: (c) {
              ctx = c;
              return const Text('y');
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('y'), findsOneWidget);
        expect(MaterialLocalizations.of(ctx).cancelButtonLabel, cancel);
        expect(Directionality.of(ctx), direction);
      });

      testWidgets('dates format in the app locale instead of throwing', (
        tester,
      ) async {
        // `DateFormat.yMMMd(context.locale.toString())` is how a dozen screens
        // write a date, and for a locale Flutter does not ship it threw
        // "Invalid locale" until its date data was registered.
        late BuildContext ctx;
        await tester.pumpWidget(
          _app(
            Locale(code),
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        );
        await tester.pumpAndSettle();
        final at = DateTime(2026, 9, 26, 18, 5);
        final locale = Localizations.localeOf(ctx).toString();
        expect(DateFormat.yMMMd(locale).format(at), contains('2026'));
        expect(DateFormat.Hm(locale).format(at), '18:05');
        expect(DateFormat.EEEE(locale).format(at), isNotEmpty);
      });
    });
  }

  testWidgets('the delegates claim no language Flutter already ships', (
    tester,
  ) async {
    for (final d in kBorrowedLocalizationsDelegates) {
      for (final code in kBorrowedLanguages) {
        expect(d.isSupported(Locale(code)), isTrue);
      }
      // If one of these ever answered for a locale Flutter DOES ship, it would
      // silently replace that language's framework strings, because it is
      // installed first.
      for (final other in const [
        Locale('en'),
        Locale('zh'),
        Locale('ru'),
        Locale('ar'),
        Locale('fa'),
        Locale('tr'),
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
}
