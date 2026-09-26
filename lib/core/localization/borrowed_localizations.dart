import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart' show DateFormat;

/// Flutter's own strings, for the languages Flutter does not ship.
///
/// The app's copy is translated by people and lives in
/// `assets/translations`; the words the FRAMEWORK owns — "Cancel" in a date
/// picker, the month names, "Back", the text-selection menu — come from
/// `flutter_localizations`, which ships a fixed set of locales. Cantonese and
/// both Kurdish languages are not in it.
///
/// The failure that produces is total and immediate, and it is not a missing
/// word: `GlobalMaterialLocalizations.delegate.isSupported(Locale('yue'))` is
/// false, so nothing resolves `MaterialLocalizations` at all and every
/// `AppBar` and `Scaffold` in the app throws "No MaterialLocalizations found"
/// the moment the language is chosen. Every widget test passes through this
/// because a bare `MaterialApp` in a test falls back to the English defaults.
///
/// `intl` has the same gap one layer down: `DateFormat.yMMMd('yue')` throws
/// "Invalid locale", because the date data Flutter loads covers only the
/// locales Flutter ships. Every screen that writes a date with the app's
/// locale — the profile header, the airing calendar, the backup list — threw
/// under Cantonese. So each language here also gets its neighbour's date data
/// registered under its own code, the first time its strings load.
///
/// Put these BEFORE the delegates `easy_localization` supplies: the first
/// delegate that claims a locale wins, and these claim nothing but the
/// languages in [_kBorrowed].
const List<LocalizationsDelegate<dynamic>> kBorrowedLocalizationsDelegates = [
  _BorrowedMaterialDelegate(),
  _BorrowedCupertinoDelegate(),
  _BorrowedWidgetsDelegate(),
];

/// The app languages whose framework strings are borrowed.
Iterable<String> get kBorrowedLanguages => _kBorrowed.keys;

/// What a language borrows, and from whom.
class _Borrow {
  const _Borrow({
    required this.framework,
    required this.dates,
    this.direction = TextDirection.ltr,
  });

  /// Whose button labels, tooltips and month names the framework shows.
  final Locale framework;

  /// Whose `intl` date data is registered under this language's code.
  final String dates;

  /// Which way the language reads. Flutter takes this from
  /// [WidgetsLocalizations], so it has to be stated here: a borrowed
  /// neighbour that reads the other way would mirror the whole app wrongly.
  final TextDirection direction;
}

const Map<String, _Borrow> _kBorrowed = {
  // Traditional Chinese: Hong Kong reads Traditional characters, so a date
  // picker that says 取消 is correct in Cantonese even though a Cantonese
  // speaker would not have written the app's own copy that way.
  'yue': _Borrow(
    framework: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    dates: 'zh_HK',
  ),
  // Both Kurdish languages borrow English. The obvious neighbours are the
  // wrong ones: Kurmanji readers live largely in Turkey and Sorani readers in
  // Iraq and Iran, and a Kurdish interface that falls back to Turkish, Arabic
  // or Persian in its date picker reads as the state language showing
  // through. English is neutral, and the few framework words it covers are
  // ones most readers of an English-first app already know.
  'ku': _Borrow(framework: Locale('en'), dates: 'en'),
  // Sorani is written in Arabic script and reads right to left, like `ar`:
  // English words, mirrored layout.
  'ckb': _Borrow(
    framework: Locale('en'),
    dates: 'en',
    direction: TextDirection.rtl,
  ),
};

/// Registers [code]'s date data as a copy of its neighbour's, once.
///
/// Called after `GlobalMaterialLocalizations` has loaded, which is what makes
/// Flutter's own date data available to copy from.
void _registerDates(String code, String from) {
  if (DateFormat.localeExists(code)) return;
  final source = DateFormat(DateFormat.YEAR, from);
  final symbols = DateSymbols.deserializeFromMap({
    ...source.dateSymbols.serializeToMap(),
    'NAME': code,
  });
  // The skeletons `DateFormat`'s named constructors ask for, each resolved to
  // the neighbour's pattern for it.
  final patterns = {
    for (final skeleton in _kSkeletons)
      skeleton: DateFormat(skeleton, from).pattern ?? skeleton,
  };
  initializeDateFormattingCustom(
    locale: code,
    symbols: symbols,
    patterns: patterns,
  );
}

const List<String> _kSkeletons = [
  DateFormat.DAY,
  DateFormat.ABBR_WEEKDAY,
  DateFormat.WEEKDAY,
  DateFormat.ABBR_STANDALONE_MONTH,
  DateFormat.STANDALONE_MONTH,
  DateFormat.NUM_MONTH,
  DateFormat.NUM_MONTH_DAY,
  DateFormat.NUM_MONTH_WEEKDAY_DAY,
  DateFormat.ABBR_MONTH,
  DateFormat.ABBR_MONTH_DAY,
  DateFormat.ABBR_MONTH_WEEKDAY_DAY,
  DateFormat.MONTH,
  DateFormat.MONTH_DAY,
  DateFormat.MONTH_WEEKDAY_DAY,
  DateFormat.ABBR_QUARTER,
  DateFormat.QUARTER,
  DateFormat.YEAR,
  DateFormat.YEAR_NUM_MONTH,
  DateFormat.YEAR_NUM_MONTH_DAY,
  DateFormat.YEAR_NUM_MONTH_WEEKDAY_DAY,
  DateFormat.YEAR_ABBR_MONTH,
  DateFormat.YEAR_ABBR_MONTH_DAY,
  DateFormat.YEAR_ABBR_MONTH_WEEKDAY_DAY,
  DateFormat.YEAR_MONTH,
  DateFormat.YEAR_MONTH_DAY,
  DateFormat.YEAR_MONTH_WEEKDAY_DAY,
  DateFormat.YEAR_ABBR_QUARTER,
  DateFormat.YEAR_QUARTER,
  DateFormat.HOUR24,
  DateFormat.HOUR24_MINUTE,
  DateFormat.HOUR24_MINUTE_SECOND,
  DateFormat.HOUR,
  DateFormat.HOUR_MINUTE,
  DateFormat.HOUR_MINUTE_SECOND,
  DateFormat.MINUTE,
  DateFormat.MINUTE_SECOND,
  DateFormat.SECOND,
];

class _BorrowedMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _BorrowedMaterialDelegate();

  @override
  bool isSupported(Locale locale) =>
      _kBorrowed.containsKey(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    final borrow = _kBorrowed[locale.languageCode]!;
    final strings = await GlobalMaterialLocalizations.delegate.load(
      borrow.framework,
    );
    _registerDates(locale.languageCode, borrow.dates);
    return strings;
  }

  @override
  bool shouldReload(_BorrowedMaterialDelegate old) => false;
}

class _BorrowedCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _BorrowedCupertinoDelegate();

  @override
  bool isSupported(Locale locale) =>
      _kBorrowed.containsKey(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(
        _kBorrowed[locale.languageCode]!.framework,
      );

  @override
  bool shouldReload(_BorrowedCupertinoDelegate old) => false;
}

class _BorrowedWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _BorrowedWidgetsDelegate();

  @override
  bool isSupported(Locale locale) =>
      _kBorrowed.containsKey(locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) async {
    final borrow = _kBorrowed[locale.languageCode]!;
    final strings = await GlobalWidgetsLocalizations.delegate.load(
      borrow.framework,
    );
    if (strings.textDirection == borrow.direction) return strings;
    // Only Sorani gets here: a right-to-left language borrowing English.
    assert(borrow.framework.languageCode == 'en');
    return const _RtlEnglishWidgets();
  }

  @override
  bool shouldReload(_BorrowedWidgetsDelegate old) => false;
}

/// English widget strings, read right to left: what Sorani borrows.
class _RtlEnglishWidgets extends DefaultWidgetsLocalizations {
  const _RtlEnglishWidgets();

  @override
  TextDirection get textDirection => TextDirection.rtl;
}
