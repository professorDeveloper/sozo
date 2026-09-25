/// A highlighted passage of a novel chapter.
///
/// Anchored by block index and character offsets into that block's plain
/// text — the same coordinates read-aloud uses — so it survives any change of
/// font, size or layout. [text] is kept for the list and as a check that the
/// chapter still says the same thing.
library;

enum HighlightColor {
  yellow(0xFFFFD54F),
  green(0xFF81C784),
  blue(0xFF64B5F6),
  pink(0xFFF48FB1);

  const HighlightColor(this.argb);
  final int argb;

  static HighlightColor byName(Object? name) => HighlightColor.values
      .firstWhere((c) => c.name == name, orElse: () => HighlightColor.yellow);
}

class NovelHighlight {
  const NovelHighlight({
    required this.id,
    required this.chapterRef,
    required this.chapter,
    required this.chapterLabel,
    required this.block,
    required this.start,
    required this.end,
    required this.text,
    this.color = HighlightColor.yellow,
    this.note = '',
    required this.createdAt,
  });

  final String id;

  /// The chapter's ref, with its number as the fallback identity for when a
  /// source re-keys its refs.
  final String chapterRef;
  final int chapter;
  final String chapterLabel;

  final int block;
  final int start;
  final int end;
  final String text;
  final HighlightColor color;
  final String note;
  final int createdAt;

  bool belongsTo(String ref, int number) =>
      chapterRef == ref || (number > 0 && chapter == number);

  bool overlaps(int block, int start, int end) =>
      this.block == block && this.start < end && start < this.end;

  NovelHighlight copyWith({HighlightColor? color, String? note}) =>
      NovelHighlight(
        id: id,
        chapterRef: chapterRef,
        chapter: chapter,
        chapterLabel: chapterLabel,
        block: block,
        start: start,
        end: end,
        text: text,
        color: color ?? this.color,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ref': chapterRef,
    'ch': chapter,
    'label': chapterLabel,
    'b': block,
    's': start,
    'e': end,
    'text': text,
    'color': color.name,
    if (note.isNotEmpty) 'note': note,
    'at': createdAt,
  };

  /// Null for a record that cannot be drawn, rather than a throw.
  static NovelHighlight? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final block = raw['b'];
    final start = raw['s'];
    final end = raw['e'];
    if (block is! int || start is! int || end is! int || end <= start) {
      return null;
    }
    return NovelHighlight(
      id: '${raw['id'] ?? ''}',
      chapterRef: '${raw['ref'] ?? ''}',
      chapter: raw['ch'] is int ? raw['ch'] as int : 0,
      chapterLabel: '${raw['label'] ?? ''}',
      block: block,
      start: start,
      end: end,
      text: '${raw['text'] ?? ''}',
      color: HighlightColor.byName(raw['color']),
      note: '${raw['note'] ?? ''}',
      createdAt: raw['at'] is int ? raw['at'] as int : 0,
    );
  }
}
