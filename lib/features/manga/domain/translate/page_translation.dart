import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// One piece of text found on a page, in the image's own pixels.
class OcrBlock {
  const OcrBlock({
    required this.rect,
    required this.text,
    required this.lineHeight,
  });

  final Rect rect;
  final String text;

  /// Average height of one recognised line, which is what "close together"
  /// is measured in: lettering size varies by page far more than by bubble.
  final double lineHeight;
}

/// A bubble's worth of text and what it says in the target language.
class TranslatedBlock {
  const TranslatedBlock({
    required this.rect,
    required this.source,
    required this.text,
  });

  final Rect rect;
  final String source;
  final String text;

  Map<String, dynamic> toJson() => {
    'l': rect.left,
    't': rect.top,
    'r': rect.right,
    'b': rect.bottom,
    's': source,
    'x': text,
  };

  static TranslatedBlock fromJson(Map<String, dynamic> m) => TranslatedBlock(
    rect: Rect.fromLTRB(
      (m['l'] as num).toDouble(),
      (m['t'] as num).toDouble(),
      (m['r'] as num).toDouble(),
      (m['b'] as num).toDouble(),
    ),
    source: '${m['s'] ?? ''}',
    text: '${m['x'] ?? ''}',
  );
}

/// A translated page: the boxes to cover, in the coordinates of an image of
/// [imageSize].
class PageTranslation {
  const PageTranslation({
    required this.imageSize,
    required this.targetLang,
    required this.blocks,
  });

  final Size imageSize;
  final String targetLang;
  final List<TranslatedBlock> blocks;

  Map<String, dynamic> toJson() => {
    'w': imageSize.width,
    'h': imageSize.height,
    'lang': targetLang,
    'blocks': [for (final b in blocks) b.toJson()],
  };

  static PageTranslation? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      return PageTranslation(
        imageSize: Size(
          (raw['w'] as num).toDouble(),
          (raw['h'] as num).toDouble(),
        ),
        targetLang: '${raw['lang']}',
        blocks: [
          for (final b in raw['blocks'] as List)
            TranslatedBlock.fromJson(b as Map<String, dynamic>),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// The server keeps 200 characters of a docKey. A long chapter url cut there
/// would lose the page number and make every page of the chapter one document.
const int kDocKeyLimit = 200;

/// The quota key for one page: the backend charges once per key per day.
String pageTranslateDocKey(String chapterUrl, int pageIndex) {
  final plain = 'manga:$chapterUrl:$pageIndex';
  if (plain.length <= kDocKeyLimit) return plain;
  final digest = sha1.convert(utf8.encode(chapterUrl)).toString();
  return 'manga:$digest:$pageIndex';
}

/// Languages written right to left, among those a page can be translated into.
const Set<String> kRtlLanguages = {'ar', 'fa', 'he', 'ur', 'ckb', 'ps', 'yi'};

bool isRtlLanguage(String lang) =>
    kRtlLanguages.contains(lang.toLowerCase().split(RegExp('[-_]')).first);

/// Joins blocks whose boxes come within [gapFactor] line heights of each
/// other, so a bubble the recogniser split in two is translated as one
/// sentence. Blocks with no letters (page numbers, stray marks) are dropped.
///
/// Reading order is top to bottom, then left to right, both for the blocks
/// returned and for the lines inside a merged one.
List<OcrBlock> mergeBlocks(List<OcrBlock> blocks, {double gapFactor = 0.8}) {
  final kept = [
    for (final b in blocks)
      if (_hasLetters(b.text) && !b.rect.isEmpty) b,
  ];
  final n = kept.length;
  final parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (_close(kept[i], kept[j], gapFactor)) {
        parent[find(i)] = find(j);
      }
    }
  }

  final groups = <int, List<OcrBlock>>{};
  for (var i = 0; i < n; i++) {
    groups.putIfAbsent(find(i), () => []).add(kept[i]);
  }

  final merged = [
    for (final group in groups.values)
      if (group.length == 1) group.single else _union(group),
  ];
  merged.sort(_readingOrder);
  return merged;
}

bool _close(OcrBlock a, OcrBlock b, double gapFactor) {
  final gap = gapFactor * math.min(a.lineHeight, b.lineHeight);
  final dx = math.max(
    0.0,
    math.max(a.rect.left, b.rect.left) - math.min(a.rect.right, b.rect.right),
  );
  final dy = math.max(
    0.0,
    math.max(a.rect.top, b.rect.top) - math.min(a.rect.bottom, b.rect.bottom),
  );
  if (dx > gap || dy > gap) return false;
  // Stacked lines of one bubble share a column. Two bubbles side by side
  // touch at the edges but barely overlap horizontally.
  if (dy > 0) {
    final overlap =
        math.min(a.rect.right, b.rect.right) -
        math.max(a.rect.left, b.rect.left);
    return overlap >= 0.3 * math.min(a.rect.width, b.rect.width);
  }
  return true;
}

OcrBlock _union(List<OcrBlock> group) {
  group.sort(_readingOrder);
  var rect = group.first.rect;
  var lines = 0.0;
  for (final b in group) {
    rect = rect.expandToInclude(b.rect);
    lines += b.lineHeight;
  }
  return OcrBlock(
    rect: rect,
    text: group.map((b) => b.text).join('\n'),
    lineHeight: lines / group.length,
  );
}

int _readingOrder(OcrBlock a, OcrBlock b) {
  // Within half a line counts as the same row, so a slightly lower block to
  // the left still reads first.
  final tolerance = 0.5 * math.min(a.lineHeight, b.lineHeight);
  if ((a.rect.top - b.rect.top).abs() > tolerance) {
    return a.rect.top.compareTo(b.rect.top);
  }
  return a.rect.left.compareTo(b.rect.left);
}

bool _hasLetters(String text) => RegExp(r'\p{L}', unicode: true).hasMatch(text);

/// Prepares recognised text for the translator: line breaks become spaces,
/// a word split by a hyphen at a line end is joined again, and ALL-CAPS
/// lettering becomes sentence case, which translators handle far better.
String normalizeOcrText(String text) {
  var out = text.replaceAllMapped(
    RegExp(r'(\p{L})-\s*\n\s*(\p{L})', unicode: true),
    (m) => '${m[1]}${m[2]}',
  );
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  final letters = out.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  if (letters.length > 1 && letters == letters.toUpperCase()) {
    out = _sentenceCase(out.toLowerCase());
  }
  return out;
}

String _sentenceCase(String lower) {
  final buffer = StringBuffer();
  var capitalize = true;
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    if (capitalize && RegExp(r'\p{L}', unicode: true).hasMatch(ch)) {
      buffer.write(ch.toUpperCase());
      capitalize = false;
    } else {
      buffer.write(ch);
    }
    if ('.!?'.contains(ch)) capitalize = true;
  }
  // The pronoun survives lower-casing as "i".
  return buffer.toString().replaceAllMapped(
    RegExp(r"\bi\b(?!\.)"),
    (_) => 'I',
  );
}

/// The largest font size between [min] and [max] at which [measure] says the
/// text fits [box], to within [precision]. [measure] lays the text out at a
/// font size, wrapped to the box width, and returns the size it took.
///
/// Returns [min] when nothing fits; the caller lets that overflow rather than
/// draw text nobody can read.
double fitFontSize({
  required Size box,
  required Size Function(double fontSize) measure,
  double min = 6,
  double max = 32,
  double precision = 0.5,
}) {
  bool fits(double size) {
    final used = measure(size);
    return used.width <= box.width + 0.01 && used.height <= box.height + 0.01;
  }

  if (box.isEmpty) return min;
  if (fits(max)) return max;
  if (!fits(min)) return min;
  var lo = min;
  var hi = max;
  while (hi - lo > precision) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// What a page shows, kept per chapter and page while the reader is open.
class PageOverlayEntry {
  const PageOverlayEntry({
    required this.translation,
    this.applied = false,
    this.showOriginal = false,
  });

  final PageTranslation translation;
  final bool applied;
  final bool showOriginal;

  PageOverlayEntry copyWith({bool? applied, bool? showOriginal}) =>
      PageOverlayEntry(
        translation: translation,
        applied: applied ?? this.applied,
        showOriginal: showOriginal ?? this.showOriginal,
      );
}

/// Overlay state for every translated page of the open reader.
///
/// A translation is stored before it is shown: the preview offers it, and
/// only Apply puts it over the page. Cancel leaves whatever was there.
class PageOverlays extends ChangeNotifier {
  final Map<String, PageOverlayEntry> _entries = {};

  static String keyFor(String chapterUrl, int pageIndex) =>
      '$chapterUrl#$pageIndex';

  PageOverlayEntry? entry(String key) => _entries[key];

  /// The stored translation for [key], if it was made into [lang].
  PageTranslation? translationFor(String key, String lang) {
    final t = _entries[key]?.translation;
    return t != null && t.targetLang == lang ? t : null;
  }

  /// What to draw over the page, or null for the original.
  PageTranslation? visible(String key) {
    final e = _entries[key];
    if (e == null || !e.applied || e.showOriginal) return null;
    return e.translation;
  }

  bool isApplied(String key) => _entries[key]?.applied ?? false;

  /// Keeps [translation] without showing it, unless it replaces one that was
  /// already applied in the same language.
  void store(String key, PageTranslation translation) {
    final old = _entries[key];
    final keepApplied =
        old != null &&
        old.applied &&
        old.translation.targetLang == translation.targetLang;
    _entries[key] = PageOverlayEntry(
      translation: translation,
      applied: keepApplied,
      showOriginal: keepApplied && old.showOriginal,
    );
    notifyListeners();
  }

  /// Puts the stored translation over the page; [showOriginal] keeps it
  /// hidden but one toggle away.
  void apply(String key, {bool showOriginal = false}) {
    final e = _entries[key];
    if (e == null) return;
    _entries[key] = e.copyWith(applied: true, showOriginal: showOriginal);
    notifyListeners();
  }

  void toggleOriginal(String key) {
    final e = _entries[key];
    if (e == null || !e.applied) return;
    _entries[key] = e.copyWith(showOriginal: !e.showOriginal);
    notifyListeners();
  }

  /// Takes the overlay off the page and keeps the translation for later.
  void remove(String key) {
    final e = _entries[key];
    if (e == null || !e.applied) return;
    _entries[key] = e.copyWith(applied: false, showOriginal: false);
    notifyListeners();
  }
}

/// Why a page could not be translated, for the message the reader shows.
enum PageTranslateFailure { noText, dailyLimit, offline, signIn, failed }

class PageTranslateException implements Exception {
  const PageTranslateException(this.reason, [this.message]);
  final PageTranslateFailure reason;
  final String? message;
  @override
  String toString() => message ?? reason.name;
}
