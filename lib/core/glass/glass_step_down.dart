import 'package:flutter/foundation.dart';

/// How long one frame has on this screen: the thing every judgement about
/// whether the refraction is affordable is actually made against.
///
/// A phone's refresh rate is the only honest budget. The same GPU that keeps
/// the glass at 60 Hz has 8.3 ms rather than 16.7 to do it in on a 120 Hz
/// panel, and the glass is the most expensive thing on the screen, so the
/// panel is read from the phone ([GlassPowerReading.refreshHz]) rather than
/// assumed.
@immutable
final class GlassFrameBudget {
  const GlassFrameBudget(this.frame);

  /// What a frame has, end to end.
  final Duration frame;

  /// Sixty hertz: what a phone that has not said — a test, a build without
  /// the bridge — is taken to have.
  static const GlassFrameBudget sixty = GlassFrameBudget(
    Duration(microseconds: 16667),
  );

  /// The budget of a panel running at [hz]. A rate the phone could not give
  /// — zero, a negative, not a number — is [sixty]; anything outside what a
  /// phone panel can actually be is clamped into range, because a budget
  /// read wrong is worse than a budget assumed.
  factory GlassFrameBudget.ofRefreshRate(double hz) {
    if (!hz.isFinite || hz <= 0) return sixty;
    final rate = hz.clamp(24.0, 240.0);
    return GlassFrameBudget(
      Duration(microseconds: (1000000 / rate).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassFrameBudget && other.frame == frame;

  @override
  int get hashCode => frame.hashCode;

  @override
  String toString() => 'GlassFrameBudget(${frame.inMicroseconds}us)';
}

/// Whether this phone, having been let through the gate, is in fact keeping
/// up with the refraction — and, when it plainly is not, the decision to
/// stop drawing it.
///
/// No flag a phone carries says whether its GPU can bend the screen sixty
/// times a second; the frames it actually draws do. So the gate
/// ([GlassPowerReading]) only keeps out the phones that could never manage
/// it, and this watches what happens to the ones it let through: while a
/// refracting glass is on the screen, each frame's whole span is measured
/// against the panel's budget, and a phone that keeps missing it is dropped
/// to the blur. A plainer glass at the full frame rate is the better phone;
/// the right glass as a slideshow is not.
///
/// Three things keep it from firing on frames that are not the glass's
/// fault:
///
/// * **Warm-up.** The frames just after a refracting glass comes up pay for
///   the shader being compiled and the page being laid out, and are always
///   over budget. [warmup] of them are measured and thrown away, and the
///   count starts again every time the glass goes and comes back.
/// * **A window, not a frame.** A frame is missed on any phone — a decode
///   landing, a garbage collection — so [misses] of the last [window] have
///   to be over before anything happens.
/// * **Slack.** A frame is only counted missed past [slack] of the budget:
///   Flutter's own reported span runs a little over the vsync interval on a
///   perfectly smooth phone, and 1.5 of it is well clear of that while
///   still being half the frame rate.
///
/// The decision **latches**: once down the glass stays the blur for the rest
/// of the app's run. A phone drawn as glass on a quiet page and as blur the
/// moment anything scrolls would flip back and forth all day, and glass that
/// comes and goes reads as a fault rather than as a kindness.
final class GlassStepDown {
  GlassStepDown({
    GlassFrameBudget budget = GlassFrameBudget.sixty,
    this.warmup = 12,
    this.window = 60,
    this.misses = 18,
    this.slack = 1.5,
  }) : _budget = budget,
       assert(warmup >= 0),
       assert(window > 0),
       assert(misses > 0 && misses <= window),
       assert(slack >= 1);

  /// What one frame has on this phone's panel.
  GlassFrameBudget get budget => _budget;
  GlassFrameBudget _budget;

  /// The panel's rate is not known when the policy is made. It is read off
  /// the phone over a channel, and the answer lands a frame or two after the
  /// first refracting glass has already come up and armed the measuring — so
  /// a policy that could only be told its budget at birth would spend every
  /// run on a 120 Hz phone judging frames against sixty hertz, which is the
  /// one direction that makes the measurement useless rather than wrong:
  /// nothing would ever be condemned.
  ///
  /// Setting it throws the window away and pays the warm-up again, because a
  /// frame already weighed against the wrong budget is not evidence of
  /// anything.
  set budget(GlassFrameBudget value) {
    if (value == _budget) return;
    _budget = value;
    restart();
  }

  /// Frames measured and thrown away each time the glass comes up.
  final int warmup;

  /// How many of the last frames are kept.
  final int window;

  /// How many of them have to be over budget.
  final int misses;

  /// How far over the budget a frame goes before it counts as missed.
  final double slack;

  /// The frames kept, oldest first: true for each one over budget. A list
  /// of bools rather than a count, because a count cannot be rolled off the
  /// back of the window.
  final List<bool> _kept = [];

  int _warmed = 0;
  bool _down = false;

  /// Whether the glass has been dropped to the blur. Once true, always true.
  bool get down => _down;

  /// How far through the window the misses stand: what a test reads to say
  /// the policy is counting, and what a debug overlay would show.
  @visibleForTesting
  int get debugMisses => _kept.where((missed) => missed).length;

  /// A refracting glass has come up on the screen, or the last one has gone:
  /// either way the warm-up and the window start again. Frames drawn with no
  /// refracting glass say nothing about the refraction and are not kept, and
  /// the glass coming back pays its warm-up afresh, so both turns clear the
  /// same two things.
  void restart() {
    _warmed = 0;
    _kept.clear();
  }

  /// One frame of the phone's, start to finish. Returns whether this frame
  /// is the one that stepped the glass down — true once, never again — so
  /// that the caller tells the tree only on the turn.
  bool frame(Duration span) {
    if (_down) return false;
    if (_warmed < warmup) {
      _warmed++;
      return false;
    }
    _kept.add(span > budget.frame * slack);
    if (_kept.length > window) _kept.removeAt(0);
    if (_kept.length < misses) return false;
    if (debugMisses < misses) return false;
    _down = true;
    return true;
  }

  @override
  String toString() =>
      'GlassStepDown(down: $_down, misses: $debugMisses/${_kept.length})';
}
