import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the four translation files against the two failures that reach users
/// as visible breakage rather than as a missing word.
void main() {
  const locales = ['en', 'ru', 'uz', 'ar'];

  Map<String, dynamic> load(String locale) => jsonDecode(
        File('assets/translations/$locale.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  Map<String, String> flatten(Map<String, dynamic> map, [String prefix = '']) {
    final out = <String, String>{};
    map.forEach((k, v) {
      final key = prefix.isEmpty ? k : '$prefix.$k';
      if (v is Map<String, dynamic>) {
        out.addAll(flatten(v, key));
      } else {
        out[key] = v.toString();
      }
    });
    return out;
  }

  /// `{}` and `{named}` — what the loader substitutes at runtime.
  List<String> tokens(String value) =>
      RegExp(r'\{[a-zA-Z_]*\}').allMatches(value).map((m) => m[0]!).toList()
        ..sort();

  /// Plural blocks legitimately differ in shape: Arabic has six categories and
  /// Russian four, so a language may carry keys English does not, and a form
  /// that names its own count ("قناتان" — exactly two) carries no placeholder.
  bool isPluralForm(String key) => const {
        'zero', 'one', 'two', 'few', 'many', 'other',
      }.contains(key.split('.').last);

  final english = flatten(load('en'));

  for (final locale in locales.where((l) => l != 'en')) {
    group(locale, () {
      final translated = flatten(load(locale));

      test('has every key English has', () {
        // A missing key falls back to English mid-sentence, which reads as the
        // app half-translated rather than as one string being absent.
        final missing = english.keys
            .where((k) => !translated.containsKey(k) && !isPluralForm(k))
            .toList()
          ..sort();
        expect(missing, isEmpty);
      });

      test('has no key English does not', () {
        // A stale key is dead weight nobody will ever notice is wrong.
        final extra = translated.keys
            .where((k) => !english.containsKey(k) && !isPluralForm(k))
            .toList()
          ..sort();
        expect(extra, isEmpty);
      });

      test('keeps every placeholder', () {
        // A dropped {} prints the sentence with the number missing; an invented
        // one prints the braces literally. Both are visible to the user and
        // neither is caught by anything else.
        final broken = <String>[];
        for (final entry in english.entries) {
          final other = translated[entry.key];
          if (other == null || isPluralForm(entry.key)) continue;
          if (!listEquals(tokens(entry.value), tokens(other))) {
            broken.add('${entry.key}: ${tokens(entry.value)} vs ${tokens(other)}');
          }
        }
        expect(broken, isEmpty);
      });

      test('has nothing blank', () {
        final blank = translated.entries
            .where((e) => e.value.trim().isEmpty)
            .map((e) => e.key)
            .toList();
        expect(blank, isEmpty);
      });
    });
  }
}

bool listEquals(List<String> a, List<String> b) =>
    a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((e) => e);
