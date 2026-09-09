// Checks that every translation key the code asks for exists in every locale.
//
//     dart run tool/check_translations.dart
//     dart run tool/check_translations.dart --unused    # also list dead keys
//
// ## Why this exists
//
// `easy_localization` resolves keys at RUNTIME. A key that was renamed in the
// code but not in the JSON, or added to `en.json` and forgotten in the other
// three, compiles perfectly and analyses clean. What happens instead is that
// the app renders the key itself — a user in Uzbek sees the literal text
// `downloads.export_hint` where a sentence should be, and nobody finds out
// until somebody screenshots it.
//
// The official ARB toolchain catches this at build time, and migrating to it
// is the real fix. It is also a rename of every `.tr()` call site in 600+
// files. This is the 5% of that work that catches 95% of the same bugs, and
// it runs in under a second.
//
// Exits non-zero when a key is missing, so CI can gate on it.

import 'dart:convert';
import 'dart:io';

/// The locale every other one is measured against.
///
/// Not because English matters more, but because a comparison needs a fixed
/// point: without one, four files that each miss a different key look
/// identically incomplete and none of them is wrong.
const String referenceLocale = 'en';

const String translationsDir = 'assets/translations';
const String sourceDir = 'lib';

/// Keys that are built at runtime and therefore never appear as a literal.
///
/// A dynamic key like `'mode.${mode.id}'.tr()` cannot be found by scanning,
/// and reporting its family as unused would train people to ignore the output.
/// Prefixes listed here are exempt from the unused check — never from the
/// missing check, which still applies to whatever the JSON actually declares.
const List<String> dynamicKeyPrefixes = [
  'mode.',
  'player.color_',
  'player.shader_',
  'quality.',
  'genre.',
];

void main(List<String> args) {
  final wantUnused = args.contains('--unused');

  final locales = _loadLocales();
  if (locales.isEmpty) {
    stderr.writeln('No translation files found in $translationsDir/');
    exit(2);
  }
  if (!locales.containsKey(referenceLocale)) {
    stderr.writeln('The reference locale "$referenceLocale" is missing.');
    exit(2);
  }

  final used = _scanUsedKeys();
  final reference = locales[referenceLocale]!;

  var failures = 0;

  // ---- 1. Keys the code asks for that no locale can answer ----------------
  final missingEverywhere = used.keys
      .where((k) => !reference.contains(k))
      .where((k) => !_isDynamic(k))
      .toList()
    ..sort();

  if (missingEverywhere.isNotEmpty) {
    failures += missingEverywhere.length;
    stdout.writeln('\n✗ Used in code, missing from $referenceLocale.json '
        '(${missingEverywhere.length}):');
    for (final key in missingEverywhere) {
      stdout.writeln('    $key');
      for (final where in used[key]!.take(3)) {
        stdout.writeln('      $where');
      }
    }
  }

  // ---- 2. Locales that have fallen behind the reference --------------------
  for (final entry in locales.entries) {
    if (entry.key == referenceLocale) continue;
    final missing = reference.difference(entry.value).toList()..sort();
    if (missing.isEmpty) continue;
    failures += missing.length;
    stdout.writeln('\n✗ ${entry.key}.json is missing ${missing.length} key(s) '
        'that $referenceLocale.json has:');
    for (final key in missing.take(40)) {
      stdout.writeln('    $key');
    }
    if (missing.length > 40) {
      stdout.writeln('    … and ${missing.length - 40} more');
    }
  }

  // ---- 3. Keys a locale has that the reference does not -------------------
  // Not a failure: a translator adding something ahead of the code is fine,
  // and so is a key left behind by a rename. Worth saying, not worth blocking.
  for (final entry in locales.entries) {
    if (entry.key == referenceLocale) continue;
    // Arabic has six plural categories and English has two, so a locale
    // carrying `…count.few` that English does not is correct CLDR, not drift.
    final extra = entry.value
        .difference(reference)
        .where((k) => !pluralForms.contains(k.split('.').last))
        .toList()
      ..sort();
    if (extra.isEmpty) continue;
    stdout.writeln('\n· ${entry.key}.json has ${extra.length} key(s) '
        'not in $referenceLocale.json:');
    for (final key in extra.take(10)) {
      stdout.writeln('    $key');
    }
  }

  // ---- 4. Dead keys, on request -------------------------------------------
  if (wantUnused) {
    final unused = reference
        .where((k) => !used.containsKey(k))
        .where((k) => !_isDynamic(k))
        .toList()
      ..sort();
    if (unused.isNotEmpty) {
      stdout.writeln('\n· Declared but never used (${unused.length}):');
      for (final key in unused) {
        stdout.writeln('    $key');
      }
      stdout.writeln('  (a key built at runtime looks unused here — add its '
          'prefix to dynamicKeyPrefixes in this file rather than deleting it)');
    }
  }

  stdout.writeln('\n${locales.length} locale(s), ${reference.length} key(s) in '
      '$referenceLocale, ${used.length} referenced from $sourceDir/.');

  if (failures == 0) {
    stdout.writeln('✓ Every key the code asks for exists in every locale.');
    exit(0);
  }
  stdout.writeln('✗ $failures problem(s).');
  exit(1);
}

bool _isDynamic(String key) =>
    dynamicKeyPrefixes.any((prefix) => key.startsWith(prefix));

/// Every locale file, as a flat set of dotted keys.
Map<String, Set<String>> _loadLocales() {
  final dir = Directory(translationsDir);
  if (!dir.existsSync()) return {};

  final out = <String, Set<String>>{};
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) continue;
      out[name] = _flatten(decoded).toSet();
    } on FormatException catch (e) {
      stderr.writeln('✗ ${file.path} is not valid JSON: ${e.message}');
      exit(2);
    }
  }
  return out;
}

/// The CLDR plural categories `easy_localization` understands.
///
/// A plural entry is a map whose children are these, and it is addressed by
/// the PARENT key: `'live_tv.channel_count'.plural(n)`. Treating it like any
/// other namespace made the checker report a working key as missing — and a
/// checker that cries wolf on correct code is worse than no checker.
const Set<String> pluralForms = {'zero', 'one', 'two', 'few', 'many', 'other'};

bool _isPluralNode(Map<String, dynamic> node) =>
    node.isNotEmpty &&
    node.keys.every(pluralForms.contains) &&
    node.values.every((v) => v is String);

/// `{"a": {"b": "x"}}` → `["a.b"]`.
///
/// Leaves, plus plural nodes, which are leaves as far as a call site is
/// concerned. A plain intermediate node is a namespace and resolves to
/// nothing.
Iterable<String> _flatten(Map<String, dynamic> node, [String prefix = '']) sync* {
  for (final entry in node.entries) {
    final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      if (_isPluralNode(value)) {
        yield key;
      } else {
        yield* _flatten(value, key);
      }
    } else {
      yield key;
    }
  }
}

/// Matches `'some.key'.tr(` and `"some.key".tr(`, plus `.plural(`.
///
/// Deliberately literal-only. A key assembled from a variable cannot be
/// checked without running the app, and pretending otherwise would produce
/// false confidence rather than false alarms.
final RegExp _trCall = RegExp(
  r'''(['"])([a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+)\1\s*\.\s*(?:tr|plural)\s*\(''',
);

/// Every literal key referenced from Dart, with where it was found.
Map<String, List<String>> _scanUsedKeys() {
  final out = <String, List<String>>{};
  final dir = Directory(sourceDir);
  if (!dir.existsSync()) return out;

  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final match in _trCall.allMatches(lines[i])) {
        final key = match.group(2)!;
        out.putIfAbsent(key, () => []).add('${file.path}:${i + 1}');
      }
    }
  }
  return out;
}
