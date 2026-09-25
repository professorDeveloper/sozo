/// One setting a JavaScript source declares: Mangayomi's
/// `getSourcePreferences()` shapes, which the LNReader adapter also speaks.
sealed class SourcePreference {
  const SourcePreference({
    required this.key,
    required this.title,
    this.summary = '',
  });

  final String key;
  final String title;
  final String summary;

  /// Null for a shape this app does not draw; it is left out rather than
  /// shown as a control that does nothing.
  static SourcePreference? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = '${raw['key'] ?? ''}';
    if (key.isEmpty) return null;
    Map<String, dynamic>? body(String name) =>
        (raw[name] as Map?)?.cast<String, dynamic>();
    String title(Map<String, dynamic> b) => '${b['title'] ?? key}';
    String summary(Map<String, dynamic> b) => '${b['summary'] ?? ''}';
    List<String> strings(Object? v) => [
      for (final e in (v as List? ?? const [])) '$e',
    ];

    if (body('switchPreferenceCompat') ?? body('checkBoxPreference')
        case final b?) {
      return SwitchSourcePreference(
        key: key,
        title: title(b),
        summary: summary(b),
        initial: b['value'] == true,
      );
    }
    if (body('listPreference') case final b?) {
      final values = strings(b['entryValues']);
      final entries = strings(b['entries']);
      if (values.isEmpty || entries.length != values.length) return null;
      final index = (b['valueIndex'] as num?)?.toInt() ?? 0;
      return ListSourcePreference(
        key: key,
        title: title(b),
        summary: summary(b),
        entries: entries,
        values: values,
        initial: values[index.clamp(0, values.length - 1)],
      );
    }
    if (body('multiSelectListPreference') case final b?) {
      final values = strings(b['entryValues']);
      final entries = strings(b['entries']);
      if (values.isEmpty || entries.length != values.length) return null;
      return MultiSourcePreference(
        key: key,
        title: title(b),
        summary: summary(b),
        entries: entries,
        values: values,
        initial: strings(b['values']).toSet(),
      );
    }
    if (body('editTextPreference') case final b?) {
      return TextSourcePreference(
        key: key,
        title: title(b),
        summary: summary(b),
        initial: '${b['value'] ?? ''}',
      );
    }
    return null;
  }
}

class SwitchSourcePreference extends SourcePreference {
  const SwitchSourcePreference({
    required super.key,
    required super.title,
    super.summary,
    required this.initial,
  });
  final bool initial;

  bool read(Map<String, dynamic> saved) {
    final v = saved[key];
    return v is bool ? v : (v is String ? v == 'true' : initial);
  }
}

class ListSourcePreference extends SourcePreference {
  const ListSourcePreference({
    required super.key,
    required super.title,
    super.summary,
    required this.entries,
    required this.values,
    required this.initial,
  });
  final List<String> entries;
  final List<String> values;
  final String initial;

  String read(Map<String, dynamic> saved) {
    final v = saved[key];
    return v != null && values.contains('$v') ? '$v' : initial;
  }

  String labelOf(String value) {
    final i = values.indexOf(value);
    return i < 0 ? value : entries[i];
  }
}

class MultiSourcePreference extends SourcePreference {
  const MultiSourcePreference({
    required super.key,
    required super.title,
    super.summary,
    required this.entries,
    required this.values,
    required this.initial,
  });
  final List<String> entries;
  final List<String> values;
  final Set<String> initial;

  Set<String> read(Map<String, dynamic> saved) {
    final v = saved[key];
    return v is List ? {for (final e in v) '$e'} : initial;
  }
}

class TextSourcePreference extends SourcePreference {
  const TextSourcePreference({
    required super.key,
    required super.title,
    super.summary,
    required this.initial,
  });
  final String initial;

  String read(Map<String, dynamic> saved) {
    final v = saved[key];
    return v == null ? initial : '$v';
  }
}
