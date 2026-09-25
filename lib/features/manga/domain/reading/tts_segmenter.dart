import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

/// One stretch of a chapter spoken in a single engine call: a sentence, or a
/// piece of one that was too long to hand over whole.
///
/// [start] and [end] index into the block's [NovelBlock.text], so the reader
/// can paint exactly what is being said. A [block] of -1 is spoken but not on
/// the page, like an announced chapter title.
class TtsUtterance {
  const TtsUtterance({
    required this.block,
    required this.start,
    required this.end,
    required this.text,
  });

  final int block;
  final int start;
  final int end;
  final String text;

  @override
  String toString() => 'TtsUtterance($block, $start..$end, "$text")';
}

/// A chapter cut into utterances, with a character count behind each one so a
/// spoken position can be turned into the reader's thousandths and back.
class TtsScript {
  TtsScript._(this.utterances, this._before, this._total);

  factory TtsScript.fromBlocks(
    List<NovelBlock> blocks, {
    String? preface,
    int maxLength = kTtsMaxUtterance,
  }) {
    final list = <TtsUtterance>[
      if (preface != null && preface.trim().isNotEmpty)
        TtsUtterance(block: -1, start: 0, end: 0, text: preface.trim()),
      ...segmentForSpeech(blocks, maxLength: maxLength),
    ];
    final before = <int>[];
    var total = 0;
    for (final u in list) {
      before.add(total);
      if (u.block >= 0) total += u.text.length;
    }
    return TtsScript._(list, before, total);
  }

  final List<TtsUtterance> utterances;
  final List<int> _before;
  final int _total;

  int get length => utterances.length;
  bool get isEmpty => utterances.isEmpty;
  TtsUtterance operator [](int i) => utterances[i];

  /// How far into the chapter utterance [index] ends, in thousandths.
  int permilleAfter(int index) {
    if (_total == 0 || utterances.isEmpty) return 0;
    final i = index.clamp(0, utterances.length - 1);
    final u = utterances[i];
    final spoken = _before[i] + (u.block >= 0 ? u.text.length : 0);
    return (spoken * 1000 / _total).round().clamp(0, 1000);
  }

  /// The utterance that sits at [permille] of the chapter's text.
  int indexAtPermille(int permille) {
    if (utterances.isEmpty || _total == 0) return 0;
    final target = _total * permille.clamp(0, 1000) / 1000;
    for (var i = 0; i < utterances.length; i++) {
      final u = utterances[i];
      if (u.block < 0) continue;
      if (_before[i] + u.text.length > target) return i;
    }
    return utterances.length - 1;
  }
}

/// Past this an Android engine starts refusing text outright (its hard limit
/// is 4000), and well before it the highlight stops meaning anything.
const int kTtsMaxUtterance = 360;

/// Cuts a chapter's blocks into sentences for the speech engine.
///
/// Rules are skipped, headings are spoken whole, and anything without a letter
/// or digit in it — a row of asterisks, a lone ellipsis — is left out, because
/// an engine reads those aloud symbol by symbol.
List<TtsUtterance> segmentForSpeech(
  List<NovelBlock> blocks, {
  int maxLength = kTtsMaxUtterance,
}) {
  final out = <TtsUtterance>[];
  for (var b = 0; b < blocks.length; b++) {
    final block = blocks[b];
    if (block.kind == NovelBlockKind.rule) continue;
    final ranges = block.kind == NovelBlockKind.heading
        ? [(0, block.text.length)]
        : sentenceRanges(block.text);
    for (final (s, e) in ranges) {
      for (final (cs, ce) in _capped(block.text, s, e, maxLength)) {
        final (ts, te) = _trimmed(block.text, cs, ce);
        if (te <= ts) continue;
        final text = block.text.substring(ts, te);
        if (!_speakable.hasMatch(text)) continue;
        out.add(TtsUtterance(block: b, start: ts, end: te, text: text));
      }
    }
  }
  return out;
}

final RegExp _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);

const String _terminators = '.!?…。！？؟';
const String _fullWidth = '。！？';
const String _closers = '"\'”’»)]}」』〕】';

/// Words that end in a full stop without ending the sentence. Lower-cased,
/// without the stop.
const Set<String> _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr', 'prof', 'vs', 'etc', 'e.g',
  'i.e', 'mt', 'lt', 'col', 'gen', 'capt', 'sgt',
  'approx', 'dept', 'est', 'inc', 'ltd', 'co', 'sen', 'rep', 'gov', 'rev',
  // Russian: "т. е.", "и т. д.", "г." after a year, "им." before a name.
  'т', 'е', 'д', 'г', 'гг', 'им', 'др', 'ул', 'стр', 'см', 'тыс', 'млн',
};

/// Abbreviations only when a number follows: "No. 5", but "he said no."
const Set<String> _numberAbbreviations = {'no', 'vol', 'ch', 'fig', 'pp'};

/// Sentence boundaries in [text], as start/end pairs covering all of it.
///
/// A terminator ends a sentence when what follows is space, the end of the
/// text or, for the full-width CJK marks, anything at all. Closing quotes and
/// brackets stay with the sentence they close. Not a boundary: a stop after a
/// known abbreviation or a single capital (an initial), and any terminator
/// followed by a lower-case word — `"What?" he asked.` is one sentence.
List<(int, int)> sentenceRanges(String text) {
  final out = <(int, int)>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (!_terminators.contains(c)) {
      i++;
      continue;
    }
    final stop = i;
    var j = i + 1;
    while (j < text.length && _terminators.contains(text[j])) {
      j++;
    }
    while (j < text.length && _closers.contains(text[j])) {
      j++;
    }
    final atEnd = j >= text.length;
    final spaced = !atEnd && _isSpace(text[j]);
    final boundary =
        atEnd ||
        (_fullWidth.contains(c)) ||
        (spaced &&
            !(c == '.' && j == stop + 1 && _abbreviationBefore(text, stop)) &&
            !_lowerNext(text, j));
    if (boundary) {
      out.add((start, j));
      start = j;
    }
    i = j;
  }
  if (start < text.length) out.add((start, text.length));
  return out;
}

bool _isSpace(String c) =>
    c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u00A0';

bool _abbreviationBefore(String text, int stop) {
  var k = stop;
  while (k > 0 && !_isSpace(text[k - 1]) && !_closers.contains(text[k - 1])) {
    k--;
  }
  final word = text.substring(k, stop);
  if (word.isEmpty) return false;
  if (word.length == 1 && word != 'I') {
    // A single capital is an initial ("J. K. Rowling"); a digit is not.
    if (word.toUpperCase() == word && word.toLowerCase() != word) return true;
  }
  final lower = word.toLowerCase();
  if (_numberAbbreviations.contains(lower)) {
    var k = stop + 1;
    while (k < text.length && _isSpace(text[k])) {
      k++;
    }
    return k < text.length && '0123456789'.contains(text[k]);
  }
  return _abbreviations.contains(lower);
}

bool _lowerNext(String text, int from) {
  var k = from;
  while (k < text.length && _isSpace(text[k])) {
    k++;
  }
  if (k >= text.length) return false;
  final c = text[k];
  return c.toLowerCase() == c && c.toUpperCase() != c;
}

/// [start]..[end] of [text] in pieces no longer than [max], broken at the
/// last comma-like mark in the back half of a window, then the last space,
/// then wherever the window ends.
List<(int, int)> _capped(String text, int start, int end, int max) {
  final out = <(int, int)>[];
  var s = start;
  while (end - s > max) {
    final window = text.substring(s, s + max);
    var cut = -1;
    for (var k = window.length - 1; k >= max ~/ 2; k--) {
      if (',;:—–、，；：'.contains(window[k])) {
        cut = k + 1;
        break;
      }
    }
    if (cut < 0) {
      final space = window.lastIndexOf(' ');
      cut = space > max ~/ 4 ? space + 1 : max;
    }
    out.add((s, s + cut));
    s += cut;
  }
  out.add((s, end));
  return out;
}

(int, int) _trimmed(String text, int s, int e) {
  while (s < e && _isSpace(text[s])) {
    s++;
  }
  while (e > s && _isSpace(text[e - 1])) {
    e--;
  }
  return (s, e);
}
