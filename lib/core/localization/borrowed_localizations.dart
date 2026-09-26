import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter's own strings, for a language Flutter does not ship.
///
/// The app's copy is translated by people and lives in
/// `assets/translations`; the words the FRAMEWORK owns — "Cancel" in a date
/// picker, the month names, "Back", the text-selection menu — come from
/// `flutter_localizations`, which ships a fixed set of locales. Cantonese is
/// not one of them.
///
/// The failure that produces is total and immediate, and it is not a missing
/// word: `GlobalMaterialLocalizations.delegate.isSupported(Locale('yue'))` is
/// false, so nothing resolves `MaterialLocalizations` at all and every
/// `AppBar` and `Scaffold` in the app throws "No MaterialLocalizations found"
/// the moment the language is chosen. Every widget test passes through this
/// because a bare `MaterialApp` in a test falls back to the English defaults.
///
/// So Cantonese borrows Traditional Chinese for the framework's own strings.
/// That is the right neighbour rather than a convenient one: Hong Kong reads
/// Traditional characters, and a date picker that says 取消 is correct in
/// Cantonese even though a Cantonese speaker would not have written the app's
/// own copy that way.
///
/// Put these BEFORE the delegates `easy_localization` supplies: the first
/// delegate that claims a locale wins, and these claim nothing but `yue`.
const List<LocalizationsDelegate<dynamic>> kYueLocalizationsDelegates = [
  _YueMaterialDelegate(),
  _YueCupertinoDelegate(),
  _YueWidgetsDelegate(),
];

/// The locale whose framework strings Cantonese borrows.
const Locale _borrowed = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
);

const String _yue = 'yue';

class _YueMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _YueMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == _yue;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_borrowed);

  @override
  bool shouldReload(_YueMaterialDelegate old) => false;
}

class _YueCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _YueCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == _yue;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_borrowed);

  @override
  bool shouldReload(_YueCupertinoDelegate old) => false;
}

class _YueWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _YueWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == _yue;

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(_borrowed);

  @override
  bool shouldReload(_YueWidgetsDelegate old) => false;
}
