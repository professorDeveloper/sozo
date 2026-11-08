import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'native_bar_layout.dart';
import 'native_controls_gate.dart';
import 'native_link.dart';

/// How a bar's buttons stand on the glass.
enum NativeBarLook {
  /// One clear glass capsule per group, plain buttons on it.
  capsule,

  /// Each button its own glass circle.
  cluster,
}

/// One row of a button's menu.
@immutable
class NativeMenuRow {
  const NativeMenuRow({
    required this.title,
    this.symbol,
    this.checked,
    this.breakBefore = false,
    this.destructive = false,
    this.key,
  });

  final String title;
  final String? symbol;

  /// Null draws no check column; false an empty one.
  final bool? checked;
  final bool breakBefore;
  final bool destructive;

  /// What the row stands for, so a choice made while the rows changed under
  /// the open menu still lands on the row the viewer saw. The title without.
  final Object? key;

  bool _same(NativeMenuRow other) =>
      key != null ? key == other.key : title == other.title;

  Map<String, Object?> toWire() => {
    'title': title,
    'symbol': symbol,
    'checked': checked,
    'breakBefore': breakBefore,
    'destructive': destructive,
  };
}

/// One button of a [NativeGlassBar].
@immutable
class NativeBarItem {
  const NativeBarItem({
    required this.id,
    required this.symbol,
    required this.semanticLabel,
    this.title,
    this.enabled = true,
    this.active = false,
    this.busy = false,
    this.prominent = false,
    this.hidden = false,
    this.extent,
    this.size,
    this.glyph = 20,
    this.fontSize = 12,
    this.hasGlyph = true,
    this.group = 0,
    this.onPressed,
    this.onLongPress,
    this.menu,
    this.onMenuSelected,
  });

  final String id;

  /// An SF Symbol name; empty for words alone.
  final String symbol;
  final String? title;
  final String semanticLabel;
  final bool enabled;

  /// Drawn in the accent, and said selected.
  final bool active;

  /// A ring turning on the rim: buffering.
  final bool busy;

  /// The tinted glass of the one action that matters most (play).
  final bool prominent;

  /// Keeps its slot and draws nothing: the room an absent Previous leaves,
  /// so play stays in the middle.
  final bool hidden;

  /// The square slot the button stands in; null is the bar's own slot.
  final double? extent;

  /// The drawn circle of a cluster button, centred in its slot; null fills it.
  final double? size;
  final double glyph;
  final double fontSize;
  final bool hasGlyph;
  final int group;
  final VoidCallback? onPressed;

  /// A hold on a button without a menu, and VoiceOver's long press on any:
  /// the Flutter sheet behind a menu stays one gesture away.
  final VoidCallback? onLongPress;

  /// Opened by a hold, as UIKit's own buttons open theirs.
  final List<NativeMenuRow>? menu;
  final ValueChanged<int>? onMenuSelected;

  BarSlotSpec get _slot => BarSlotSpec(
    extent: extent,
    label: title,
    fontSize: fontSize,
    glyph: glyph,
    hasGlyph: hasGlyph,
    group: group,
  );
}

/// A group of player controls as the phone's own glass buttons, in one
/// hosted view (ios/Runner/NativePlayerBar.swift), or [fallback] wherever the
/// gate says no ([NativeControls]) or the slots do not fit.
///
/// Dart lays it out ([layoutBar]) and sends the rects; UIKit only places the
/// buttons. Hits land only on a slot ([SlotHitBox]), so the gaps stay the
/// page's. It fades itself, in UIKit, on [shown], and leaves the frame once
/// faded so a hidden bar costs no composition.
class NativeGlassBar extends StatefulWidget {
  const NativeGlassBar({
    super.key,
    required this.items,
    required this.look,
    required this.fallback,
    this.shown = true,
    this.axis = Axis.horizontal,
    this.direction,
    this.spread = BarSpread.packed,
    this.maxExtent = double.infinity,
    this.accent = const Color(0xFFFFFFFF),
    this.dim = const Color(0x38000000),
    this.onMenuOpen,
    this.onMenuClose,
  });

  static const String viewType = 'soplay/native_player_bar';

  /// How long the bar takes to fade, as the controls' own fade.
  static const Duration fade = Duration(milliseconds: 220);

  final List<NativeBarItem> items;
  final NativeBarLook look;
  final WidgetBuilder fallback;
  final bool shown;
  final Axis axis;

  /// Null is the ambient direction; transport passes LTR.
  final TextDirection? direction;
  final BarSpread spread;

  /// A cap under the room the parent gives.
  final double maxExtent;
  final Color accent;

  /// The capsule glass's tint; words on it want a deeper one.
  final Color dim;
  final VoidCallback? onMenuOpen;
  final VoidCallback? onMenuClose;

  @override
  State<NativeGlassBar> createState() => _NativeGlassBarState();
}

class _NativeGlassBarState extends State<NativeGlassBar>
    with NativeControlState<NativeGlassBar> {
  /// One set for the view's life: a new one each build would replace the
  /// recognizers mid-press.
  static final _gestures = pressGestures();

  BarLayout? _layout;
  TextDirection _dir = TextDirection.ltr;
  double _scale = 1;
  bool _reduceMotion = false;

  /// Faded out and out of the frame.
  late bool _gone = !widget.shown;
  Timer? _fading;

  Animation<double>? _route;
  bool _routeMoving = false;

  /// The rows each menu was last sent, by item: a row is chosen by its index
  /// in those.
  final Map<String, List<NativeMenuRow>> _toldRows = {};

  /// The rows of a menu as it was when it opened: UIKit keeps showing those
  /// while it is up, whatever was sent since.
  final Map<String, List<NativeMenuRow>> _openRows = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final route = ModalRoute.of(context)?.animation;
    if (route != _route) {
      _route?.removeStatusListener(_routeStatus);
      _route = route;
      route?.addStatusListener(_routeStatus);
      _routeMoving = route != null && !route.isCompleted;
    }
  }

  void _routeStatus(AnimationStatus status) {
    final moving = !status.isCompleted;
    if (moving != _routeMoving && mounted) {
      setState(() => _routeMoving = moving);
    }
  }

  @override
  void didUpdateWidget(NativeGlassBar old) {
    super.didUpdateWidget(old);
    if (old.shown == widget.shown) return;
    _fading?.cancel();
    if (widget.shown) {
      _gone = false;
    } else {
      _fading = Timer(_reduceMotion ? Duration.zero : NativeGlassBar.fade, () {
        if (mounted && !widget.shown) setState(() => _gone = true);
      });
    }
  }

  @override
  void dispose() {
    _fading?.cancel();
    _route?.removeStatusListener(_routeStatus);
    super.dispose();
  }

  Map<String, Object?> _shownWire() => {
    'shown': widget.shown,
    'ms': _reduceMotion ? 0 : NativeGlassBar.fade.inMilliseconds,
  };

  Map<String, Object?> _itemWire(NativeBarItem item, Rect rect) => {
    'id': item.id,
    'symbol': item.hasGlyph ? item.symbol : '',
    'title': item.title,
    'enabled': item.enabled,
    'active': item.active,
    'busy': item.busy,
    'prominent': item.prominent,
    'hidden': item.hidden,
    'size': item.size ?? item.extent,
    'glyph': item.glyph,
    'fontSize': _scale * item.fontSize,
    'accent': widget.accent.toARGB32(),
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'group': item.group,
    'menu': item.menu?.map((r) => r.toWire()).toList(),
    'longPress': item.onLongPress != null,
  };

  Map<String, Object?> _payload(BarLayout layout) => {
    'items': [
      for (var i = 0; i < widget.items.length; i++)
        _itemWire(widget.items[i], layout.slots[i]),
    ],
    'look': widget.look.name,
    'dim': widget.dim.toARGB32(),
    'dir': _dir == TextDirection.rtl ? 'rtl' : 'ltr',
    'axis': widget.axis.name,
    'capsules': [
      for (final r in layout.capsules) [r.left, r.top, r.width, r.height],
    ],
  };

  /// What a full `setItems` is needed for: anything that moves a button.
  static const _placing = {'id', 'rect', 'group'};

  static Object? _structure(Map<String, Object?> payload) => {
    for (final e in payload.entries)
      if (e.key != 'items') e.key: e.value,
    'items': [
      for (final item in payload['items']! as List)
        {for (final k in _placing) k: (item as Map)[k]},
    ],
  };

  @override
  void sync() {
    final layout = _layout;
    if (layout == null || layout.slots.length != widget.items.length) return;
    final payload = _payload(layout);
    final told = toldOf('setItems') as Map<String, Object?>?;
    if (told == null || !nativeSame(_structure(told), _structure(payload))) {
      say('setItems', payload);
    } else {
      final before = told['items']! as List;
      final now = payload['items']! as List;
      for (var i = 0; i < now.length; i++) {
        final was = before[i] as Map;
        final item = now[i] as Map<String, Object?>;
        final changed = <String, Object?>{
          for (final e in item.entries)
            if (!_placing.contains(e.key) && !nativeSame(was[e.key], e.value))
              e.key: e.value,
        };
        if (changed.isNotEmpty) say('setItem', {'id': item['id'], ...changed});
      }
    }
    remember('setItems', payload);
    for (final item in widget.items) {
      final rows = item.menu;
      if (rows == null) {
        _toldRows.remove(item.id);
      } else {
        _toldRows[item.id] = rows;
      }
    }
    tell('setShown', _shownWire());
  }

  NativeBarItem? _item(Object? id) {
    for (final item in widget.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  void heard(String method, Object? arguments) {
    switch (method) {
      case 'press':
        final item = _item(arguments);
        if (item != null && item.enabled) item.onPressed?.call();
      case 'longPress':
        final item = _item(arguments);
        if (item != null && item.enabled) item.onLongPress?.call();
      case 'select':
        if (arguments is! Map) return;
        final item = _item(arguments['id']);
        final row = arguments['row'];
        final told = _openRows[item?.id] ?? _toldRows[item?.id];
        final rows = item?.menu;
        if (item == null || row is! int || told == null || rows == null) return;
        if (row < 0 || row >= told.length) return;
        final index = rows.indexWhere((r) => r._same(told[row]));
        if (index >= 0) item.onMenuSelected?.call(index);
      case 'menuOpen':
        final rows = _toldRows[arguments];
        if (arguments is String && rows != null) _openRows[arguments] = rows;
        widget.onMenuOpen?.call();
      case 'menuClose':
        _openRows.remove(arguments);
        widget.onMenuClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeControls.of(context)) return widget.fallback(context);
    final scaler = MediaQuery.textScalerOf(context);
    _dir = widget.direction ?? Directionality.of(context);
    _scale = scaler.scale(1);
    return LayoutBuilder(
      builder: (context, box) {
        final room = widget.axis == Axis.horizontal
            ? box.maxWidth
            : box.maxHeight;
        final max = room < widget.maxExtent ? room : widget.maxExtent;
        final layout = layoutBar(
          slots: [for (final item in widget.items) item._slot],
          dir: _dir,
          axis: widget.axis,
          maxExtent: max,
          capsules: widget.look == NativeBarLook.capsule,
          spread: widget.spread,
          textScaler: scaler,
        );
        if (layout == null) return widget.fallback(context);
        final first = _layout == null;
        _layout = layout;
        if (!first) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && linked) sync();
          });
        }
        return _hostBar(layout);
      },
    );
  }

  Widget _hostBar(BarLayout layout) {
    final hits = widget.look == NativeBarLook.capsule
        ? layout.capsules
        : [
            for (var i = 0; i < widget.items.length; i++)
              if (!widget.items[i].hidden) layout.slots[i],
          ];
    final payload = _payload(layout);
    final shown = _shownWire();
    final interactive = widget.shown && !_gone && !_routeMoving;
    return Offstage(
      offstage: _gone || _routeMoving,
      child: SizedBox.fromSize(
        size: layout.size,
        child: Stack(
          children: [
            Positioned.fill(
              child: SlotHitBox(
                rects: hits,
                enabled: interactive,
                child: ExcludeSemantics(
                  child: hosted(
                    type: NativeGlassBar.viewType,
                    params: {...payload, 'shown': widget.shown},
                    gestures: _gestures,
                    made: {'setItems': payload, 'setShown': shown},
                  ),
                ),
              ),
            ),
            for (var i = 0; i < widget.items.length; i++)
              if (!widget.items[i].hidden)
                Positioned.fromRect(
                  rect: layout.slots[i],
                  child: _slotSemantics(widget.items[i]),
                ),
          ],
        ),
      ),
    );
  }

  Widget _slotSemantics(NativeBarItem item) => Semantics(
    container: true,
    button: true,
    label: item.semanticLabel,
    value: item.title == item.semanticLabel ? null : item.title,
    enabled: item.enabled,
    selected: item.active,
    onTap: item.enabled ? item.onPressed : null,
    onLongPress: item.enabled ? item.onLongPress : null,
    child: const SizedBox.expand(),
  );
}

/// Answers a hit only inside [rects]: the gaps between a bar's buttons are
/// the page's, so a tap there still toggles the controls and a double tap
/// still seeks.
class SlotHitBox extends SingleChildRenderObjectWidget {
  const SlotHitBox({
    super.key,
    required this.rects,
    this.enabled = true,
    super.child,
  });

  final List<Rect> rects;
  final bool enabled;

  @override
  RenderSlotHitBox createRenderObject(BuildContext context) =>
      RenderSlotHitBox(rects, enabled: enabled);

  @override
  void updateRenderObject(BuildContext context, RenderSlotHitBox renderObject) {
    renderObject
      ..rects = rects
      ..enabled = enabled;
  }
}

class RenderSlotHitBox extends RenderProxyBox {
  RenderSlotHitBox(this.rects, {this.enabled = true});

  List<Rect> rects;
  bool enabled;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!enabled || !rects.any((r) => r.contains(position))) return false;
    return super.hitTest(result, position: position);
  }
}
