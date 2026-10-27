part of 'glass_surface.dart';

/// Watches where a group's glass stands on the screen: over one of the
/// phone's own views, and carried somewhere without being painted again.
///
/// **Over the phone's own view.** A view UIKit draws inside the app — the
/// native tab bar, a web page, the AirPlay button — is
/// not in Flutter's picture: the engine cuts the picture at it, and what
/// Flutter draws over the view goes into a layer of its own above it. The
/// refraction shader there reads that layer's backdrop, which holds
/// nothing of the page, and it writes the glass fully opaque wherever its
/// shape is — so the glass over the view's frame came out a hard-edged
/// dark block under the tint, the size of the view's frame. Such a group
/// is held ([GlassHoldReason.underView]) for as long as any view drawn
/// before it on the screen reaches under it, and given back when none does.
/// Views drawn after it stand over the glass and leave its picture alone.
///
/// Where the views are is read after a frame from the layers the frame
/// was made of ([GlassUnderlay]), and decides the next frame — so it is
/// read ahead: a view or a glass moving is taken to move as far again by
/// the next frame, and a glass about to be drawn over where a view stood
/// is not drawn for that one frame rather than drawn wrong. Only the views
/// drawn before the glass in the last frame are read ahead: a view drawn
/// after the page — the native tab bar slid away under a pushed page — taken
/// for one under a glass would keep that glass out of every frame. A frame
/// the glass was left out of that the
/// frame's own layers then find clear is followed by one it is drawn in,
/// whatever the reading ahead says: left out, it stays out until something
/// else asks for a frame.
///
/// **Carried without a paint.** The renderer bakes where its shapes stand
/// on the screen into the shader's matte when it paints, and notices that
/// they have moved only while the frame is being composited — too late
/// for that frame, and, as the frame is already under way, without asking
/// for another (`ensureVisualUpdate` asks for nothing mid-frame). A glass
/// carried by a layout — a sheet growing to its detent, a sheet fitting
/// content that landed, a keyboard pushing it up — kept the matte of where
/// it stood a frame before, until anything else drew a frame: the shader
/// bent the shape where it had been, and the ✕'s lower half showed the
/// page above the sheet. One frame more after the move, and the matte is
/// where the glass is.
class _GlassWatch extends SingleChildRenderObjectWidget {
  const _GlassWatch({required this.liquid, required this.onUnder, super.child});

  /// The refraction is drawn: only then does a move ask for a frame more.
  final bool liquid;

  /// Told after a frame whether a view of the phone's stands under the
  /// glass.
  final ValueChanged<bool> onUnder;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassWatch(liquid: liquid, onUnder: onUnder);

  @override
  void updateRenderObject(BuildContext context, _RenderGlassWatch box) {
    box
      ..liquid = liquid
      ..onUnder = onUnder;
  }
}

class _RenderGlassWatch extends RenderProxyBox {
  _RenderGlassWatch({required bool liquid, required this.onUnder})
    : _liquid = liquid;

  bool _liquid;
  bool get liquid => _liquid;
  set liquid(bool value) {
    if (value == _liquid) return;
    _liquid = value;
    markNeedsPaint();
  }

  ValueChanged<bool> onUnder;

  /// What the last frame found, and where the glass stood on the screen
  /// then.
  bool under = false;
  Rect? lastOnScreen;

  /// Where the glass stood, through every transform above it, the last
  /// time the frame's layers were read: a change asks for a frame more
  /// (carried without a paint).
  Matrix4? lastTransform;

  /// The views drawn before the glass in the last frame — the ones that
  /// can stand under it; null before its first frame.
  Set<int>? viewsBefore;

  /// The glass was left out of this frame, read ahead to be over a view.
  bool skipped = false;

  /// The frame's layers found it clear after all: the next paint draws it
  /// whatever the reading ahead says.
  bool cleared = false;

  /// The group's place in the frame's layers ([_WatchLayer]).
  Layer? get mark => layer;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlassUnderlay._watch(this);
  }

  @override
  void detach() {
    GlassUnderlay._unwatch(this);
    super.detach();
  }

  /// Said once the frame is through: the group cannot be rebuilt from
  /// inside one.
  void tell(bool value) {
    if (value == under) return;
    under = value;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached && under == value) onUnder(value);
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final mark = (layer as _WatchLayer?) ?? _WatchLayer();
    layer = mark
      ..box = this
      ..rect = offset & size;
    context.pushLayer(mark, (context, offset) {}, offset);
    final wasCleared = cleared;
    cleared = false;
    skipped =
        _liquid &&
        !wasCleared &&
        GlassUnderlay._ahead(
          MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size),
          lastOnScreen,
          viewsBefore,
        );
    if (skipped) {
      // About to refract over a view of the phone's: not drawn this one
      // frame, and held from the next.
      tell(true);
      return;
    }
    super.paint(context, offset);
  }

  /// The frame's layers found the glass clear of every view under it: a
  /// glass left out of this frame on the reading ahead is drawn in the
  /// next, asked for once this one is through.
  void foundClear() {
    if (!skipped) return;
    skipped = false;
    cleared = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) markNeedsPaint();
    });
  }
}

/// A mark in the frame's layers: laid in again — attached — whenever
/// whatever it stands in is painted again, moved by a paint, or brought
/// back into the frame (a tab shown again). That is the only way a glass
/// or a view can come to stand somewhere else on the screen, so a frame in
/// which no mark was laid in again is one in which nothing a glass could be
/// over has changed ([GlassUnderlay]).
///
/// An empty layer: it costs a push in the scene, and is never composited
/// again for its own sake — the glass's used to be, every frame
/// ([Layer.alwaysNeedsAddToScene]), to notice a move; that now happens
/// when the layers are read.
class _Mark extends OffsetLayer {
  @override
  void attach(Object owner) {
    super.attach(owner);
    GlassUnderlay._stir();
  }

  @override
  void detach() {
    GlassUnderlay._stir();
    super.detach();
  }
}

/// The group's place in the frame's layers: where it stands, and what was
/// drawn before it.
class _WatchLayer extends _Mark {
  _RenderGlassWatch? box;

  /// The group's box in its parent layer's space.
  Rect rect = Rect.zero;
}

/// Where one of the app's own views of the phone's is drawn, just before
/// it in the frame's layers ([PlatformViewMark]).
class _ViewMarkLayer extends _Mark {}

/// Marks a view of the phone's — a [UiKitView] the app makes
/// (`ChannelNativeHost`) — in the frame's layers, so that the glass knows
/// when it may have moved, come or gone ([GlassUnderlay]) without reading
/// every layer of every frame.
///
/// A view drawn without one (a web page, a test's stand-in) is still found
/// and still holds the glass; only, while one is on the screen, every
/// frame's layers are read, as they all were before.
class PlatformViewMark extends SingleChildRenderObjectWidget {
  const PlatformViewMark({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlatformViewMark();
}

class _RenderPlatformViewMark extends RenderProxyBox {
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final mark = (layer as _ViewMarkLayer?) ?? _ViewMarkLayer();
    layer = mark;
    context.pushLayer(mark, (context, offset) {}, offset);
    super.paint(context, offset);
  }
}

/// After a frame, the views of the phone's that the frame drew, and which
/// glass stands over one of them ([_GlassWatch]).
///
/// The frame's layers are read only after a frame that may have moved
/// something a glass could be over — not after every frame while any glass
/// is on the screen, as before (a spinner elsewhere on a settled page drew
/// sixty frames a second, and each one walked every layer of the screen):
///
/// * a glass's or a marked view's mark was laid in again or taken out
///   ([_Mark]) — painted, moved by a paint, shown or hidden;
/// * a glass came or went;
/// * the last reading found a view moving (it is read again to see it
///   stop), or a view no [PlatformViewMark] marks, or a glass or view
///   carried by a [FollowerLayer] (which moves with its leader without
///   a paint of its own) — then every frame is read, as before.
abstract final class GlassUnderlay {
  static final Set<_RenderGlassWatch> _watches = {};
  static bool _hooked = false;

  /// Something may have moved since the layers were last read.
  static bool _stirred = true;

  /// The last reading asked for the next frame to be read whatever: a view
  /// moving, unmarked, or following a leader.
  static bool _again = false;

  /// Where each view stood after the last reading, by its id, and how far
  /// it had moved since the one before.
  static Map<int, Rect> _views = const {};
  static Map<int, Offset> _moves = const {};

  static int _reads = 0;

  /// How many times the frame's layers have been read: what the frame-cost
  /// tests count.
  @visibleForTesting
  static int get debugReads => _reads;

  static void _stir() => _stirred = true;

  static void _watch(_RenderGlassWatch box) {
    // What was read while no glass was watched is no word on the next
    // frame.
    if (_watches.isEmpty) {
      _views = const {};
      _moves = const {};
    }
    _watches.add(box);
    _stirred = true;
    if (_hooked) return;
    _hooked = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _read());
  }

  static void _unwatch(_RenderGlassWatch box) {
    _watches.remove(box);
    _stirred = true;
  }

  /// Whether a glass now at [onScreen] (and at [before] a frame ago) is
  /// about to stand over a view, by where the views stood after the last
  /// frame and how they were moving — of them, only [under], the views
  /// drawn before the glass then, where the glass has been drawn before.
  static bool _ahead(Rect onScreen, Rect? before, Set<int>? under) {
    if (_views.isEmpty) return false;
    final glass = _reach(onScreen, before);
    for (final MapEntry(key: id, value: view) in _views.entries) {
      if (under != null && !under.contains(id)) continue;
      if (_reach(
        view,
        view.shift(-(_moves[id] ?? Offset.zero)),
      ).overlaps(glass)) {
        return true;
      }
    }
    return false;
  }

  /// [now], and as far again as it came from [before]: where a thing
  /// moving may stand by the next frame.
  static Rect _reach(Rect now, Rect? before) {
    if (before == null) return now;
    final step = now.center - before.center;
    return now.expandToInclude(now.shift(step));
  }

  static void _read() {
    if (_watches.isEmpty) {
      _views = const {};
      _moves = const {};
      _again = false;
      return;
    }
    if (!_stirred && !_again) return;
    _stirred = false;
    _reads++;
    // Any watched glass leads to the root of the frame's layers.
    ContainerLayer? root;
    for (final box in _watches) {
      Layer? up = box.mark;
      while (up?.parent != null) {
        up = up!.parent;
      }
      if (up is ContainerLayer && up.attached) {
        root = up;
        break;
      }
    }
    final walk = _Walk();
    if (root != null) {
      // In points, as the boxes are: the root's own transform is the
      // screen's pixel ratio.
      for (
        var child = root.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk.visit(child, Matrix4.identity(), followed: false);
      }
    }
    final moves = <int, Offset>{};
    for (final MapEntry(key: id, value: view) in walk.views.entries) {
      final was = _views[id];
      if (was != null && view.center != was.center) {
        moves[id] = view.center - was.center;
      }
    }
    _views = walk.views;
    _moves = moves;
    _again = moves.isNotEmpty || walk.unmarked || walk.followed;
    for (final box in _watches) {
      _carried(box);
    }
  }

  /// A refracting glass that stands elsewhere on the screen than when the
  /// layers were last read asks for a frame more: the renderer's matte is
  /// a frame behind (carried without a paint, [_GlassWatch]).
  static void _carried(_RenderGlassWatch box) {
    if (!box.attached || !box.liquid) {
      box.lastTransform = null;
      return;
    }
    final now = box.getTransformTo(null);
    final last = box.lastTransform;
    box.lastTransform = now;
    if (last == null || MatrixUtils.matrixEquals(last, now)) return;
    SchedulerBinding.instance.scheduleFrame();
  }
}

/// One reading of the frame's layers: the views and the glass in the order
/// they were drawn, carried to the screen.
class _Walk {
  final Map<int, Rect> views = {};

  /// A view was drawn with no [PlatformViewMark] before it.
  bool unmarked = false;

  /// A glass or a view stands under a [FollowerLayer].
  bool followed = false;

  void visit(Layer layer, Matrix4 toScreen, {required bool followed}) {
    if (layer is PlatformViewLayer) {
      views[layer.viewId] = MatrixUtils.transformRect(toScreen, layer.rect);
      if (layer.previousSibling is! _ViewMarkLayer) unmarked = true;
      if (followed) this.followed = true;
      return;
    }
    if (layer is _WatchLayer) {
      final box = layer.box;
      if (box != null && box.attached) {
        if (followed) this.followed = true;
        final glass = MatrixUtils.transformRect(toScreen, layer.rect);
        final reach = GlassUnderlay._reach(glass, box.lastOnScreen);
        box.lastOnScreen = glass;
        // Only the views drawn so far: they are the ones under it.
        box.viewsBefore = views.keys.toSet();
        final under = views.entries.any(
          (view) => GlassUnderlay._reach(
            view.value,
            GlassUnderlay._views[view.key],
          ).overlaps(reach),
        );
        box.tell(under);
        if (!under) box.foundClear();
      }
      return;
    }
    if (layer is! ContainerLayer) return;
    final under = followed || layer is FollowerLayer;
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      final carried = toScreen.clone();
      layer.applyTransform(child, carried);
      visit(child, carried, followed: under);
    }
  }
}
