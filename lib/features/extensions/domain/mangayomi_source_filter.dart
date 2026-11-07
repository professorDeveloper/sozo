import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// The filters shared by the installed list and the source picker.
class MangayomiSourceFilter {
  const MangayomiSourceFilter({
    this.query = '',
    this.type,
    this.languages = const [],
    this.includeNsfw = true,
  });

  final String query;

  /// Null means every type.
  final MangayomiItemType? type;

  /// Empty means every language. Sources tagged `all` match any selection.
  final List<String> languages;
  final bool includeNsfw;

  bool matches(MangayomiSource s) {
    if (!includeNsfw && s.isNsfw) return false;
    if (type != null && s.itemType != type) return false;
    if (!srclang.langMatches(s.lang, languages)) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) ||
        s.baseUrl.toLowerCase().contains(q);
  }

  /// Matching sources sorted by name, then language.
  List<MangayomiSource> apply(Iterable<MangayomiSource> sources) =>
      sources.where(matches).toList()..sort(compareByName);

  static int compareByName(MangayomiSource a, MangayomiSource b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.lang.compareTo(b.lang);
  }

  /// How many of [sources] carry each normalised language code.
  static Map<String, int> languageCounts(Iterable<MangayomiSource> sources) {
    final out = <String, int>{};
    for (final s in sources) {
      final key = srclang.normalizeLang(s.lang);
      if (key.isEmpty) continue;
      out.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  /// The selection after the user taps [code]; `all` clears it.
  static List<String> toggleLanguage(List<String> selected, String code) {
    if (code == srclang.kAllLanguages) return const [];
    final next = List<String>.from(selected);
    if (!next.remove(code)) next.add(code);
    return next;
  }
}
