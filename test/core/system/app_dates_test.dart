// The language somebody reads an app in and the date order they can parse at a
// glance are not the same choice. Someone running the app in English in
// Tashkent still reads 22/09/2026, and 09/22/2026 in the middle of a download
// list is a number they have to stop and decode.
import 'package:flutter_test/flutter_test.dart';
// easy_localization re-exports intl, which is how the app itself reaches
// DateFormat. Same door here, rather than depending on a package the app does
// not declare.
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:soplay/core/system/app_dates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every locale's month names and default orders, which `DateFormat` only
  // has for `en` until they are loaded.
  setUpAll(initializeDateFormatting);

  final date = DateTime(2026, 9, 22);

  test('no override follows the language', () {
    expect(AppDates.format(date, locale: 'en'), contains('2026'));
    expect(AppDates.format(date, locale: 'en'), contains('22'));
    // The point of the default: two languages, two orders, neither chosen.
    expect(
      AppDates.format(date, locale: 'en'),
      isNot(AppDates.format(date, locale: 'ru')),
    );
  });

  test('and an override is honoured whatever the language', () {
    for (final locale in ['en', 'ru', 'uz', 'ar']) {
      expect(
        AppDates.format(date, locale: locale, pattern: 'dd/MM/yyyy'),
        '22/09/2026',
        reason: locale,
      );
    }
  });

  test('every offered pattern produces something different and readable', () {
    final seen = <String>{};
    for (final p in AppDates.choices) {
      final out = AppDates.format(date, locale: 'en', pattern: p);
      expect(out, contains('2026'), reason: p);
      expect(out.trim(), isNotEmpty, reason: p);
      expect(seen.add(out), isTrue, reason: 'two choices print the same: $out');
    }
  });

  test('a pattern that is not on the menu falls back to the language', () {
    // `DateFormat` does NOT reject a pattern it cannot read — it treats the
    // letters it does not know as literal text, so this would otherwise print
    // "not a pattern" with a couple of digits in it, on every date in the app.
    expect(
      DateFormat('not a pattern', 'en').format(date),
      contains('not'),
      reason: 'intl started rejecting bad patterns; the guard can be a catch',
    );
    expect(
      AppDates.format(date, locale: 'en', pattern: 'not a pattern'),
      AppDates.format(date, locale: 'en'),
    );
    // Including a pattern that WOULD work but was never offered: the menu is
    // the contract, so that nothing can arrive by way of a restored backup.
    expect(
      AppDates.format(date, locale: 'en', pattern: 'yyyy/dd/MM'),
      AppDates.format(date, locale: 'en'),
    );
  });

  test('the sample is a date whose parts cannot be confused', () {
    // "dd/MM/yyyy" means nothing to most people; "22/09/2026" is the question
    // they are actually being asked — so the day, the month and the year all
    // have to be different numbers.
    final sample = AppDates.sample('dd/MM/yyyy', 'en');
    expect(sample, '22/09/2026');
    final parts = sample.split('/').toSet();
    expect(parts, hasLength(3));
  });
}
