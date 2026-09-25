import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';

/// How this app writes a date.
///
/// Every absolute date used to go through `DateFormat.yMMMd(locale)`, which
/// takes its ordering from the app's language. That is the right default and
/// the wrong rule: the language somebody reads an app in and the date order
/// they can parse at a glance are not the same choice. Someone who runs the
/// app in English in Tashkent still reads 22/09/2026, and `09/22/2026` in the
/// middle of a download list is a number they have to stop and decode.
///
/// So the language remains the default, and anyone it does not suit can say
/// so once. Stored as the pattern itself rather than as an enum index, so an
/// old stored value keeps meaning what it meant and a format this app has not
/// thought of is one string away.
class AppDates {
  const AppDates._();

  /// The empty pattern: whatever the app's language does. Not a format in the
  /// list of formats — it is the absence of an override.
  static const String followLanguage = '';

  /// What the settings screen offers, in the order it offers them.
  ///
  /// Deliberately short. This is a preference for people whose language gets
  /// it wrong, not a date-pattern editor, and every extra row is another thing
  /// to read past for everybody it was already right for.
  static const List<String> choices = [
    followLanguage,
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'yyyy-MM-dd',
    'd MMM yyyy',
  ];

  /// A date, written the way this install writes dates.
  ///
  /// [context] supplies the language, which is still what decides month names
  /// and the default ordering. An override only ever changes the ORDER and the
  /// separators; it never forces a language on the words inside.
  static String short(BuildContext context, DateTime at) =>
      format(at, locale: context.locale.toString(), pattern: pattern);

  /// The stored override, or [followLanguage].
  ///
  /// Read through `getIt` rather than taken as an argument because this is
  /// called from a dozen leaf widgets, and threading a service down to each of
  /// them to answer "how do you write a date" is a worse trade than the lookup.
  static String get pattern {
    final hive = getIt.isRegistered<HiveService>()
        ? getIt<HiveService>()
        : null;
    return hive?.dateFormatPattern ?? followLanguage;
  }

  /// The formatting itself, with nothing to look up.
  ///
  /// Separated so it can be tested without a Hive box or a BuildContext: what
  /// is worth asserting is that a pattern is honoured and that a bad one falls
  /// back rather than throwing, and neither needs the app running.
  static String format(
    DateTime at, {
    required String locale,
    String pattern = followLanguage,
  }) {
    // Checked against the menu, not merely tried. `DateFormat` does not
    // reject a pattern it cannot read — it treats the letters it does not know
    // as literal text, so "not a pattern" formats to "not a pattern" with a
    // couple of digits in it rather than throwing. A stored value from a
    // future version or from somebody's edited backup would print that, on
    // every date in the app, with nothing to catch.
    if (!choices.contains(pattern)) return DateFormat.yMMMd(locale).format(at);
    if (pattern.isEmpty) return DateFormat.yMMMd(locale).format(at);
    return DateFormat(pattern, locale).format(at);
  }

  /// What to show in the settings row for [pattern].
  ///
  /// The pattern's own output, for a date whose parts cannot be confused with
  /// each other — the 22nd of a month that is not the 22nd, in a year that is
  /// neither. "dd/MM/yyyy" means nothing to most people; "22/09/2026" is the
  /// question they are actually being asked.
  static String sample(String pattern, String locale) =>
      format(_sampleDate, locale: locale, pattern: pattern);

  static final DateTime _sampleDate = DateTime(2026, 9, 22);
}
