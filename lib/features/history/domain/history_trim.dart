/// What history throws away when it has too much, and what it must not.
///
/// The old rule was one number: keep the 50 most recent rows. A row is one
/// EPISODE — the storage key is the content url plus the episode — while every
/// screen that reads history collapses it to one card per TITLE. So fifty rows
/// was never fifty things the viewer could see. Watch fifty episodes of one
/// series, which is under two cours of a weekly anime, and that series owned
/// the whole store: every other title was evicted, and Continue watching showed
/// a single card.
///
/// Two changes. The budget is large enough that per-episode rows are no longer
/// scarce, and the trim knows which row is a title's card and takes it last.
///
/// Pure: rows in, keys to delete out. No Hive, no clock.
library;

class HistoryTrim {
  /// Total rows kept.
  ///
  /// Generous on purpose, and it can afford to be: a row is a few hundred
  /// bytes, so this is well under a megabyte. Within a kept title the
  /// per-episode rows are what puts the watched mark on an episode list, and a
  /// viewer sixty episodes into a long series should still see the first fifty
  /// marked.
  static const int maxRows = 1500;

  /// The storage keys to delete, given every row currently held.
  ///
  /// [rows] need not be sorted. Each entry is a (key, contentUrl, watchedAt)
  /// triple — the only three things the decision depends on, so the caller's
  /// entity type does not have to reach this file.
  ///
  /// Two passes, and the order between them is the fix. The first drops the
  /// oldest rows that are NOT the most recent row of their title: episode 3 of
  /// a series the viewer is sixty episodes into is the cheapest thing in the
  /// store, because losing it costs a tick on an episode list and nothing else.
  /// Only if that is not enough does the second pass take whole titles, oldest
  /// last-watched first — and it has to exist, or a store of a thousand titles
  /// with one row each could never be trimmed at all.
  static List<String> keysToDrop(
    Iterable<({String key, String contentUrl, int watchedAt})> rows, {
    int maxRows = HistoryTrim.maxRows,
  }) {
    final all = rows.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    var over = all.length - maxRows;
    if (over <= 0) return const [];

    // The first row belonging to a title is that title's most recent, because
    // the list is sorted newest-first. That row is the title's card.
    final newestRowOfTitle = <String, String>{};
    for (final row in all) {
      newestRowOfTitle.putIfAbsent(row.contentUrl, () => row.key);
    }

    final drop = <String>{};

    // Oldest first, skipping every title's card.
    for (var i = all.length - 1; i >= 0 && over > 0; i--) {
      final row = all[i];
      if (newestRowOfTitle[row.contentUrl] == row.key) continue;
      drop.add(row.key);
      over--;
    }

    // Still over: what is left is one row per title, so a title has to go.
    for (var i = all.length - 1; i >= 0 && over > 0; i--) {
      final row = all[i];
      if (drop.add(row.key)) over--;
    }

    return drop.toList();
  }
}
