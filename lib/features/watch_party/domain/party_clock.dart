/// Server clock offset from `party:ping` / `party:pong` round trips.
///
/// A sync's `positionSec` is where the server put the room at `serverTime`.
/// Reading it as "where the room is at the moment it arrived" is late by the
/// one-way trip, so a guest on a slow link always trails the host by that
/// much. With an offset, the local instant the server meant can be recovered
/// and the trip taken out.
///
/// Pure: millisecond timestamps in, numbers out.
class PartyClock {
  PartyClock({this.window = 8});

  /// How many recent round trips are kept. The one with the shortest trip
  /// wins: queueing only ever adds delay, so the fastest sample is the least
  /// skewed.
  final int window;

  /// Round trips slower than this say more about the network than the clock.
  static const int maxRttMs = 5000;

  /// The most an alignment may move a receipt back. Beyond this the offset is
  /// stale or wrong and the receipt time is the safer guess.
  static const int maxShiftMs = 3000;

  final List<_Sample> _samples = <_Sample>[];

  /// Records one round trip: [sentAt] and [receivedAt] on this device's clock,
  /// [serverTime] on the server's. Returns false when the sample is unusable.
  bool add({required int sentAt, required int serverTime, required int receivedAt}) {
    final rtt = receivedAt - sentAt;
    if (rtt < 0 || rtt > maxRttMs) return false;
    _samples.add(_Sample(rtt, serverTime - (sentAt + rtt / 2).round()));
    if (_samples.length > window) _samples.removeAt(0);
    return true;
  }

  void reset() => _samples.clear();

  _Sample? get _best {
    _Sample? best;
    for (final s in _samples) {
      if (best == null || s.rtt < best.rtt) best = s;
    }
    return best;
  }

  /// Server clock minus local clock, or null before the first usable sample.
  int? get offsetMs => _best?.offset;

  int? get rttMs => _best?.rtt;

  /// The local instant the server meant by [serverTime], for a message that
  /// arrived at [receivedAt]. Falls back to [receivedAt] without an offset, or
  /// when the answer would be in the future or implausibly far back.
  DateTime align({required int? serverTime, required DateTime receivedAt}) {
    final offset = offsetMs;
    if (serverTime == null || offset == null) return receivedAt;
    final local = serverTime - offset;
    final shift = receivedAt.millisecondsSinceEpoch - local;
    if (shift < 0 || shift > maxShiftMs) return receivedAt;
    return DateTime.fromMillisecondsSinceEpoch(local);
  }
}

class _Sample {
  const _Sample(this.rtt, this.offset);
  final int rtt;
  final int offset;
}
