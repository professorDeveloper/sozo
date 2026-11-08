import 'dart:convert';

/// An extractor's answer as plain JSON types, whichever platform delivered it.
///
/// Android hands `callAsyncJavaScript` results over as JSON text, which decodes
/// to `Map<String, dynamic>` all the way down. iOS and macOS pass WebKit's
/// objects through the platform channel instead, so every nested object arrives
/// as `Map<Object?, Object?>`, and the models' `as Map<String, dynamic>` casts
/// throw on the first nested card. A shallow `cast` only fixes the top level.
///
/// WebKit also hands every JavaScript number over as a double, where JSON text
/// gives `1` as an int. Whole numbers are turned back into ints so a page
/// number reads the same on both platforms.
Map<String, dynamic>? jsObjectFrom(Object? value) {
  if (value == null) return null;
  if (value is String) {
    if (value.isEmpty || value == 'null') return null;
    try {
      value = jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
  return jsonMap(value);
}

/// [value] as a `Map<String, dynamic>` with plain JSON types all the way down,
/// or null when it is not a map. For maps from a platform channel or a Hive
/// box, which arrive as `Map<Object?, Object?>` or `Map<dynamic, dynamic>`.
Map<String, dynamic>? jsonMap(Object? value) =>
    value is Map ? _object(value) : null;

/// The maps in [value], each as [jsonMap] gives it. Anything else in the list
/// is skipped, and a value that is not a list gives an empty one.
List<Map<String, dynamic>> jsonMaps(Object? value) => [
  if (value is List)
    for (final e in value)
      if (e is Map) _object(e),
];

Map<String, dynamic> _object(Map<dynamic, dynamic> raw) => {
  for (final e in raw.entries)
    if (e.key != null) '${e.key}': _plain(e.value),
};

Object? _plain(Object? value) {
  if (value is Map) return _object(value);
  if (value is List) return value.map(_plain).toList();
  if (value is double &&
      value.isFinite &&
      value == value.truncateToDouble() &&
      value.abs() <= 9007199254740991) {
    return value.toInt();
  }
  return value;
}

/// A whole number from a number or from numeric text, such as a count a source
/// sends as `"12"`.
int? jsonInt(Object? value) {
  final n = value is String ? num.tryParse(value.trim()) : value;
  return n is num && n.isFinite ? n.toInt() : null;
}

/// Trimmed text from a string or a number, or null when there is none.
String? jsonText(Object? value) {
  if (value is! String && value is! num) return null;
  final s = '$value'.trim();
  return s.isEmpty ? null : s;
}
