/// Where a source files in an alphabetical index, and what the strip shows.
///
/// Split out of the widget because this is the part that can be wrong: the
/// bucketing of names that do not start with a Latin letter, and collapsing a
/// list of per-row letters into the chips actually worth showing.
library;

/// The letter [name] files under.
///
/// Anything outside A–Z shares one bucket. A strip with a chip per script is
/// longer than the list it indexes, and these lists are sorted by a name the
/// ecosystem chose — mostly Latin, occasionally not.
String indexLetterOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '#';
  final first = trimmed[0].toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(first) ? first : '#';
}

/// The chips for a list already in display order.
///
/// Collapses runs rather than taking a set: the strip has to follow the list's
/// own order, and a set would reorder it — or silently merge a letter that
/// appears twice because the list is not perfectly sorted.
List<String> indexLetters(Iterable<String> letters) {
  final out = <String>[];
  for (final letter in letters) {
    if (out.isEmpty || out.last != letter) out.add(letter);
  }
  return out;
}

/// Orders two source names for an A–Z index.
///
/// The index strip was drawn over the list in whatever order the backend sent
/// it, so the chips read "V A I U A T K Y A P H" — a letter per run, over a
/// list with no runs. An alphabetical index only means anything over an
/// alphabetical list.
///
/// Names outside A–Z sort last as one block, matching the single '#' bucket
/// [indexLetterOf] puts them in.
int compareForIndex(String a, String b) {
  final la = indexLetterOf(a);
  final lb = indexLetterOf(b);
  if (la != lb) {
    if (la == '#') return 1;
    if (lb == '#') return -1;
    return la.compareTo(lb);
  }
  return a.toLowerCase().compareTo(b.toLowerCase());
}
