import 'package:soplay/features/detail/domain/entities/episode_entity.dart';

/// One heading in the chapter list, and the chapters under it.
class ChapterGroup {
  const ChapterGroup({
    required this.label,
    required this.volume,
    required this.indices,
  });

  /// What the heading says. Empty for the single group a short list gets,
  /// which is drawn without a heading at all.
  final String label;

  /// The volume number this group is, or null when the grouping is by range.
  final int? volume;

  /// Positions in the ORIGINAL chapter list, so tapping a row still loads the
  /// right chapter. Grouping must never renumber anything: the index is the
  /// identity everything else in the reader is keyed on.
  final List<int> indices;
}

/// Splits a chapter list into headings somebody can navigate.
///
/// A source with six hundred chapters gives a flat list six hundred rows long,
/// and the only way to reach chapter 300 is to drag a scrollbar until the
/// numbers look right. Grouping gives it a spine.
///
/// Two ways, in order of preference:
///
///  * **By volume**, when the labels say so. Most scanlation sources write
///    "Vol. 4 Ch. 31" or "Volume 4, Chapter 31", and a volume is a real
///    division somebody remembers reading — worth far more than an arbitrary
///    block. Used only when MOST chapters carry one, because a handful of
///    volume-labelled specials in an otherwise unlabelled list would put
///    nearly everything in "Other".
///  * **By range**, otherwise: blocks of [rangeSize], labelled by the chapter
///    numbers at each end rather than by position, so the heading reads like
///    the numbers on the rows under it.
///
/// A list shorter than [minToGroup] is left alone. Headings over a list that
/// fits on two screens are noise.
List<ChapterGroup> groupChapters(
  List<EpisodeEntity> chapters, {
  int minToGroup = 40,
  int rangeSize = 50,
}) {
  if (chapters.length < minToGroup) {
    return [
      ChapterGroup(
        label: '',
        volume: null,
        indices: [for (var i = 0; i < chapters.length; i++) i],
      ),
    ];
  }

  final volumes = [for (final c in chapters) volumeOf(c.label)];
  final named = volumes.where((v) => v != null).length;
  // Two thirds, not "any": a list where a quarter of the chapters name a
  // volume is a list that is not organised by volume.
  if (named * 3 >= chapters.length * 2) {
    final byVolume = <int?, List<int>>{};
    for (var i = 0; i < chapters.length; i++) {
      byVolume.putIfAbsent(volumes[i], () => []).add(i);
    }
    final keys = byVolume.keys.toList()
      // Unnumbered chapters last, under their own heading, rather than
      // silently sorted in among numbers they do not have.
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });
    return [
      for (final v in keys)
        ChapterGroup(
          label: v == null ? '' : '$v',
          volume: v,
          indices: byVolume[v]!,
        ),
    ];
  }

  final groups = <ChapterGroup>[];
  for (var start = 0; start < chapters.length; start += rangeSize) {
    final end = (start + rangeSize).clamp(0, chapters.length);
    final indices = [for (var i = start; i < end; i++) i];
    groups.add(
      ChapterGroup(
        label: '${_number(chapters[start])} – ${_number(chapters[end - 1])}',
        volume: null,
        indices: indices,
      ),
    );
  }
  return groups;
}

/// The volume a chapter says it belongs to, or null.
///
/// Deliberately narrow. It matches a word meaning "volume" followed by a
/// number, in the three spellings sources actually use — and nothing else,
/// because a looser pattern reads the "2" out of "Season 2" or out of a title
/// and invents volumes nobody wrote.
int? volumeOf(String label) {
  final m = _volume.firstMatch(label);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? '');
}

final RegExp _volume = RegExp(
  r'\b(?:vol|volume|tome|том)\.?\s*(\d{1,3})\b',
  caseSensitive: false,
);

/// The chapter number as written, for a range heading.
///
/// The stored number where there is one, and the first number in the label
/// otherwise — a source that numbers nothing still labels "Chapter 12".
String _number(EpisodeEntity c) {
  if (c.episode > 0) return '${c.episode}';
  final m = RegExp(r'\d+').firstMatch(c.label);
  return m?.group(0) ?? c.label;
}
