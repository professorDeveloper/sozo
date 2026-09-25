import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_parsing/path_parsing.dart';

/// The mark, parsed once, measured once, and sampled once.
///
/// Three things live here that a painter must not do per frame.
///
/// The **parse** — an SVG path walk over a bundle string. It was inside
/// `SozoSignature`, which is the only thing that needed it; the splash needs
/// the same path, and two copies of a parse is two copies of a bug.
///
/// The **measure** — [ui.Path.computeMetrics] is the expensive half of
/// trimming a path to a pen position. The path is parsed once and never
/// mutated, so the answer is the same on every frame for the life of the
/// process.
///
/// The **samples** — [ui.PathMetric.getTangentForOffset] walks the contour on
/// every call. A mark that has to bend needs the answer for a few hundred
/// places at once, sixty times a second, which is exactly the work that turns
/// a 16ms budget into a dropped frame on a cold start. Asked once, the answers
/// sit in flat [Float32List]s and a frame becomes arithmetic over memory.
class SozoMarkGeometry {
  const SozoMarkGeometry._({
    required this.body,
    required this.spine,
    required this.spineMetric,
    required this.spineLength,
    required this.outlineX,
    required this.outlineY,
    required this.normalX,
    required this.normalY,
    required this.spineX,
    required this.spineY,
    required this.bounds,
    required this.edge,
    required this.edgeTop,
    required this.edgeBottom,
    required this.strokes,
  });

  /// The asset this is read from — the shipped mark re-cut into named parts.
  static const String asset = 'assets/brand/sozo_mark_animated.svg';

  /// How many places around the outline are sampled.
  ///
  /// The outline is 1472 units long in a 512 box, so 320 samples is one every
  /// 4.6 units — finer than a phone pixel at any size this is drawn, and small
  /// enough that a whole frame's worth of displaced points is five kilobytes
  /// that never moves.
  static const int outlineSamples = 320;

  /// And along the spine, which is shorter and only ever carries a pen or a
  /// highlight rather than a deformation.
  static const int spineSamples = 160;

  /// The silhouette, filled even-odd as the asset asks.
  final ui.Path body;

  /// The open stroke down the middle of the ribbon. Never filled.
  final ui.Path spine;

  /// [spine] measured, for a pen position.
  final ui.PathMetric spineMetric;
  final double spineLength;

  /// Points around [body]'s outline, evenly spaced by arc length, and the unit
  /// normal at each one pointing OUT of the fill.
  ///
  /// Which side is out depends on the asset's winding, which is a fact about
  /// the file rather than something a painter should have to know — so it is
  /// resolved once, here, by testing a single normal against the fill.
  final Float32List outlineX;
  final Float32List outlineY;
  final Float32List normalX;
  final Float32List normalY;

  /// Points along [spine], evenly spaced by arc length.
  final Float32List spineX;
  final Float32List spineY;

  /// [body]'s bounds. The radius a flood has to travel to cover the mark is
  /// derived from this rather than guessed at as a fraction of the viewBox —
  /// the mark does not fill its box, and a guess leaves a hole in the middle
  /// or finishes early at the edges.
  final ui.Rect bounds;

  /// [body]'s silhouette, measured, for drawing the letter as a line.
  final ui.PathMetric edge;

  /// Where on [edge] the middles of the two terminals are: the top cut, where
  /// both sides of the letter start from, and the bottom one, where they meet.
  final double edgeTop;
  final double edgeBottom;

  /// The dragon inside the letter as line drawing, in the order it is drawn.
  /// Empty where the lines did not load; the letter's own edge is still there.
  final List<SozoStroke> strokes;

  /// The dragon's lines, traced from the artwork by
  /// `tool/brand_dragon_lines.py`.
  static const String linesAsset = 'assets/brand/sozo_logo_lines.json';

  static SozoMarkGeometry? _loaded;
  static Future<void>? _loading;
  static ui.Image? _art;

  /// The logo's own artwork: the dragon relief inside the letter, the peach
  /// ground, the small "Sozo" in the top arm.
  ///
  /// Registered to the same 512 box as [body], at twice the resolution, so a
  /// shader that samples it through any path in that box lands on the right
  /// piece of the picture. It was aligned by maximising the overlap between
  /// the artwork's letter and [body] rather than by eye — 0.96 intersection
  /// over union, the rest being the artwork's own bevel and anti-aliasing.
  ///
  /// This is the logo. [body] is only its outline, and a splash that filled
  /// the outline with a flat colour was drawing the one part of the logo that
  /// is not the logo.
  static ui.Image? get art => _art;

  static const String artAsset = 'assets/brand/sozo_logo_art.png';

  static ui.Image? _foot;
  static ui.Image? _footGround;

  /// The dragon's raised foot — the three toes in the right-hand bend — cut
  /// out of [art] by `tool/brand_dragon_foot.py`, so the splash can move it.
  ///
  /// Only the foot, over nothing, and only the [footBox] patch of the box:
  /// it is drawn on its own transform, and a full-size copy would be four
  /// megabytes of transparency. Matted against [footGround], so the two
  /// together, with the foot at rest, are [art] to within a value or two.
  static ui.Image? get foot => _foot;

  /// [art] with the foot taken out and the ground carried across where it
  /// was: what the foot uncovers when it lifts. Full size and registered like
  /// [art], so it can stand in for it through the same shader and the letter's
  /// anti-aliased edge is drawn once, not twice.
  static ui.Image? get footGround => _footGround;

  static const String footAsset = 'assets/brand/sozo_logo_foot.png';
  static const String footGroundAsset =
      'assets/brand/sozo_logo_foot_ground.png';

  /// Where [foot] sits in the 512 box, and the point it turns about: the back
  /// of the ankle, where the leg leaves the letter's inner edge. Mirrored from
  /// the tool that cut it — the foot's cut at the ankle is a ray from exactly
  /// this point and an arc centred on it, and about anywhere else the joint
  /// opens as it turns.
  static const ui.Rect footBox = ui.Rect.fromLTRB(328, 192, 408, 304);
  static const ui.Offset footPivot = ui.Offset(347, 256);

  /// The geometry, once it has been read. Null before that.
  ///
  /// A getter rather than a future at the call site: a painter runs on a frame
  /// and cannot await anything, so the widget above it asks for the value and
  /// draws the flat mark until there is one.
  static SozoMarkGeometry? get value => _loaded;

  /// Reads and measures the mark before anything needs to draw it.
  ///
  /// Safe to call repeatedly; the work happens once. Called before `runApp` so
  /// the splash — the first thing drawn in the process — is not the one launch
  /// in every process that falls back to a flat logo.
  static Future<void> precache() => _loading ??= _read();

  static Future<void> _read() async {
    // Separately guarded: an artwork that will not decode costs the splash its
    // texture, not its geometry. It falls back to a flat letter, which is a
    // worse splash and still a splash.
    try {
      _art = await _image(artAsset);
    } catch (_) {
      _art = null;
    }
    // A pair or nothing: a foot with no ground under it leaves a copy of
    // itself behind when it lifts, and the ground with no foot is the logo
    // with a hole in it. Without them the logo is simply still.
    try {
      final foot = await _image(footAsset);
      final ground = await _image(footGroundAsset);
      _foot = foot;
      _footGround = ground;
    } catch (_) {
      _foot = null;
      _footGround = null;
    }
    try {
      final svg = await rootBundle.loadString(asset);
      final body = _pathNamed(svg, 'body');
      final spine = _pathNamed(svg, 'spine');
      if (body == null || spine == null) return;
      body.fillType = ui.PathFillType.evenOdd;

      final strokes = await _strokes();

      final outline = body.computeMetrics().toList();
      if (outline.isEmpty) return;
      // The longest contour is the silhouette. A traced mark can carry a stray
      // sliver, and sampling that instead would bend a speck while the letter
      // sat still.
      outline.sort((a, b) => b.length.compareTo(a.length));
      final edge = outline.first;

      final ox = Float32List(outlineSamples);
      final oy = Float32List(outlineSamples);
      final nx = Float32List(outlineSamples);
      final ny = Float32List(outlineSamples);
      for (var i = 0; i < outlineSamples; i++) {
        final t = edge.getTangentForOffset(edge.length * i / outlineSamples);
        if (t == null) continue;
        ox[i] = t.position.dx;
        oy[i] = t.position.dy;
        // The normal is the tangent turned a quarter turn. Which quarter is
        // decided below, for the whole table at once.
        nx[i] = -t.vector.dy;
        ny[i] = t.vector.dx;
      }

      // Out, not in. Tested once with the first usable sample: step a little
      // way along the normal and ask the path whether that is still inside.
      // Per sample this would be 320 `contains` calls per load AND would give
      // inconsistent answers at the terminals, where a short step crosses the
      // opposite edge.
      var probe = 0;
      while (probe < outlineSamples && nx[probe] == 0 && ny[probe] == 0) {
        probe++;
      }
      if (probe < outlineSamples) {
        final out = ui.Offset(
          ox[probe] + nx[probe] * 6,
          oy[probe] + ny[probe] * 6,
        );
        if (body.contains(out)) {
          for (var i = 0; i < outlineSamples; i++) {
            nx[i] = -nx[i];
            ny[i] = -ny[i];
          }
        }
      }

      final spineMetrics = spine.computeMetrics().toList();
      if (spineMetrics.isEmpty) return;
      final track = spineMetrics.first;
      final sx = Float32List(spineSamples);
      final sy = Float32List(spineSamples);
      for (var i = 0; i < spineSamples; i++) {
        final t = track.getTangentForOffset(
          track.length * i / (spineSamples - 1),
        );
        if (t == null) continue;
        sx[i] = t.position.dx;
        sy[i] = t.position.dy;
      }

      _loaded = SozoMarkGeometry._(
        body: body,
        spine: spine,
        spineMetric: track,
        spineLength: track.length,
        outlineX: ox,
        outlineY: oy,
        normalX: nx,
        normalY: ny,
        spineX: sx,
        spineY: sy,
        bounds: body.getBounds(),
        edge: edge,
        edgeTop: _nearest(edge, sx[0], sy[0]),
        edgeBottom: _nearest(edge, sx[spineSamples - 1], sy[spineSamples - 1]),
        strokes: strokes,
      );
    } catch (_) {
      // A mark that will not parse is not worth failing a launch over: every
      // caller falls back to drawing the asset flat, which is the same shape
      // without the motion. Left null so a later attempt can still succeed.
      _loading = null;
    }
  }

  static Future<ui.Image> _image(String asset) async {
    final bytes = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  /// Where on [metric] is nearest to ([x], [y]). Once, at load: a walk of the
  /// contour at a step finer than a pixel at any size the mark is drawn.
  static double _nearest(ui.PathMetric metric, double x, double y) {
    var best = 0.0;
    var bestD = double.infinity;
    for (var at = 0.0; at <= metric.length; at += 1) {
      final p = metric.getTangentForOffset(at)?.position;
      if (p == null) continue;
      final d = (p.dx - x) * (p.dx - x) + (p.dy - y) * (p.dy - y);
      if (d < bestD) {
        bestD = d;
        best = at;
      }
    }
    return best;
  }

  static Future<List<SozoStroke>> _strokes() async {
    // Guarded on its own: without the dragon's lines the letter is still
    // drawn, and then painted in.
    try {
      final json = jsonDecode(await rootBundle.loadString(linesAsset)) as Map;
      return [
        for (final s in json['strokes'] as List)
          SozoStroke._fromPoints(
            (s['points'] as List).cast<num>(),
            (s['along'] as num).toDouble(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// One `<path id="...">` out of the asset, as a [ui.Path].
  static ui.Path? _pathNamed(String svg, String id) {
    final m = RegExp(
      'id="$id"[^>]*?\\sd="([^"]+)"',
      dotAll: true,
    ).firstMatch(svg);
    if (m == null) return null;
    final proxy = _PathProxy();
    writeSvgPathDataToPath(m.group(1)!, proxy);
    return proxy.path;
  }
}

class _PathProxy extends PathProxy {
  final ui.Path path = ui.Path();

  @override
  void close() => path.close();

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

/// One line of the dragon's drawing: a contour where it meets the ground.
class SozoStroke {
  SozoStroke._(this.metric, this.along);

  factory SozoStroke._fromPoints(List<num> points, double along) {
    final path = ui.Path()..moveTo(points[0].toDouble(), points[1].toDouble());
    for (var i = 2; i + 1 < points.length; i += 2) {
      path.lineTo(points[i].toDouble(), points[i + 1].toDouble());
    }
    return SozoStroke._(path.computeMetrics().first, along);
  }

  /// The line, measured once, for drawing it a length at a time.
  final ui.PathMetric metric;

  /// Where it sits along the letter's spine, 0 at the top terminal and 1 at
  /// the bottom: the order the dragon is drawn in is the order the letter is
  /// written in.
  final double along;
}
