/// One jumpable run of episodes, matching a page the server already serves.
///
/// [from] and [to] are episode NUMBERS, in the order they are displayed — so a
/// descending list reads "1176–1127", counting down, exactly as the rows below
/// it do. A block whose numbers ran the other way to its contents would be a
/// label that argues with the list.
class EpisodeBlock {
  const EpisodeBlock({
    required this.page,
    required this.from,
    required this.to,
  });

  /// The server page this block loads. The blocks ARE the pages: a jump is one
  /// request, not every request between here and there.
  final int page;

  final int from;
  final int to;

  String get label => from == to ? '$from' : '$from–$to';

  @override
  bool operator ==(Object other) =>
      other is EpisodeBlock &&
      other.page == page &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(page, from, to);

  @override
  String toString() => 'EpisodeBlock($page: $label)';
}

/// Splits a run of episodes into the blocks a reader can jump between.
///
/// ## Why this exists
///
/// A thousand-episode series is twenty-plus scroll-loads away from its own
/// ending, and until now the only way to reach a late episode was to sit there
/// pulling pages in. One tap should be enough.
///
/// ## Why the numbers are derived rather than assumed
///
/// [firstNumber] is the number of the first episode of the whole run, taken
/// from real data rather than assumed to be 1. Plenty of sources number from 0,
/// and some carry a season's absolute numbering — labelling those "1–50" would
/// put a number on the chip that appears nowhere in the list underneath it.
///
/// Returns an empty list when there is nothing to jump over: a single page is
/// already entirely on screen, and a strip of one chip is decoration.
List<EpisodeBlock> episodeBlocks({
  required int total,
  required int size,
  required bool descending,
  required int firstNumber,
}) {
  if (total < 1 || size < 1 || total <= size) return const [];

  final pages = (total + size - 1) ~/ size;
  final last = firstNumber + total - 1;

  return [
    for (var page = 1; page <= pages; page++)
      if (descending)
        // Descending pages count down from the end of the run, and the label
        // counts down with them.
        EpisodeBlock(
          page: page,
          from: last - (page - 1) * size,
          to: last - ((page * size - 1).clamp(0, total - 1)),
        )
      else
        EpisodeBlock(
          page: page,
          from: firstNumber + (page - 1) * size,
          to: firstNumber + (page * size - 1).clamp(0, total - 1),
        ),
  ];
}

/// The block holding [episodeNumber], or null when the run does not reach it.
///
/// Asking "which page is 437 on" is the question behind every long list: the
/// filter can only search what is loaded, so a number typed on a fresh window
/// of a 1176-episode run matched nothing and the reader was left to scroll
/// twelve pages to find out where it lived. The arithmetic that draws the chips
/// already knows the answer.
///
/// Position is counted from [firstNumber] rather than assumed, for the same
/// reason [episodeBlocks] derives its labels: sources that number from 0, and
/// seasons carrying absolute numbering, are common enough that assuming 1 puts
/// the reader on the wrong page.
///
/// Null when there is nothing to jump to — a run that fits on one page, or a
/// number outside the run entirely.
EpisodeBlock? blockContaining(
  int episodeNumber, {
  required int total,
  required int size,
  required bool descending,
  required int firstNumber,
}) {
  final offset = episodeNumber - firstNumber;
  if (total < 1 || size < 1 || offset < 0 || offset >= total) return null;

  // Descending pages start from the end of the run, so a number's distance
  // from the start becomes its distance from the last page.
  final position = descending ? total - 1 - offset : offset;
  final page = position ~/ size + 1;

  // Built directly rather than by scanning `episodeBlocks(...)` for a page it
  // already computed above. This runs from the scroll listener on every
  // notification, and building the whole list to find one entry allocated a
  // dozen EpisodeBlocks and a List per scroll frame — on an Android TV box
  // that is real frame budget spent on arithmetic already done.
  //
  // The two branches mirror `episodeBlocks` exactly; if the labelling there
  // ever changes, it changes here.
  final last = firstNumber + total - 1;
  return descending
      ? EpisodeBlock(
          page: page,
          from: last - (page - 1) * size,
          to: last - ((page * size - 1).clamp(0, total - 1)),
        )
      : EpisodeBlock(
          page: page,
          from: firstNumber + (page - 1) * size,
          to: firstNumber + (page * size - 1).clamp(0, total - 1),
        );
}
