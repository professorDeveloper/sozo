/// The quick-bar emoji. The backend accepts exactly these
/// (src/services/timedReactionService.js).
const List<String> kTimedReactionEmoji = [
  '🔥',
  '😂',
  '😮',
  '😢',
  '😍',
  '👏',
  '💀',
  '😡',
];

const int kTimedReactionMaxText = 60;

class ReactionItem {
  const ReactionItem({
    required this.kind,
    required this.value,
    required this.count,
  });

  /// 'emoji' or 'text'.
  final String kind;
  final String value;
  final int count;

  bool get isEmoji => kind == 'emoji';

  factory ReactionItem.fromJson(Map<String, dynamic> json) => ReactionItem(
    kind: json['kind'] as String? ?? 'emoji',
    value: json['value'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 1,
  );
}

/// Everything reacted at one second of the episode.
class ReactionBucket {
  const ReactionBucket({
    required this.t,
    required this.total,
    required this.items,
  });

  final int t;

  /// All reactions at [t], including the ones [items] leaves out.
  final int total;
  final List<ReactionItem> items;

  factory ReactionBucket.fromJson(Map<String, dynamic> json) => ReactionBucket(
    t: (json['t'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    items: [
      for (final i in (json['items'] as List? ?? const []))
        if (i is Map) ReactionItem.fromJson(i.cast<String, dynamic>()),
    ],
  );
}

class ReactionTimeline {
  ReactionTimeline(List<ReactionBucket> buckets)
    : buckets = List.unmodifiable(
        [...buckets]..sort((a, b) => a.t.compareTo(b.t)),
      );

  static final ReactionTimeline empty = ReactionTimeline(const []);

  /// Sorted by second.
  final List<ReactionBucket> buckets;

  bool get isEmpty => buckets.isEmpty;

  factory ReactionTimeline.fromJson(Map<String, dynamic> json) =>
      ReactionTimeline([
        for (final b in (json['buckets'] as List? ?? const []))
          if (b is Map) ReactionBucket.fromJson(b.cast<String, dynamic>()),
      ]);

  /// The timeline with one more reaction at [t] — the viewer's own, shown
  /// without waiting for the next fetch.
  ReactionTimeline withReaction(int t, String kind, String value) {
    final out = <ReactionBucket>[];
    var placed = false;
    for (final b in buckets) {
      if (b.t != t) {
        out.add(b);
        continue;
      }
      placed = true;
      final items = [...b.items];
      final i = items.indexWhere((x) => x.kind == kind && x.value == value);
      if (i >= 0) {
        items[i] = ReactionItem(kind: kind, value: value, count: items[i].count + 1);
      } else {
        items.add(ReactionItem(kind: kind, value: value, count: 1));
      }
      out.add(ReactionBucket(t: t, total: b.total + 1, items: items));
    }
    if (!placed) {
      out.add(
        ReactionBucket(
          t: t,
          total: 1,
          items: [ReactionItem(kind: kind, value: value, count: 1)],
        ),
      );
    }
    return ReactionTimeline(out);
  }

  /// Reaction density in [bins] equal slices of [durationSec], scaled so the
  /// busiest slice is 1. All zeros when there is nothing to draw.
  List<double> heatmap(int durationSec, {int bins = 100}) {
    final out = List<double>.filled(bins, 0);
    if (durationSec <= 0 || bins <= 0) return out;
    for (final b in buckets) {
      if (b.t < 0 || b.t > durationSec) continue;
      final i = b.t * bins ~/ durationSec;
      out[i < bins ? i : bins - 1] += b.total.toDouble();
    }
    var peak = 0.0;
    for (final v in out) {
      if (v > peak) peak = v;
    }
    if (peak <= 0) return out;
    for (var i = 0; i < bins; i++) {
      out[i] = out[i] / peak;
    }
    return out;
  }
}

/// One pill in the reaction lane: an emoji or text and how many people sent
/// it in the last few seconds — "🔥 ×12".
class ReactionPop {
  const ReactionPop({
    required this.kind,
    required this.value,
    required this.count,
    required this.lastSec,
  });

  final String kind;
  final String value;
  final int count;

  /// The latest second in the window this pill counts.
  final int lastSec;

  /// Stable while the pill is on screen, so it updates in place.
  String get id => '$kind:$value';

  @override
  bool operator ==(Object other) =>
      other is ReactionPop &&
      other.kind == kind &&
      other.value == value &&
      other.count == count &&
      other.lastSec == lastSec;

  @override
  int get hashCode => Object.hash(kind, value, count, lastSec);

  @override
  String toString() => 'ReactionPop($value x$count @$lastSec)';
}

/// Which reactions are on screen at a playhead position.
///
/// A reaction shows for [window] after its second. A jump — a seek either
/// way, or a gap longer than [jumpTolerance] between ticks — starts the
/// window afresh at the new position, so landing somewhere does not burst
/// the last few seconds before it onto the screen at once. The same emoji
/// within the window groups into one pill, and at most [maxVisible] show:
/// the most-sent first, the most recent among equals.
///
/// Pure: positions in, pills out.
class ReactionScheduler {
  ReactionScheduler({
    this.maxVisible = 3,
    this.window = const Duration(seconds: 4),
    this.jumpTolerance = const Duration(seconds: 2),
  });

  final int maxVisible;
  final Duration window;
  final Duration jumpTolerance;

  ReactionTimeline _timeline = ReactionTimeline.empty;
  Duration? _last;
  int _anchorSec = 0;

  ReactionTimeline get timeline => _timeline;

  void load(ReactionTimeline timeline) => _timeline = timeline;

  void clear() {
    _timeline = ReactionTimeline.empty;
    _last = null;
    _anchorSec = 0;
  }

  /// The pills for [position].
  List<ReactionPop> at(Duration position) {
    final last = _last;
    final posSec = position.inSeconds;
    if (last == null ||
        position < last ||
        position - last > jumpTolerance) {
      _anchorSec = posSec;
    }
    _last = position;
    if (_timeline.isEmpty || maxVisible <= 0) return const [];

    final fromSec = (posSec - window.inSeconds + 1) < _anchorSec
        ? _anchorSec
        : posSec - window.inSeconds + 1;

    final grouped = <String, ReactionPop>{};
    for (final b in _bucketsBetween(fromSec, posSec)) {
      for (final item in b.items) {
        final key = '${item.kind}:${item.value}';
        final prev = grouped[key];
        grouped[key] = ReactionPop(
          kind: item.kind,
          value: item.value,
          count: (prev?.count ?? 0) + item.count,
          lastSec: b.t,
        );
      }
    }
    final pops = grouped.values.toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        final byTime = b.lastSec.compareTo(a.lastSec);
        if (byTime != 0) return byTime;
        return a.value.compareTo(b.value);
      });
    return pops.length > maxVisible ? pops.sublist(0, maxVisible) : pops;
  }

  Iterable<ReactionBucket> _bucketsBetween(int fromSec, int toSec) sync* {
    final list = _timeline.buckets;
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].t < fromSec) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < list.length && list[i].t <= toSec; i++) {
      yield list[i];
    }
  }
}
