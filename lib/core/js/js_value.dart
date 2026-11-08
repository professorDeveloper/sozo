import 'dart:convert';

/// An extractor's answer as plain JSON types, whichever platform delivered it.
///
/// Android hands `callAsyncJavaScript` results over as JSON text, which decodes
/// to `Map<String, dynamic>` all the way down. iOS and macOS pass WebKit's
/// objects through the platform channel instead, so every nested object arrives
/// as `Map<Object?, Object?>`, and the models' `as Map<String, dynamic>` casts
/// throw on the first nested card. A shallow `cast` only fixes the top level.
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
  if (value is! Map) return null;
  return _object(value);
}

Map<String, dynamic> _object(Map<dynamic, dynamic> raw) => {
  for (final e in raw.entries)
    if (e.key != null) '${e.key}': _plain(e.value),
};

Object? _plain(Object? value) {
  if (value is Map) return _object(value);
  if (value is List) return value.map(_plain).toList();
  return value;
}
