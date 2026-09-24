import 'dart:convert';

/// The string a local notification carries back when it is tapped.
///
/// JSON. It used to be `k=v&k=v` in one place and JSON in another, so a tapped
/// airing reminder decoded to nothing. [decodeNotificationPayload] still reads
/// the old form: a notification posted by the previous build can sit in the
/// tray across the update.
String? encodeNotificationPayload(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return null;
  return jsonEncode({
    for (final e in data.entries)
      if (e.value != null) e.key: e.value is num || e.value is bool
          ? e.value
          : '${e.value}',
  });
}

Map<String, dynamic>? decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  final trimmed = payload.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
  }
  final out = <String, dynamic>{};
  for (final part in trimmed.split('&')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    try {
      out[Uri.decodeComponent(part.substring(0, i))] = Uri.decodeComponent(
        part.substring(i + 1),
      );
    } catch (_) {}
  }
  return out.isEmpty ? null : out;
}
