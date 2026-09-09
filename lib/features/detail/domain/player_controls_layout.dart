/// Where each player control sits, and what the viewer is allowed to do to it.
///
/// The bars used to be a hard-coded widget tree, and every argument about them
/// was an argument about that tree: six controls went behind a `⋯` sheet to buy
/// room and had to come back out; quality and episodes shared a slot, so on a
/// serial the quality panel was unreachable; the bottom row pinned everything
/// to the right edge whenever a film had no Previous/Next. Each fix moved one
/// button and risked the next report.
///
/// Layout is a viewer preference, so it belongs in data the viewer can edit,
/// not in a Row somebody has to re-argue.
///
/// ## Layout is not availability
///
/// These are two different questions and collapsing them is the mistake this
/// module exists to prevent:
///
///   * **Availability** — CAN this control exist right now? A film has no
///     episodes; a device without shader support has no Anime4K; a `cs:`
///     provider cannot join a watch party. Answered by `PlayerAffordances` and
///     the engine, never here.
///   * **Layout** — WHERE does the viewer want it, and do they want it at all?
///     Answered here, and only here.
///
/// A control that is laid out but unavailable simply does not render. A control
/// that is available but hidden does not render either. Neither one is an error,
/// and neither one may overwrite the other's answer.
///
/// Pure: ids in, ids out. No Flutter, no getIt, no I/O.
library;

/// The four places a control can live.
///
/// `bottomLeft` and `bottomRight` are the two groups either side of the bottom
/// row's `spaceBetween`. They are separate slots rather than one list because
/// the split is the whole point of that row: transport on the left, everything
/// else on the right. One list would give the viewer no way to express it.
enum PlayerControlSlot { topBar, bottomLeft, bottomRight, hidden }

/// One control the viewer can move.
class PlayerControlSpec {
  const PlayerControlSpec({
    required this.id,
    required this.labelKey,
    required this.defaultSlot,
    this.pinned = false,
  });

  /// Stable across releases — it is what gets written to storage. Renaming one
  /// silently resets that control to its default for everybody who had moved
  /// it, so these are never renamed; a control that goes away is removed from
  /// the catalogue and its stored id is then ignored on load.
  final String id;

  final String labelKey;

  /// Where it goes for a viewer who has never touched this screen, and where a
  /// control ADDED in a later release goes for a viewer who has.
  final PlayerControlSlot defaultSlot;

  /// Pinned controls cannot be moved or hidden.
  ///
  /// Exactly one thing is pinned: Settings. It is the way back to every panel
  /// that is not on a bar, so a viewer who hides it has hidden the escape
  /// hatch as well — with no way to reach the screen that would undo it.
  final bool pinned;
}

/// Every control the player can put on a bar.
abstract final class PlayerControlCatalogue {
  static const List<PlayerControlSpec> all = <PlayerControlSpec>[
    // ── transport ────────────────────────────────────────────────────────
    PlayerControlSpec(
      id: 'previous',
      labelKey: 'player.previous',
      defaultSlot: PlayerControlSlot.bottomLeft,
    ),
    PlayerControlSpec(
      id: 'next',
      labelKey: 'general.next',
      defaultSlot: PlayerControlSlot.bottomLeft,
    ),
    // ── the bottom row's value-carrying buttons ──────────────────────────
    PlayerControlSpec(
      id: 'speed',
      labelKey: 'player.speed',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'server',
      labelKey: 'player.server',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'quality',
      labelKey: 'player.quality',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'episodes',
      labelKey: 'player.episodes',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'shader',
      labelKey: 'player.enhance',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'fit',
      labelKey: 'player.fit',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'sleep',
      labelKey: 'player.sleep_timer',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'cast',
      labelKey: 'player.cast',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'party',
      labelKey: 'watch_party.title',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'pip',
      labelKey: 'player.pip',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    PlayerControlSpec(
      id: 'download',
      labelKey: 'player.download',
      defaultSlot: PlayerControlSlot.bottomRight,
    ),
    // ── the top bar ──────────────────────────────────────────────────────
    PlayerControlSpec(
      id: 'language',
      labelKey: 'player.audio_language',
      defaultSlot: PlayerControlSlot.topBar,
    ),
    PlayerControlSpec(
      id: 'subtitles',
      labelKey: 'player.subtitles',
      defaultSlot: PlayerControlSlot.topBar,
    ),
    PlayerControlSpec(
      id: 'orientation',
      labelKey: 'player.rotate',
      defaultSlot: PlayerControlSlot.topBar,
    ),
    PlayerControlSpec(
      id: 'lock',
      labelKey: 'player.lock',
      defaultSlot: PlayerControlSlot.topBar,
    ),
    PlayerControlSpec(
      id: 'settings',
      labelKey: 'player.settings',
      defaultSlot: PlayerControlSlot.topBar,
      pinned: true,
    ),
    PlayerControlSpec(
      id: 'stats',
      labelKey: 'player.info_title',
      defaultSlot: PlayerControlSlot.hidden,
    ),
  ];

  static PlayerControlSpec? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static bool isPinned(String id) => byId(id)?.pinned ?? false;
}

/// A viewer's arrangement of the bars.
///
/// Immutable: every edit returns a new layout, so the settings screen can hold
/// an undo stack and the player can compare against the old one cheaply.
class PlayerControlsLayout {
  const PlayerControlsLayout._(this._slots);

  final Map<PlayerControlSlot, List<String>> _slots;

  /// How many controls fit across the top bar.
  ///
  /// A real ceiling, not a style rule. The bar shares its width with the title,
  /// and its overflow behaviour is a `FittedBox` — an extra button does not wrap
  /// or scroll, it shrinks every button until none of them can be hit. Refusing
  /// the move is the honest answer; silently accepting it and letting the row
  /// scale to nothing is how the bar got into trouble before.
  ///
  /// Six, from the geometry rather than taste: `_IconButton` is 38pt with ~3pt
  /// between, and the action group is `flex: 5` of 7 beside the title. On the
  /// narrowest phone this ships to, six come to ~243pt in ~234pt of room — a
  /// 4% scale, invisible. Seven is ~284pt, an 18% scale, and that is where the
  /// glyphs start to read as smudges.
  ///
  /// The shipped default fills five of the six on purpose. A default that sits
  /// exactly on the ceiling makes the editor refuse the first move anybody
  /// tries, which reads as a broken screen rather than a full bar.
  static const int topBarCapacity = 6;

  /// The arrangement for a viewer who has never edited it.
  factory PlayerControlsLayout.defaults() {
    final slots = <PlayerControlSlot, List<String>>{
      for (final s in PlayerControlSlot.values) s: <String>[],
    };
    for (final spec in PlayerControlCatalogue.all) {
      slots[spec.defaultSlot]!.add(spec.id);
    }
    return PlayerControlsLayout._(slots);
  }

  /// Rebuilds a layout from storage.
  ///
  /// Three things this has to survive, all of which happen on a real upgrade:
  ///
  ///   * **A control added since the layout was saved.** It is absent from
  ///     storage entirely, which is different from being hidden — hiding puts
  ///     an id in the `hidden` list. So absent means new, and new goes to its
  ///     default slot. Without this an upgrade would leave the new control
  ///     invisible forever, with nothing on screen to explain why.
  ///   * **A control removed since.** Its stored id matches no spec and is
  ///     dropped rather than carried as a ghost the settings screen cannot draw.
  ///   * **A stored top bar over capacity**, from an older build with a larger
  ///     ceiling. The overflow moves to `hidden` in stored order, so the result
  ///     is deterministic and the viewer's first choices are the ones kept.
  factory PlayerControlsLayout.fromStored(Map<String, List<String>> stored) {
    final slots = <PlayerControlSlot, List<String>>{
      for (final s in PlayerControlSlot.values) s: <String>[],
    };
    final placed = <String>{};

    for (final slot in PlayerControlSlot.values) {
      for (final id in stored[slot.name] ?? const <String>[]) {
        if (PlayerControlCatalogue.byId(id) == null) continue;
        if (!placed.add(id)) continue; // an id listed twice lands once
        slots[slot]!.add(id);
      }
    }

    for (final spec in PlayerControlCatalogue.all) {
      if (placed.contains(spec.id)) continue;
      slots[spec.defaultSlot]!.add(spec.id);
    }

    // Pinned controls stay reachable even if storage says otherwise — an
    // older build, a hand-edited box, or a bug must not be able to strand a
    // viewer with no way back to the settings sheet.
    for (final spec in PlayerControlCatalogue.all) {
      if (!spec.pinned) continue;
      if (slots[spec.defaultSlot]!.contains(spec.id)) continue;
      for (final list in slots.values) {
        list.remove(spec.id);
      }
      slots[spec.defaultSlot]!.add(spec.id);
    }

    final top = slots[PlayerControlSlot.topBar]!;
    while (top.length > topBarCapacity) {
      final overflow = top.removeLast();
      if (PlayerControlCatalogue.isPinned(overflow)) {
        top.insert(0, overflow);
        break;
      }
      slots[PlayerControlSlot.hidden]!.add(overflow);
    }

    return PlayerControlsLayout._(slots);
  }

  Map<String, List<String>> toStored() => {
        for (final e in _slots.entries) e.key.name: List<String>.of(e.value),
      };

  List<String> of(PlayerControlSlot slot) =>
      List<String>.unmodifiable(_slots[slot] ?? const <String>[]);

  PlayerControlSlot slotOf(String id) {
    for (final e in _slots.entries) {
      if (e.value.contains(id)) return e.key;
    }
    return PlayerControlSlot.hidden;
  }

  /// Whether the top bar has room for one more.
  bool get topBarIsFull =>
      _slots[PlayerControlSlot.topBar]!.length >= topBarCapacity;

  int get topBarCount => _slots[PlayerControlSlot.topBar]!.length;

  /// Whether [id] may go to [to] — and, when it may not, `moveRefusal` says why.
  bool canMove(String id, PlayerControlSlot to) => moveRefusal(id, to) == null;

  /// The reason [id] cannot go to [to], as a translation key, or null when it
  /// can. A refusal the viewer can read beats a drag that springs back.
  String? moveRefusal(String id, PlayerControlSlot to) {
    final spec = PlayerControlCatalogue.byId(id);
    if (spec == null) return 'player.layout_unknown_control';
    if (spec.pinned && to != slotOf(id)) return 'player.layout_pinned';
    if (to == PlayerControlSlot.topBar &&
        slotOf(id) != PlayerControlSlot.topBar &&
        topBarIsFull) {
      return 'player.layout_top_bar_full';
    }
    return null;
  }

  /// Moves [id] into [to], appending unless [index] says otherwise. Returns
  /// this layout unchanged when the move is refused, so a caller that skips
  /// [canMove] still cannot produce an invalid arrangement.
  PlayerControlsLayout move(String id, PlayerControlSlot to, {int? index}) {
    if (!canMove(id, to)) return this;
    final next = _copy();
    for (final list in next.values) {
      list.remove(id);
    }
    final target = next[to]!;
    final at = index == null ? target.length : index.clamp(0, target.length);
    target.insert(at, id);
    return PlayerControlsLayout._(next);
  }

  /// Reorders within one slot. Out-of-range indices are clamped rather than
  /// thrown: a reorder callback is driven by a drag, and a drag that ends off
  /// the edge of the list is ordinary.
  PlayerControlsLayout reorder(PlayerControlSlot slot, int from, int to) {
    final next = _copy();
    final list = next[slot]!;
    if (list.isEmpty) return this;
    final f = from.clamp(0, list.length - 1);
    final id = list.removeAt(f);
    list.insert(to.clamp(0, list.length), id);
    return PlayerControlsLayout._(next);
  }

  /// Whether this is still the shipped arrangement — what decides if Reset has
  /// anything to undo.
  bool get isDefault {
    final d = PlayerControlsLayout.defaults();
    for (final slot in PlayerControlSlot.values) {
      final a = _slots[slot]!;
      final b = d._slots[slot]!;
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return true;
  }

  Map<PlayerControlSlot, List<String>> _copy() => {
        for (final e in _slots.entries) e.key: List<String>.of(e.value),
      };
}
