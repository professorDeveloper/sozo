/// HTTP field names are case-insensitive; later maps override earlier maps.
Map<String, String> mergeHttpHeaders(Iterable<Map<String, String>> maps) {
  final result = <String, String>{};
  for (final headers in maps) {
    for (final entry in headers.entries) {
      result.removeWhere(
        (key, _) => key.toLowerCase() == entry.key.toLowerCase(),
      );
      result[entry.key] = entry.value;
    }
  }
  return result;
}
