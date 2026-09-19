import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

/// The app's UI language, and the only place it is written.
///
/// ## Why this exists
///
/// The language used to live in two places that never spoke to each other.
/// `context.setLocale()` persists through `easy_localization`'s own storage and
/// is what the interface reads; `HiveService.saveLanguage()` is what the
/// subtitle translator falls back to and what the backend is told for push copy.
/// Only the settings screen wrote the second one, and nothing wrote it at
/// startup — so a German phone showed a German interface while Hive still said
/// `en`, and that user's subtitles and notifications quietly stayed English.
///
/// Both writes now go through [set], and [syncFromDevice] repairs accounts that
/// were already in the split state.
abstract final class AppLanguage {
  /// Native names on purpose: a person looking for their own language finds it
  /// fastest written the way they write it.
  static const names = <String, String>{
    'en': 'English',
    'uz': "O'zbekcha",
    'ru': 'Русский',
    'ar': 'العربية',
    'de': 'Deutsch',
    'nl': 'Nederlands',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'tr': 'Türkçe',
    'id': 'Bahasa Indonesia',
    'yue': '廣東話',
  };

  static String labelOf(String code) => names[code] ?? code;

  static const flags = <String, String>{
    'en': '🇬🇧',
    'uz': '🇺🇿',
    'ru': '🇷🇺',
    'ar': '🇸🇦',
    'de': '🇩🇪',
    'nl': '🇳🇱',
    'es': '🇪🇸',
    'pt': '🇵🇹',
    'fr': '🇫🇷',
    'tr': '🇹🇷',
    'id': '🇮🇩',
    'yue': '🇭🇰',
  };

  static String flagOf(String code) => flags[code] ?? '🌐';

  /// Switches the interface, and everything downstream of it.
  static Future<void> set(BuildContext context, String code) async {
    if (code != context.locale.languageCode) {
      await context.setLocale(Locale(code));
    }
    await getIt<HiveService>().saveLanguage(code);
    // Push copy is written server-side, so the server has to be told. Fire and
    // forget: a language change must not wait on the network, and the next
    // launch re-registers anyway.
    unawaited(getIt<NotificationService>().refreshRegistration());
  }

  /// Points Hive at the locale `easy_localization` actually resolved.
  ///
  /// Called once at startup. On a first launch the resolved locale comes from
  /// the device, not from anything the user picked, and Hive's own default is
  /// the string `'en'` — which is a real answer, not an absent one, so nothing
  /// downstream can tell "English" from "never asked".
  static Future<void> syncFromDevice(BuildContext context) async {
    final hive = getIt<HiveService>();
    final active = context.locale.languageCode;
    if (hive.getLanguage() == active) return;
    await hive.saveLanguage(active);
  }
}
