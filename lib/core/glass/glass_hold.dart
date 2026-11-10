import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Why a `GlassGroup`'s refraction is held — drawn as its tint alone,
/// reading nothing of the screen — right now.
///
/// Every reason the app has for holding glass is one of these, and a group
/// keeps them all in one [GlassHoldReasons]: "why is this glass flat?" is
/// answered by reading that one listenable, not six mechanisms.
enum GlassHoldReason {
  /// A [GlassHold] above the group is down, or a [GlassHoldWhile] — the
  /// player's seek bar being dragged, the screen turning.
  above,

  /// The route the group stands in is moving: coming, going, covered,
  /// uncovered, or dragged back by a finger on any navigator above it
  /// (`RouteMotion`).
  route,

  /// One of the phone's own views stands under the glass, or is about to
  /// (`_GlassWatch`, `GlassUnderlay`): the shader would draw a dark block
  /// over it.
  underView,

  /// The keyboard is moving under a [GlassKeyboardHold] above the group:
  /// every frame of the slide the shader would read the whole screen again
  /// for glass that moved with it, and the slide would drop frames. Held as
  /// a route is: the refraction only, the blur recipe drawn in its place,
  /// back once the keyboard has stood still for [GlassKeyboardHold.settle].
  keyboard,
}

/// The reasons one group's glass is held, as one listenable: empty when the
/// refraction may be drawn.
///
/// The group writes each reason as its source says it; [GlassHoldReason.above]
/// is written [quietly] — it arrives through the group's own dependency on
/// the holds above it, which rebuilds the group anyway.
final class GlassHoldReasons extends ChangeNotifier
    implements ValueListenable<Set<GlassHoldReason>> {
  Set<GlassHoldReason> _value = const {};

  @override
  Set<GlassHoldReason> get value => _value;

  /// Whether any reason holds the glass.
  bool get held => _value.isNotEmpty;

  /// Whether [reason] is one of them.
  bool has(GlassHoldReason reason) => _value.contains(reason);

  /// Says whether [reason] holds the glass now; listeners are told when the
  /// set changes, unless [quietly].
  void set(GlassHoldReason reason, bool holds, {bool quietly = false}) {
    if (holds == _value.contains(reason)) return;
    _value = Set.unmodifiable(
      holds ? {..._value, reason} : ({..._value}..remove(reason)),
    );
    if (!quietly) notifyListeners();
  }

  @override
  String toString() =>
      'GlassHoldReasons(${_value.map((reason) => reason.name).join(', ')})';
}

/// The glass put down: for the frames the screen moves under it most and
/// shows through it least — a page pushed over the tabs, the shell sliding
/// in — the glass under this is drawn with its blur switched off and its
/// tint alone (`GlassMode.blur`, disabled), and comes back up when they
/// land.
///
/// Holds nest, and combine: the glass is down while **any** hold above it
/// is ([downOf] reads up the chain), so a page's own hold that stands
/// false — no fade of its own running — never lifts the shell's that is
/// down. A group reads the chain as its [GlassHoldReason.above].
class GlassHold extends InheritedNotifier<ValueListenable<bool>> {
  const GlassHold({
    super.key,
    required ValueListenable<bool> down,
    required super.child,
  }) : super(notifier: down);

  /// Whether the glass at [context] is put down: any [GlassHold] above it
  /// down. [context] is told again when any hold it read changes; the walk
  /// stops at the first one down, which is all a change could matter
  /// through until it lifts.
  static bool downOf(BuildContext context) {
    var hold = context.getElementForInheritedWidgetOfExactType<GlassHold>();
    while (hold != null) {
      context.dependOnInheritedElement(hold);
      if ((hold.widget as GlassHold).notifier?.value ?? false) return true;
      hold = _above(hold);
    }
    return false;
  }

  /// The hold enclosing [hold], if any.
  static InheritedElement? _above(InheritedElement hold) {
    Element? parent;
    hold.visitAncestorElements((element) {
      parent = element;
      return false;
    });
    return parent?.getElementForInheritedWidgetOfExactType<GlassHold>();
  }
}

/// Puts the glass in [child] down ([GlassHold]) while [moving] says so,
/// asked again every time [source] ticks — a fade part-way, a page
/// controller between whole pages.
///
/// The one shape for "glass held while this is part-way". It nests in the
/// holds above it and combines with them ([GlassHold.downOf]).
class GlassHoldWhile extends StatefulWidget {
  const GlassHoldWhile({
    super.key,
    required this.source,
    required this.moving,
    required this.child,
  });

  /// What ticks while the thing moves: an animation, a page controller.
  final Listenable source;

  /// Whether it is part-way now; read on every tick of [source] and every
  /// time this is rebuilt.
  final bool Function() moving;

  final Widget child;

  @override
  State<GlassHoldWhile> createState() => _GlassHoldWhileState();
}

class _GlassHoldWhileState extends State<GlassHoldWhile> {
  final ValueNotifier<bool> _down = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_read);
    _read();
  }

  @override
  void didUpdateWidget(GlassHoldWhile old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) {
      old.source.removeListener(_read);
      widget.source.addListener(_read);
    }
    _read();
  }

  void _read() => _down.value = widget.moving();

  @override
  void dispose() {
    widget.source.removeListener(_read);
    _down.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GlassHold(down: _down, child: widget.child);
}

/// Says to the groups under it whether the keyboard is moving now — their
/// [GlassHoldReason.keyboard]. Here it is only the word, so the glass reads
/// it without knowing where the keyboard is measured.
///
/// Unlike a [GlassHold] it does not put the glass down: a group drawn as
/// the blur keeps its blur; only a refracting group gives way to the blur
/// recipe, as it does for its route moving.
class GlassKeyboardHold extends InheritedNotifier<ValueListenable<bool>> {
  const GlassKeyboardHold({
    super.key,
    required ValueListenable<bool> moving,
    required super.child,
  }) : super(notifier: moving);

  /// How long the keyboard stands still before the glass is given back —
  /// the length of [GlassGroup]'s own cross-fade back to the refraction,
  /// so a keyboard that pauses between two frames of its slide does not
  /// let the shader in for one of them.
  static const Duration settle = Duration(milliseconds: 120);

  /// Whether a [GlassKeyboardHold] above [context] says the keyboard is
  /// moving; [context] is told again when it changes.
  static bool movingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassKeyboardHold>()
          ?.notifier
          ?.value ??
      false;
}
