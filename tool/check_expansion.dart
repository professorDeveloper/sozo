// Ranks translation keys by how much longer they got than English.
//
//     dart run tool/check_expansion.dart            # the worst 40, all locales
//     dart run tool/check_expansion.dart de 100     # the worst 100 in German
//
// ## Why this exists
//
// German and Dutch run 10-35% longer than English, and short button labels are
// worse than that: "Settings" becomes "Einstellungen" (+67%), "Download"
// becomes "Herunterladen" (+150%). A `Text` inside a fixed-width `SizedBox` is
// then clipped SILENTLY in a release build — no exception, no log line, nothing
// in the console. Nobody files a bug about a half-cut button; they just decide
// the app looks cheap.
//
// Overflow is not random: it happens where the most-expanded string meets the
// tightest box. Sorting by expansion ratio therefore names the screens worth
// opening in German, instead of auditing all sixty of them.
//
// Only keys whose English side is short are ranked. A paragraph growing 40%
// wraps to another line; a six-character label growing 40% runs out of button.

import 'dart:convert';
import 'dart:io';

const translationsDir = 'assets/translations';
const referenceLocale = 'en';

/// Above this, the English text is a sentence and wrapping absorbs the growth.
const int shortEnough = 24;

/// Worth looking at. Below this the growth fits in the padding.
const double minRatio = 1.15;

void main(List<String> args) {
  final locale = args.isNotEmpty && !RegExp(r'^\d+$').hasMatch(args.first)
      ? args.first
      : null;
  final limit = int.tryParse(args.lastOrNull ?? '') ?? 40;

  final english = _load(referenceLocale);
  if (english == null) {
    stderr.writeln('No $referenceLocale.json in $translationsDir/');
    exit(2);
  }

  final locales = locale != null
      ? [locale]
      : (Directory(translationsDir)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.json'))
          .map((n) => n.substring(0, n.length - 5))
          .where((l) => l != referenceLocale)
          .toList()
        ..sort());

  final rows = <_Row>[];
  for (final code in locales) {
    final translated = _load(code);
    if (translated == null) {
      stderr.writeln('Missing $code.json');
      exit(2);
    }
    english.forEach((key, source) {
      if (source.isEmpty || source.length > shortEnough) return;
      final value = translated[key];
      if (value == null || value == source) return;
      final ratio = value.length / source.length;
      if (ratio < minRatio) return;
      rows.add(_Row(code, key, source, value, ratio));
    });
  }

  rows.sort((a, b) => b.ratio.compareTo(a.ratio));

  final shown = rows.take(limit).toList();
  stdout.writeln(
    'Top $limit of ${rows.length} short strings that grew by ${(minRatio - 1) * 100}% or more:\n',
  );
  for (final row in shown) {
    final pct = ((row.ratio - 1) * 100).round();
    stdout.writeln('+$pct%\t${row.locale}\t${row.key}');
    stdout.writeln('\t\t"${row.source}" -> "${row.value}"');
  }

  // Grouped by key, because one key overflowing in four languages is one screen
  // to fix, not four.
  final byKey = <String, int>{};
  for (final row in rows) {
    byKey[row.key] = (byKey[row.key] ?? 0) + 1;
  }
  final worst = byKey.entries.where((e) => e.value >= 4).map((e) => e.key).toList()..sort();
  if (worst.isNotEmpty) {
    stdout.writeln('\n${worst.length} key(s) grow in four or more locales:');
    for (final key in worst) {
      stdout.writeln('  $key');
    }
  }
}

Map<String, String>? _load(String locale) {
  final file = File('$translationsDir/$locale.json');
  if (!file.existsSync()) return null;
  final out = <String, String>{};
  void walk(Map<String, dynamic> node, String prefix) {
    node.forEach((key, value) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        walk(value, path);
      } else {
        out[path] = value.toString();
      }
    });
  }

  walk(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>, '');
  return out;
}

class _Row {
  _Row(this.locale, this.key, this.source, this.value, this.ratio);
  final String locale;
  final String key;
  final String source;
  final String value;
  final double ratio;
}
