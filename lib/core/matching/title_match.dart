import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How sure the app is that two titles name the same thing.
///
/// Three bands rather than a number because every surface that shows a match
/// has to make the same three decisions — open it without asking, offer it with
/// a caveat, or do not put it in front of anyone — and those decisions were
/// being made with a different magic constant in each file.
enum TitleConfidence {
  /// The same title, give or take the decoration a source bolts on.
  exact,

  /// Almost certainly the same thing: a season suffix, a missing article, a
  /// transliteration. Good enough to act on, not good enough to hide.
  strong,

  /// Plausible and unproven. Worth showing to someone who asked for
  /// alternatives, never worth choosing for them.
  weak,
}

/// One comparison of a catalogue title against a source's listing of it.
///
/// ## Why this is one class and not two private methods
///
/// [score] used to be computed twice, once inside the alternate-source sheet's
/// service and once, differently, on the path that turns a catalogue card into
/// something playable. A title that matched on the detail page and not in the
/// source switcher — or the reverse — is a bug that nobody can reproduce,
/// because the two answers came from two normalisers with two noise lists.
///
/// ## Why the score is recall over the QUERY, and never over the candidate
///
/// The formula this replaces divided the shared tokens by the *shorter* of the
/// two token sets, on the reasoning that a source listing "Naruto Shippuden
/// Uzbek tilida barcha qismlar" should still answer a search for "Naruto".
/// It does answer it — and so does every title short enough to be accidentally
/// contained. Dividing by the shorter set means the less a candidate says, the
/// easier a perfect score, which is exactly backwards: it is why a source whose
/// row was called "Return" scored 1.00 against "Return of the Blossoming
/// Blade".
///
/// The question asked here instead is: *how much of what makes the query
/// specific does this candidate carry?* A candidate that carries none of it is
/// not a match however short it is, and "Naruto" against "Naruto Shippuden …"
/// still scores highly on recall, because every distinctive word of the query
/// is present. Words the candidate adds can only shave the score
/// ([_extraWordPenalty]), never lift it, so recall stays the ceiling.
///
/// ## Why words are weighted by length
///
/// Recall alone is not enough when the query is two words long and one of them
/// is "one": "One Piece" against "One Punch Man" shares half the query and
/// would clear any floor low enough to let a real match through. Weighting each
/// word by its length ([_weightOf]) is a crude stand-in for how rare it is, and
/// a correct one often enough to matter here — "one" and "man" are short
/// because they are common, "blossoming" and "shippuden" are long because they
/// are not. It costs no corpus and no table, and it is what puts "One Punch
/// Man" at 0.29 while "Naruto Shippuden …" stays at 0.83.
///
/// ## The numbers this file exists to produce
///
/// These are the rows the source switcher really offered for **"Return of the
/// Blossoming Blade"**, with the score the old formula gave them beside the one
/// this class gives. Everything below [floor] is never shown at all; the test
/// file asserts each of these to three decimal places, so if the table and the
/// code disagree, the test is the one telling the truth.
///
/// | candidate                                       | was  | now  | band     |
/// |-------------------------------------------------|------|------|----------|
/// | Return of the Blossoming Blade                   | 1.00 | 1.00 | exact    |
/// | Return                                          | 1.00 | 0.32 | rejected |
/// | Blade of the Immortal                           | 0.75 | 0.22 | rejected |
/// | K: Return of Kings                              | 0.67 | 0.28 | rejected |
/// | Aladdin The Return of Jafar (1994) Movie Hindi … | 0.50 | 0.25 | rejected |
/// | The Lord of the Rings: The Return of the King    | 0.60 | 0.26 | rejected |
///
/// All four wrong rows carry exactly one of the query's three distinctive words
/// ("return", or "blade"), and none of them reaches [floor]. `of` and `the` are
/// worth nothing on their own — see [_stopwords] — which is what collapses "The
/// Lord of the Rings: The Return of the King" from three shared words to one.
@immutable
class TitleMatch {
  const TitleMatch({required this.score, required this.confidence});

  /// 0..1, for ordering. Two matches in the same band are ordered by this;
  /// which band they are in is [confidence], and that is what decisions are
  /// made on.
  final double score;

  final TitleConfidence confidence;

  /// Nothing comparable: an empty title, or a query with no usable words.
  static const TitleMatch none = TitleMatch(
    score: 0,
    confidence: TitleConfidence.weak,
  );

  /// Below this a candidate is not shown at all.
  ///
  /// Drawn where it is because that is what a coincidence measures: one shared
  /// word out of three lands between 0.22 and 0.32 (see the table above), and
  /// the loosest real match this app has to keep — a source that answers
  /// "Return of the Blossoming Blade" with "Blossoming Blade" — scores 0.68.
  /// There is a wide gap between the two and this sits in it.
  static const double floor = 0.40;

  /// Enough to act on without a caveat.
  static const double strongAt = 0.60;

  /// The same title, once decoration is discounted.
  ///
  /// Reaching this needs every distinctive word of the query present *and*
  /// almost nothing else in the candidate — with [_extraWordPenalty] at 0.30, a
  /// candidate that pads the query with a fifth of its own weight already falls
  /// short. "Jujutsu Kaisen 2nd Season" lands at 0.94 and is reported as
  /// [TitleConfidence.strong], because a season is not the thing that was asked
  /// for and the whole point of three bands is to say so.
  static const double exactAt = 0.95;

  /// How much of the score words present only in the CANDIDATE can take away.
  ///
  /// This is what separates [TitleConfidence.exact] from
  /// [TitleConfidence.strong], so it is not a small tie-breaker: at 0.30 a
  /// candidate has to be within about a sixth of the query's own weight to be
  /// called the same title. Sources do bolt decoration onto a title, but the
  /// decoration this app has actually met is in [_noise] and is removed before
  /// any of this runs — what is left over after that is usually a real
  /// difference, a season or a subtitle or a different cut.
  static const double _extraWordPenalty = 0.30;

  /// The most shared stopwords can be worth, in total.
  ///
  /// Small enough to be a tie-break and nothing else: it exists to order two
  /// otherwise near-identical scores, because "Blade of the Immortal" and
  /// "Blade Immortal" are not quite equally good answers to a query with "of
  /// the" in it. It is added after the score is formed, so a candidate sitting
  /// within this much of a band edge can be nudged over it — that is a
  /// twelve-thousandth of the range and below the resolution of any decision
  /// made here, but it is not the impossibility an earlier version of this
  /// sentence claimed.
  static const double _fillerCeiling = 0.012;

  /// How alike two words must look before they count as the same word.
  ///
  /// This is the only character-level comparison left, and it is deliberately
  /// per-word rather than over the whole title. A bounded similarity *bonus* on
  /// the full string was tried and is what let "K: Return of Kings" reach 0.43
  /// against "Return of the Blossoming Blade" — two unrelated titles about the
  /// same length share a great many trigrams for reasons that have nothing to
  /// do with meaning. Asking instead whether one *word* is a respelling of
  /// another buys the thing that was actually wanted — "shippuden" against
  /// "shippuuden", "kings" against "king" — and cannot manufacture agreement
  /// between words that are simply different.
  static const double _tokenSimFloor = 0.78;

  /// Below this length a word must match exactly.
  ///
  /// Three-letter words share trigrams far too readily to be compared loosely,
  /// and they are the common ones, so a false pairing there is both likelier
  /// and more damaging.
  static const int _fuzzyMinLength = 4;

  bool get isUsable => score >= floor;

  /// Whether this is good enough to choose on someone's behalf — to open, or
  /// to remember for next time.
  bool get isTrustworthy => confidence != TitleConfidence.weak;

  /// Score [candidate] as an answer to [query].
  ///
  /// Years, when either side has one, are applied here via [withYear]; pass
  /// them and do not call [withYear] again.
  factory TitleMatch.of({
    required String query,
    required String candidate,
    int? queryYear,
    int? candidateYear,
  }) {
    final q = normalise(query);
    final c = normalise(candidate);
    if (q.isEmpty || c.isEmpty) return none;

    // Spaces removed before the comparison, because where a title puts them is
    // the single most common thing two catalogues disagree about and the least
    // meaningful: "Dandadan" and "Dan Da Dan" are one show, and no amount of
    // word-level cleverness pairs a word with three words that are not it.
    var base = _compact(q) == _compact(c)
        ? const TitleMatch(score: 1, confidence: TitleConfidence.exact)
        : _scoreTokens(q, c);

    // Two titles that are identical only because a season number was taken off
    // one of them are a match, but they are not the SAME title — "Jujutsu
    // Kaisen" and "Jujutsu Kaisen 2nd Season" are two years apart. Calling that
    // exact is how a viewer who has finished a show is opened into its first
    // episode, because exact is the band the app acts on without asking.
    if (_hasSeasonNumber(query) != _hasSeasonNumber(candidate)) {
      base = base._cappedAtStrong();
    }

    // Then again against each side's head — the part before the colon or dash
    // a title hangs its subtitle off.
    //
    // Scoring only whole titles is right in one direction and badly wrong in
    // the other, and the app runs in the wrong one. A catalogue supplies the
    // long canonical name, "Bleach: Thousand-Year Blood War", and a source
    // carries the short one, "Bleach"; measured against the whole query that
    // scores 0.23 and is thrown away, although it is the correct answer and the
    // only one there is. Against the head it is a perfect match.
    //
    // This cannot resurrect the garbage it was tightened to reject, because a
    // head only exists where a separator does: "Return of the Blossoming Blade"
    // has none, so "Return" is still scored against the whole thing and still
    // rejected. And a head match is capped below [TitleConfidence.exact] — it
    // dropped a subtitle to get there, and a dropped subtitle is how a viewer
    // ends up in season one of a show they have finished.
    final qHead = normalise(_headOf(query));
    final cHead = normalise(_headOf(candidate));
    for (final (a, b) in [(qHead, c), (q, cHead), (qHead, cHead)]) {
      if (a.isEmpty || b.isEmpty) continue;
      final scored = _scoreTokens(a, b);
      if (scored.score > base.score) base = scored._cappedAtStrong();
    }

    return base.withYear(
      queryYear: queryYear ?? yearIn(query),
      candidateYear: candidateYear ?? yearIn(candidate),
    );
  }

  /// What a title says before its subtitle, or an empty string when it has no
  /// subtitle to speak of.
  ///
  /// Only the separators that actually introduce one — a colon, or a dash with
  /// spaces around it. A bare hyphen is part of "Spider-Man" and "Kaguya-sama"
  /// far more often than it is a separator.
  static String _headOf(String raw) {
    final m = _subtitleSeparator.firstMatch(raw);
    if (m == null) return '';
    final head = raw.substring(0, m.start).trim();
    return head.length < 2 ? '' : head;
  }

  static final RegExp _subtitleSeparator = RegExp(r':|\s[-–—]\s');

  /// Whether [raw] names a numbered season, which [_decoration] removes.
  static bool _hasSeasonNumber(String raw) {
    final s = raw.toLowerCase();
    return _decoration.any((shape) => shape.hasMatch(s));
  }

  /// The same match, never called [TitleConfidence.exact].
  TitleMatch _cappedAtStrong() => confidence == TitleConfidence.exact
      ? TitleMatch(
          score: math.min(score, exactAt - 0.01),
          confidence: TitleConfidence.strong,
        )
      : this;

  /// The same match with the release year taken into account.
  ///
  /// Apply once, to a match scored without years. The year is the cheapest
  /// disambiguator there is and the only one that settles "The Return of Jafar
  /// (1994)" against a 2024 title without any title cleverness at all.
  ///
  /// A year that agrees is worth very little — most titles that agree on the
  /// year are the same title anyway — so it nudges the score for ordering and
  /// deliberately leaves the band alone. A year that disagrees is worth a great
  /// deal and caps the result at [TitleConfidence.weak] rather than rejecting
  /// it outright, because an Uzbek or extension listing routinely carries the
  /// year it was UPLOADED rather than the year the show aired; that is wrong
  /// often enough that it must not delete the right answer, and right often
  /// enough that it must not be ignored.
  TitleMatch withYear({int? queryYear, int? candidateYear}) {
    if (queryYear == null || candidateYear == null) return this;
    if (queryYear == candidateYear) {
      return TitleMatch(
        score: math.min(1, score + 0.05),
        confidence: confidence,
      );
    }
    // Demoted to below every agreeing match, and no further. Halving the score
    // was not the cap this comment describes — it deleted the answer outright
    // for anything under 0.80, which took "Return of the Blossoming Blade"
    // (2024) against "Blossoming Blade" (2023) from 0.68 to 0.34 and out of the
    // list. A disagreeing year is a reason to distrust a match and to sort it
    // last; it is not a reason to pretend the match was never found.
    return TitleMatch(
      score: math.min(score, strongAt - 0.01),
      confidence: TitleConfidence.weak,
    );
  }

  /// The best of [items], or null when none of them clears [floor].
  ///
  /// Generic over the row type so this can rank a provider's search results
  /// without `core` having to know what a search result is.
  ///
  /// Ties keep the first item: the engines upstream already put their own best
  /// guess first, and re-ordering equal scores moves rows under a finger that
  /// is on the way down to one.
  static (T, TitleMatch)? best<T>(
    Iterable<T> items, {
    required String query,
    required String Function(T item) titleOf,
    int? queryYear,
    int? Function(T item)? yearOf,
  }) {
    T? bestItem;
    var bestMatch = none;
    for (final item in items) {
      final match = TitleMatch.of(
        query: query,
        candidate: titleOf(item),
        queryYear: queryYear,
        candidateYear: yearOf?.call(item),
      );
      if (match.score > bestMatch.score) {
        bestMatch = match;
        bestItem = item;
      }
    }
    if (bestItem == null || !bestMatch.isUsable) return null;
    return (bestItem, bestMatch);
  }

  static TitleConfidence confidenceOf(double score) {
    if (score >= exactAt) return TitleConfidence.exact;
    if (score >= strongAt) return TitleConfidence.strong;
    return TitleConfidence.weak;
  }

  /// The words these particular catalogues bolt onto a title.
  ///
  /// Hard-won, and the reason an Uzbek listing is comparable to an English one
  /// at all: "Naruto Shippuden (Uzbek tilida) barcha qismlar" and "Naruto
  /// Shippuden" are the same row on two sites. Removed as whole words, never as
  /// substrings — as substrings this quietly turned "Subaru" into "aru".
  ///
  /// Every word here has to be decoration ALWAYS, in every title anyone might
  /// search for, because it is stripped from both sides. That rules out several
  /// that were on this list and looked safe: "serial" is the first word of
  /// *Serial Experiments Lain*, "sub" of *Sub Zero*, "kino" of any number of
  /// German and Russian titles. Stripping them scored "Sub Zero" against "Zero"
  /// as a perfect match, which is worse than a bad score — a perfect one is
  /// acted on without asking. A word that is only sometimes decoration belongs
  /// in [_decoration], where it is removed only in the shape that makes it so.
  static const List<String> _noise = [
    'barcha qismlar',
    'uzbek tilida',
    'ozbek tilida',
    'ozbekcha',
    'tarjima',
    'qismlar',
    'full hd',
    'subbed',
    'dubbed',
  ];

  /// Decoration that is only decoration in a particular shape.
  ///
  /// "Season" is the clearest case. "Jujutsu Kaisen 2nd Season" and "Jujutsu
  /// Kaisen" are the same show and the word has to go; *Season of the Witch*
  /// and *The Witch* are two different films and it must not. The difference is
  /// entirely whether a number is attached to it, so that is what is matched.
  static final List<RegExp> _decoration = [
    RegExp(r'\b(?:season|sezon|fasl)\s*\d+\b'),
    RegExp(r'\b\d+\s*(?:st|nd|rd|th)?\s*(?:season|sezon|fasl)\b'),
  ];

  /// Words that are never evidence on their own.
  ///
  /// Three languages, because three kinds of source are being compared: the
  /// English articles and prepositions, the romaji particles that fill an anime
  /// catalogue ("Kimi no Na wa", "Shingeki no Kyojin"), and the Spanish and
  /// Portuguese articles the ES sources carry. Without this, "The Lord of the
  /// Rings: The Return of the King" shares three words with "Return of the
  /// Blossoming Blade" and looks like a two-thirds match.
  static const Set<String> _stopwords = {
    // English
    'a', 'an', 'the', 'of', 'and', 'or', 'to', 'in', 'on', 'for', 'from',
    'with', 'at', 'by',
    // Romaji particles
    'no', 'wa', 'ga', 'ni', 'de', 'wo', 'ye', 'e',
    // Spanish / Portuguese
    'el', 'la', 'los', 'las', 'del', 'y', 'o', 'os', 'as', 'um', 'uma',
  };

  /// A parenthesised release year, when the title carries one.
  ///
  /// Only when bracketed. A bare four-digit number in a title is far more often
  /// part of the name — "Blade Runner 2049", "Akira 2019" — and treating it as
  /// a release year would make the two disagree about a year neither of them
  /// stated.
  static int? yearIn(String title) {
    final m = _bracketedYear.firstMatch(title);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static final RegExp _bracketedYear = RegExp(
    r'[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]',
  );

  /// Everything that is not a letter, a digit or a space.
  ///
  /// Unicode-aware rather than an alphabet whitelist: the previous version kept
  /// Latin and Cyrillic and deleted everything else, so a Japanese or Korean
  /// title normalised to the empty string and could never match even itself.
  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N} ]+', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _marks = RegExp(r"['’`´]+");

  /// Lowercase, de-decorated, punctuation gone.
  static String normalise(String raw) {
    var s = raw.toLowerCase().replaceAll(_bracketedYear, ' ');
    // Before punctuation goes, so "o'zbekcha" and "ozbekcha" are one word.
    s = s.replaceAll(_marks, '');
    s = s.replaceAll(_punctuation, ' ').replaceAll(_spaces, ' ').trim();
    if (s.isEmpty) return s;

    for (final shape in _decoration) {
      s = s.replaceAll(shape, ' ');
    }
    s = s.replaceAll(_spaces, ' ').trim();
    if (s.isEmpty) return s;

    var padded = ' $s ';
    for (final phrase in _noise) {
      while (padded.contains(' $phrase ')) {
        padded = padded.replaceAll(' $phrase ', ' ');
      }
    }
    final cleaned = padded.replaceAll(_spaces, ' ').trim();
    // A title that is ENTIRELY decoration — a source whose row is called
    // "Serial" or "Kino" — keeps its words rather than becoming unmatchable.
    return cleaned.isEmpty ? s : cleaned;
  }

  /// The words that make a title specific: no stopwords, nothing shorter than
  /// two characters unless it is a number, which is usually a season or a part
  /// and is exactly the difference between two listings.
  static Set<String> keyTokensOf(String raw) => _keys(normalise(raw));

  static String _compact(String normalised) => normalised.replaceAll(' ', '');

  static Set<String> _keys(String normalised) => {
    for (final t in normalised.split(' '))
      if (_isKey(t)) t,
  };

  /// The words a title is made of that are NOT evidence — stopwords and stray
  /// single letters. Kept because they still order two equal scores.
  static Set<String> _fillers(String normalised) => {
    for (final t in normalised.split(' '))
      if (t.isNotEmpty && !_isKey(t)) t,
  };

  static bool _isKey(String t) {
    if (t.isEmpty || _stopwords.contains(t)) return false;
    // A lone digit is kept: "Naruto 2" and "Naruto 3" differ by exactly that.
    return t.length > 1 || _isDigit(t.codeUnitAt(0));
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isNumber(String t) {
    for (var i = 0; i < t.length; i++) {
      if (!_isDigit(t.codeUnitAt(i))) return false;
    }
    return t.isNotEmpty;
  }

  /// How much a word counts as evidence, by length, capped at eight.
  ///
  /// A bare number is weighed as a medium-length word rather than by its one
  /// character: "2" in "Solo Leveling Season 2" is short but it is the most
  /// distinguishing thing in the title, and at a single character's weight two
  /// different seasons scored as the same show.
  static double _weightOf(String token) {
    if (_isNumber(token)) return 0.5;
    final n = token.length > 8 ? 8 : token.length;
    return n / 8;
  }

  static double _weight(Iterable<String> tokens) {
    var total = 0.0;
    for (final t in tokens) {
      total += _weightOf(t);
    }
    return total;
  }

  static TitleMatch _scoreTokens(String q, String c) {
    var queryKeys = _keys(q);
    var candidateKeys = _keys(c);
    if (queryKeys.isEmpty) {
      // Everything the query says is a stopword — "The Who", "La De" — so the
      // stopwords are all the evidence there is. Returning an empty set here
      // and scoring zero is how a title made of small words became unfindable.
      queryKeys = q.split(' ').where((t) => t.isNotEmpty).toSet();
      candidateKeys = c.split(' ').where((t) => t.isNotEmpty).toSet();
    }
    if (queryKeys.isEmpty || candidateKeys.isEmpty) return none;

    final queryWeight = _weight(queryKeys);
    final candidateWeight = _weight(candidateKeys);
    if (queryWeight <= 0 || candidateWeight <= 0) return none;

    // Measured from both ends: how much of the query the candidate carries
    // (recall) and how much of the candidate the query accounts for
    // (precision). A word may be paired with a respelling of itself, which is
    // why this is not a set intersection — see [_tokenSimFloor].
    final matchedInQuery = _matchedWeight(queryKeys, candidateKeys);
    final matchedInCandidate = _matchedWeight(candidateKeys, queryKeys);
    if (matchedInQuery <= 0) return none;

    final recall = matchedInQuery / queryWeight;
    final precision = matchedInCandidate / candidateWeight;
    // Multiplied, not added: recall is the ceiling, so a candidate can never
    // score above the share of the query it actually carries. An additive
    // precision term is how "Return" got to 0.43 — perfect precision on one
    // borrowed word.
    var score = recall * (1 - _extraWordPenalty * (1 - precision));
    final fillers = _fillers(q).intersection(_fillers(c)).length;
    score += math.min(fillers * 0.004, _fillerCeiling);

    score = score.clamp(0.0, 1.0);
    return TitleMatch(score: score, confidence: confidenceOf(score));
  }

  /// Total weight of [from] that is answered by something in [to].
  static double _matchedWeight(Set<String> from, Set<String> to) {
    var total = 0.0;
    for (final t in from) {
      if (to.contains(t)) {
        total += _weightOf(t);
        continue;
      }
      final sim = _closest(t, to);
      if (sim > 0) total += _weightOf(t) * sim;
    }
    return total;
  }

  /// How closely [token] resembles the nearest word in [others], or 0 when
  /// nothing there is close enough to be the same word.
  static double _closest(String token, Set<String> others) {
    if (token.length < _fuzzyMinLength) return 0;
    var best = 0.0;
    for (final other in others) {
      if (other.length < _fuzzyMinLength) continue;
      final d = _trigramDice(token, other);
      if (d > best) best = d;
    }
    return best >= _tokenSimFloor ? best : 0;
  }

  /// Dice coefficient over character trigrams. Twenty lines and no dependency;
  /// edit distance costs O(n·m) for an answer this does not need.
  static double _trigramDice(String a, String b) {
    if (a == b) return 1;
    final ta = _trigrams(a);
    final tb = _trigrams(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    var shared = 0;
    for (final g in ta) {
      if (tb.contains(g)) shared++;
    }
    return 2 * shared / (ta.length + tb.length);
  }

  static Set<String> _trigrams(String s) {
    if (s.length < 3) return s.isEmpty ? const {} : {s};
    return {for (var i = 0; i + 3 <= s.length; i++) s.substring(i, i + 3)};
  }
}
