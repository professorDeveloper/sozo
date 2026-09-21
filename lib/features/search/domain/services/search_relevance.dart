import 'package:soplay/features/home/domain/entities/movie.dart';

/// How well a catalogue result answers the query that produced it.
///
/// ## Why the client has to do this at all
///
/// A search here is a fan-out to third-party catalogues, and several of them
/// match on more than the title — a description, a tag list, an alias field.
/// That is usually a feature: it is how "one piece" finds *Van Pis*, the Uzbek
/// dub, whose title shares not one letter with the query. It is also how
/// "naruto" finds *Learn To Draw APK* and how "aot" fills a screen with
/// unrelated Uzbek films, because three letters occur inside a word somewhere
/// in a synopsis.
///
/// The app cannot fix those catalogues and must not pretend the junk is not
/// there. What it can do is put the real answer first.
///
/// ## Rank, do not filter
///
/// Scoring is used for **ordering**, and a zero score never removes a row on
/// its own. *Van Pis* scores zero against "one piece" and is the single most
/// correct result in the set — a relevance filter would delete exactly the
/// results that justify having many sources. Dropping is reserved for
/// [looksUnsearched], which fires on a different signal entirely.
class SearchRelevance {
  const SearchRelevance._();

  /// Words that carry no signal in a title match. Kept deliberately short: a
  /// long stop list starts eating real title words ("Movie" is in half the
  /// anime canon) and the cost of a useless token is only a diluted score.
  static const Set<String> _stopWords = {
    'the', 'and', 'a', 'an', 'of', 'season', 'episode', 'part',
    'sub', 'subbed', 'dub', 'dubbed', 'watch', 'online', 'free',
  };

  /// A batch this size or larger with nothing matching is a catalogue dump.
  ///
  /// The number separates the two shapes seen in practice. A source that
  /// searched and found only an aliased match returns one or two rows; a source
  /// that ignored the query returns a full page — 16, 18, 26 rows of whatever
  /// it lists by default. Below this, "no token matched" is far more likely to
  /// mean the match was by alias than that the search was ignored.
  static const int _dumpSize = 6;

  /// A token has to be this long before a substring match counts for anything.
  ///
  /// "aot" is the worked example: three letters land inside ordinary words in
  /// every language, and letting them score turns a whole page of unrelated
  /// films into plausible-looking results.
  static const int _minSubstringToken = 4;

  /// Query words a genuine title match would plausibly contain.
  ///
  /// Empty for a query written entirely in a non-Latin script, which disables
  /// scoring rather than letting it rank everything at zero — the order the
  /// source chose is a better answer than an order this cannot compute.
  static Set<String> tokensOf(String query) => normalize(query)
      .split(' ')
      .where((t) => t.length >= 2 && !_stopWords.contains(t))
      .toSet();

  /// Lowercased, punctuation dropped, whitespace collapsed.
  ///
  /// Unicode-aware rather than an alphabet whitelist. The whitelist kept Latin,
  /// Cyrillic and Arabic and deleted everything else — so a Japanese, Korean,
  /// Chinese, Thai, Greek or Hebrew title normalised to the EMPTY STRING and
  /// scored zero against itself. On an app whose catalogue is largely Japanese
  /// that is not a ranking quirk; it is three separate failures downstream:
  /// such a title sorts last in every search, [looksUnsearched] can delete a
  /// whole page of correct results as a catalogue dump, and the weak-results
  /// banner is stapled over answers that were right.
  ///
  /// [TitleMatch.normalise] fixed the same bug in the same way and says so; the
  /// two are deliberately identical here.
  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N} ]+', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');

  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(_punctuation, ' ')
      .replaceAll(_spaces, ' ')
      .trim();

  /// Which writing systems [text] is made of.
  ///
  /// Only the distinctions that decide whether two strings could possibly match
  /// by the letter comparisons below: a romaji title and the same title in
  /// katakana share no characters at all, so a score of zero between them means
  /// nothing about whether the source answered the question.
  static Set<String> scriptsOf(String text) {
    final out = <String>{};
    for (final rune in text.runes) {
      if (rune >= 0x3040 && rune <= 0x30FF) {
        out.add('kana');
      } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
        out.add('han');
      } else if (rune >= 0xAC00 && rune <= 0xD7AF ||
          rune >= 0x1100 && rune <= 0x11FF) {
        out.add('hangul');
      } else if (rune >= 0x0E00 && rune <= 0x0E7F) {
        out.add('thai');
      } else if (rune >= 0x0400 && rune <= 0x04FF) {
        out.add('cyrillic');
      } else if (rune >= 0x0590 && rune <= 0x05FF) {
        out.add('hebrew');
      } else if (rune >= 0x0600 && rune <= 0x06FF) {
        out.add('arabic');
      } else if (rune >= 0x0370 && rune <= 0x03FF) {
        out.add('greek');
      } else if (rune >= 0x41 && rune <= 0x5A ||
          rune >= 0x61 && rune <= 0x7A) {
        out.add('latin');
      }
    }
    return out;
  }

  /// 0.0 (nothing in the title relates to the query) to 1.0 (it is the query).
  ///
  /// The bands are ordered by how sure the match is, not by how much of the
  /// title was used: an exact title beats a prefix beats a substring beats
  /// scattered words. Within the last band, a whole word counts fully and a
  /// substring counts a quarter, because "titan" inside "Attack on Titan" is
  /// evidence and "aot" inside "Bo'zqir" is a coincidence.
  static double score(String title, String query) {
    final t = normalize(title);
    final q = normalize(query);
    if (t.isEmpty || q.isEmpty) return 0;
    if (t == q) return 1;
    if (t.startsWith('$q ')) return 0.9;
    if (t.contains(q)) return 0.8;

    final tokens = tokensOf(query);
    if (tokens.isEmpty) return 0;
    final words = t.split(' ').toSet();

    var hits = 0.0;
    for (final token in tokens) {
      if (words.contains(token)) {
        hits += 1;
      } else if (token.length >= _minSubstringToken && t.contains(token)) {
        hits += 0.25;
      }
    }
    if (hits == 0) return 0;
    // Capped below the substring band so a partial word match can never
    // outrank a title that literally contains the query.
    return 0.1 + 0.65 * (hits / tokens.length);
  }

  /// Reorders a source's rows best-first, keeping the source's own order
  /// wherever the scores tie.
  ///
  /// Stability matters more than it looks: these lists repaint as other legs
  /// land, and a comparator that breaks ties arbitrarily moves cards under a
  /// finger that is already on the way down to one.
  static List<MovieEntity> rank(List<MovieEntity> items, String query) {
    if (items.length < 2 || normalize(query).isEmpty) return items;
    final scored = [
      for (var i = 0; i < items.length; i++)
        (index: i, item: items[i], score: score(items[i].title, query)),
    ];
    // Already in the right order — the common case for a source that searched
    // properly, and worth not allocating a new list for.
    if (scored.every((e) => e.score == scored.first.score)) return items;
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return [for (final e in scored) e.item];
  }

  /// The best score in a batch — how well this source answered, in one number.
  static double bestScore(List<MovieEntity> items, String query) {
    var best = 0.0;
    for (final item in items) {
      final s = score(item.title, query);
      if (s > best) best = s;
    }
    return best;
  }

  /// Whether a source plainly did not search, and returned its front page.
  ///
  /// Two conditions, and both are needed. Nothing matching is not enough on its
  /// own — that is also what an alias-only match looks like, and dropping those
  /// would remove the best results in the set. A full page of rows is not
  /// enough either; a popular query legitimately fills a page.
  ///
  /// Together they are specific: a source that searched and found one aliased
  /// title returns one row, never sixteen. This is the same guard the torrent
  /// indexers needed, for the same reason — a backend that quietly ignores a
  /// parameter answers every question with the same confident list, and nothing
  /// anywhere reports a problem.
  static bool looksUnsearched(List<MovieEntity> items, String query) {
    if (items.length < _dumpSize) return false;
    if (tokensOf(query).isEmpty) return false;
    // A page written in a script the query does not use tells us nothing.
    //
    // Scoring compares letters, so "naruto" against six katakana titles is
    // zero whether the source answered perfectly or handed over its front
    // page — and this method's whole job is to tell those two apart. Before
    // the normaliser was made Unicode-aware the katakana normalised away and
    // the zero looked decisive; it never was. Sources routinely answer a
    // romaji query with native titles and the reverse, so the honest reading
    // of "no shared script" is "cannot judge", and a page is only thrown away
    // on evidence.
    if (!_comparable(items, query)) return false;
    return bestScore(items, query) == 0;
  }

  /// Whether the query and the batch are written in a way that can be compared
  /// at all.
  static bool _comparable(List<MovieEntity> items, String query) {
    final q = scriptsOf(query);
    if (q.isEmpty) return false;
    for (final item in items) {
      if (scriptsOf(item.title).intersection(q).isNotEmpty) return true;
    }
    return false;
  }

  /// Whether a score against [query] is worth acting on at all.
  ///
  /// For the weak-results banner, which is a claim about the ANSWER — saying
  /// "nothing here matches" over correct results because the two are written in
  /// different alphabets is worse than saying nothing.
  static bool canScore(List<MovieEntity> items, String query) =>
      _comparable(items, query);
}
