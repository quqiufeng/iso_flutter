// Dart 移植：anatomy/kit/tube.mjs（沿 3D 路径扫掠的管）——核心几何（跳过的部分见文件末 TODO）
// 原项目：https://github.com/wheresryan22/anatomy (MIT)
import 'dart:math' as math;

import 'iso_kit.dart';
import 'iso_lathe.dart';

final List<double> _LIGHT = () {
  final length = math.sqrt(0.55 * 0.55 + 0.835 * 0.835);
  return [-0.55 / length, -0.835 / length];
}();

String _poly(List<P2> points, [bool closed = true]) => pathOf(points, closed);

double _area(List<P2> points) {
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final nx = points[(i + 1) % points.length][0];
    final ny = points[(i + 1) % points.length][1];
    sum += points[i][0] * ny - nx * points[i][1];
  }
  return sum;
}

class TFrame {
  TFrame(this.p, this.nx, this.ny, this.half);
  final P2 p;
  final double nx, ny, half;
}

class Sides {
  Sides(this.left, this.right, this.shineA, this.shineB, this.shadeA, this.shadeB);
  final List<P2> left, right, shineA, shineB, shadeA, shadeB;
}

Sides _sideOf(List<TFrame> frames) {
  final out = Sides([], [], [], [], [], []);
  for (final f in frames) {
    out.left.add([f.p[0] + f.nx * f.half, f.p[1] + f.ny * f.half]);
    out.right.add([f.p[0] - f.nx * f.half, f.p[1] - f.ny * f.half]);
    final toward = f.nx * _LIGHT[0] + f.ny * _LIGHT[1];
    final shineAt = f.half * 0.44 * toward;
    final shineHalf = f.half * 0.24;
    out.shineA.add([f.p[0] + f.nx * (shineAt + shineHalf), f.p[1] + f.ny * (shineAt + shineHalf)]);
    out.shineB.add([f.p[0] + f.nx * (shineAt - shineHalf), f.p[1] + f.ny * (shineAt - shineHalf)]);
    final shadeAt = -f.half * 0.62 * toward;
    final shadeHalf = f.half * 0.2;
    out.shadeA.add([f.p[0] + f.nx * (shadeAt + shadeHalf), f.p[1] + f.ny * (shadeAt + shadeHalf)]);
    out.shadeB.add([f.p[0] + f.nx * (shadeAt - shadeHalf), f.p[1] + f.ny * (shadeAt - shadeHalf)]);
  }
  return out;
}

class Cap {
  Cap(this.ring, this.arc, this.inner);
  final List<P2> ring, arc, inner;
}

Cap _capOf(V3 centre, V3 tangent, double radius, P2 inward, Proj p) {
  final v = viewOf(p);
  var n1 = cross3(tangent, v);
  if (len3(n1) < 1e-6) n1 = frameAlong([0, 0, 0], tangent).u;
  n1 = unit3(n1);
  final n2 = unit3(cross3(tangent, n1));
  const steps = 28;
  final ring = List.generate(steps, (index) {
    final angle = (index / steps) * math.pi * 2;
    return iso(add3(centre, add3(mul3(n1, radius * math.cos(angle)), mul3(n2, radius * math.sin(angle)))), p);
  });
  final c = iso(centre, p);
  final probe = iso(add3(centre, n2), p);
  final along = (probe[0] - c[0]) * inward[0] + (probe[1] - c[1]) * inward[1];
  final from = along > 0 ? steps ~/ 2 : 0;
  List<P2> half(int start) => List.generate(steps ~/ 2 + 1, (index) => ring[(start + index) % steps]);
  return Cap(ring, half(from), half((from + steps ~/ 2) % steps));
}

List<P2> _stripeEnd(List<P2> half, P2 centre, double nx, double ny, double from, double to) {
  double offset(P2 pt) => (pt[0] - centre[0]) * nx + (pt[1] - centre[1]) * ny;
  final values = half.map(offset).toList();
  final lo = math.min(from, to);
  final hi = math.max(from, to);
  final points = <P2>[];
  for (var k = 0; k < half.length; k++) {
    if (values[k] >= lo && values[k] <= hi) points.add(half[k]);
    if (k < half.length - 1) {
      for (final level in [lo, hi]) {
        if ((values[k] - level) * (values[k + 1] - level) < 0) {
          final t = (level - values[k]) / (values[k + 1] - values[k] == 0 ? 1e-9 : values[k + 1] - values[k]);
          points.add([half[k][0] + (half[k + 1][0] - half[k][0]) * t, half[k][1] + (half[k + 1][1] - half[k][1]) * t]);
        }
      }
    }
  }
  final pairs = <List<double>>[];
  for (final pt in points) {
    pairs.add([pt[0], pt[1], offset(pt)]);
  }
  pairs.sort((x, y) => from > to ? y[2].compareTo(x[2]) : x[2].compareTo(y[2]));
  return pairs.map((e) => [e[0], e[1]]).toList();
}

class Span {
  Span(this.from, this.to, this.open0, this.open1, this.gap0, this.gap1);
  double from, to;
  bool open0, open1, gap0, gap1;
}

List<Span> _spansOf(double total, List<List<double>> gaps, List<double> breaks, double maxLength, bool closed) {
  final cuts = gaps
      .map((ab) => [math.max(0.0, math.min(ab[0], ab[1])), math.min(total, math.max(ab[0], ab[1]))])
      .where((ab) => ab[1] - ab[0] > 1e-6)
      .toList()
    ..sort((x, y) => x[0].compareTo(y[0]));
  final runs = <List<double>>[];
  var at = 0.0;
  for (final ab in cuts) {
    if (ab[0] > at + 1e-6) runs.add([at, ab[0], at > 0 ? 1 : 0, 1]);
    at = math.max(at, ab[1]);
  }
  if (total > at + 1e-6) {
    runs.add([at, total, at > 0 ? 1 : 0, (cuts.isNotEmpty && cuts.last[1] >= total - 1e-6) ? 1 : 0]);
  }
  final pieces = <Span>[];
  for (final run in runs) {
    final from0 = run[0], to0 = run[1];
    final gapStart = run[2] > 0, gapEnd = run[3] > 0;
    final stops = <double>[
      from0,
      ...breaks.where((b) => b > from0 + 1e-6 && b < to0 - 1e-6).toList()..sort(),
      to0,
    ];
    for (var index = 0; index < stops.length - 1; index++) {
      final a = stops[index], b = stops[index + 1];
      final count = math.max(1, ((b - a) / maxLength - 1e-9).ceil());
      for (var c = 0; c < count; c++) {
        pieces.add(Span(
          a + (b - a) * c / count,
          a + (b - a) * (c + 1) / count,
          !(index == 0 && c == 0),
          !(index == stops.length - 2 && c == count - 1),
          index == 0 && c == 0 && gapStart,
          index == stops.length - 2 && c == count - 1 && gapEnd,
        ));
      }
    }
  }
  if (closed && cuts.isEmpty && pieces.isNotEmpty) {
    pieces.first.open0 = true;
    pieces.last.open1 = true;
  }
  return pieces;
}

class Ring {
  Ring(this.d, this.alpha);
  final String d;
  final double alpha;
}

class _Tip {
  _Tip(this.half, this.frame);
  final List<P2> half;
  final TFrame frame;
}

class TubePiece {
  TubePiece({
    required this.rings,
    required this.ringTone,
    required this.mid,
    required this.body,
    required this.shine,
    required this.shade,
    required this.edges,
    required this.wide,
    required this.points,
    required this.radii,
    required this.ends,
    required this.from,
    required this.to,
  });
  final List<Ring> rings;
  final String ringTone, body, shine, shade, edges;
  final V3 mid;
  final bool wide;
  final List<V3> points;
  final List<double> radii;
  final List<bool> ends;
  final double from, to;
}

class _Part {
  _Part(this.points, this.flat, this.widths, this.frames);
  final List<V3> points;
  final List<P2> flat;
  final List<double> widths;
  final List<TFrame> frames;
}

List<TubePiece> tubePieces(
  List<V3> points3,
  double Function(double) radiusAt,
  Proj p, {
  double maxLength = 30,
  double spacing = 2.2,
  bool closed = false,
  List<double> breaks = const [],
  List<List<double>> gaps = const [],
  bool caps = true,
  Object stripes = 'auto',
  bool rings = false,
  double pitch = 3,
  double twist = 0,
  List<double> fade = const [0.1, 0.55],
  String ringTone = 'lo',
}) {
  final dense = resample(points3, spacing);
  final total = pathLength(dense);
  final k = scaleOf(p);
  final wide = stripes == 'auto'
      ? List.generate(33, (i) => radiusAt(i / 32)).reduce(math.max) * k > 1.3
      : stripes == true;
  const lead = 0.5;
  final out = <TubePiece>[];
  final looped = closed && gaps.isEmpty;
  double wrap(double at) => looped ? ((at % total) + total) % total : math.max(0, math.min(total, at));
  final step = math.max(0.05, math.min(spacing, total / 4) * 0.5);

  TFrame frameAt(double at, P2 pt, double width) {
    final a = iso(pointAlong(dense, wrap(at - step)), p);
    final b = iso(pointAlong(dense, wrap(at + step)), p);
    var tx = b[0] - a[0];
    var ty = b[1] - a[1];
    final length = math.sqrt(tx * tx + ty * ty);
    tx = length == 0 ? 0 : tx / length;
    ty = length == 0 ? 0 : ty / length;
    return TFrame(pt, -ty, tx, width);
  }

  _Part partOf(double start, double end) {
    var points = cut(dense, math.max(0, start), math.min(total, end));
    if (looped && start < 0) points = [...cut(dense, total + start, total), ...points.sublist(1)];
    if (looped && end > total) points = [...points, ...cut(dense, 0, end - total).sublist(1)];
    var walked = looped ? start : math.max(0.0, start);
    final along = <double>[];
    for (var index = 0; index < points.length; index++) {
      if (index > 0) walked += len3(sub3(points[index], points[index - 1]));
      along.add(walked);
    }
    final flat = points.map((pt) => iso(pt, p)).toList();
    final widths =
        along.map((at) => radiusAt(looped ? wrap(at) / total : math.min(1, math.max(0, at / total))) * k).toList();
    final frames = List.generate(flat.length, (index) => frameAt(along[index], flat[index], widths[index]));
    return _Part(points, flat, widths, frames);
  }

  for (final piece in _spansOf(total, gaps, breaks, maxLength, closed)) {
    final openStart = piece.open0 && (piece.from > 0 || looped);
    final openEnd = piece.open1 && (piece.to < total || looped);
    final body = partOf(openStart ? piece.from - lead : piece.from, openEnd ? piece.to + lead : piece.to);
    if (body.points.length < 2) continue;
    final stripe = openStart || openEnd
        ? partOf(openStart ? piece.from - 2 * lead : piece.from, openEnd ? piece.to + 2 * lead : piece.to)
        : body;
    final sides = _sideOf(body.frames);
    final bands = identical(stripe, body) ? sides : _sideOf(stripe.frames);
    var bodyPath = _poly([...sides.left, ...sides.right.reversed]);
    var edges = pathOf(sides.left) + pathOf(sides.right);
    final ends = [
      !piece.open0 && !looped && (piece.from <= 1e-6 || piece.gap0),
      !piece.open1 && !looped && (piece.to >= total - 1e-6 || piece.gap1),
    ];
    final capped = [ends[0] && (piece.gap0 || caps), ends[1] && (piece.gap1 || caps)];
    final sign = _area([...sides.left, ...sides.right.reversed]).sign;
    final tips = <_Tip?>[null, null];
    for (var side = 0; side < 2; side++) {
      if (!capped[side]) continue;
      final at = side == 1 ? body.points.length - 1 : 0;
      final other = side == 1 ? body.points.length - 2 : 1;
      final tangent = unit3(sub3(body.points[side == 1 ? at : other], body.points[side == 1 ? other : at]));
      final outward = side == 1 ? tangent : mul3(tangent, -1);
      final inward = [body.flat[other][0] - body.flat[at][0], body.flat[other][1] - body.flat[at][1]];
      final cap = _capOf(body.points[at], tangent, body.widths[at] / k, inward, p);
      final orientedRing = _area(cap.ring).sign == sign ? cap.ring : cap.ring.reversed.toList();
      bodyPath += _poly(orientedRing);
      edges += pathOf(cap.arc);
      final open = dot3(outward, viewOf(p)) > 0;
      if (open) edges += pathOf(cap.inner);
      tips[side] = _Tip(open ? cap.inner : cap.arc, body.frames[at]);
    }
    List<P2> band(List<P2> a, List<P2> b, List<double> Function(TFrame) offsets) {
      final head = tips[1] != null
          ? _stripeEnd(tips[1]!.half, tips[1]!.frame.p, tips[1]!.frame.nx, tips[1]!.frame.ny,
              offsets(tips[1]!.frame)[0], offsets(tips[1]!.frame)[1])
          : <P2>[];
      final tail = tips[0] != null
          ? _stripeEnd(tips[0]!.half, tips[0]!.frame.p, tips[0]!.frame.nx, tips[0]!.frame.ny,
              offsets(tips[0]!.frame)[1], offsets(tips[0]!.frame)[0])
          : <P2>[];
      return [...a, ...head, ...b.reversed, ...tail];
    }

    double toward(TFrame f) => f.nx * _LIGHT[0] + f.ny * _LIGHT[1];
    List<double> shineOffsets(TFrame f) =>
        [f.half * 0.44 * toward(f) + f.half * 0.24, f.half * 0.44 * toward(f) - f.half * 0.24];
    List<double> shadeOffsets(TFrame f) =>
        [-f.half * 0.62 * toward(f) + f.half * 0.2, -f.half * 0.62 * toward(f) - f.half * 0.2];

    out.add(TubePiece(
      rings: rings ? _ringsOf(dense, total, radiusAt, p, piece, pitch: pitch, twist: twist, fade: fade) : [],
      ringTone: ringTone,
      mid: pointAlong(dense, (piece.from + piece.to) / 2),
      body: bodyPath,
      shine: _poly(band(bands.shineA, bands.shineB, shineOffsets)),
      shade: _poly(band(bands.shadeA, bands.shadeB, shadeOffsets)),
      edges: edges,
      wide: wide,
      points: body.points,
      radii: body.widths.map((w) => w / k).toList(),
      ends: ends,
      from: piece.from,
      to: piece.to,
    ));
  }
  return out;
}

List<Ring> _ringsOf(List<V3> dense, double total, double Function(double) radiusAt, Proj p, Span piece,
    {double pitch = 3, double twist = 0, List<double> fade = const [0.1, 0.55], int steps = 16}) {
  final v = viewOf(p);
  final lo = piece.from, hi = piece.to;
  final margin = twist != 0 ? 0.0 : math.min(pitch * 0.35, (hi - lo) / 2);
  final from = math.max(lo, margin);
  final to = math.min(hi, margin != 0 ? hi - margin : hi);
  if (to <= from) return [];
  final out = <Ring>[];
  final hands = twist != 0 ? [1.0] : [0.0];
  final reach = twist.abs() * ([0.0, 0.5, 1.0].map(radiusAt).reduce(math.max));
  final first = ((from - reach) / pitch).ceil();
  final last = ((to + reach) / pitch).floor();
  ({P2 p, double facing, double r})? surface(double t, double theta) {
    final at = math.max(0.0, math.min(total, t));
    final c = pointAlong(dense, at);
    final tt = tangentAlong(dense, at);
    var n1 = cross3(tt, v);
    if (len3(n1) < 1e-6) return null;
    n1 = unit3(n1);
    var n2 = unit3(cross3(tt, n1));
    if (dot3(n2, v) < 0) n2 = mul3(n2, -1);
    final r = radiusAt(at / (total == 0 ? 1 : total));
    final normal = add3(mul3(n1, math.cos(theta)), mul3(n2, math.sin(theta)));
    return (p: iso(add3(c, mul3(normal, r)), p), facing: dot3(normal, v), r: r);
  }

  for (var index = first; index <= last; index++) {
    final station = index * pitch;
    for (final hand in hands) {
      final samples = <List<double>>[];
      for (var s = 0; s <= steps; s++) {
        final theta = (s / steps) * math.pi;
        final t = station +
            hand * twist * radiusAt(math.max(0, math.min(1, station / (total == 0 ? 1 : total)))) * (s / steps - 0.5);
        samples.add([t, theta]);
      }
      for (var s = 0; s < steps; s++) {
        var a = samples[s];
        var b = samples[s + 1];
        if ((a[0] < from && b[0] < from) || (a[0] > to && b[0] > to)) continue;
        List<double> clipTo(List<double> x, List<double> y, double edge) =>
            [edge, x[1] + ((y[1] - x[1]) * (edge - x[0])) / (y[0] - x[0] == 0 ? 1e-9 : y[0] - x[0])];
        if (a[0] < from) a = clipTo(a, b, from);
        if (b[0] < from) b = clipTo(b, a, from);
        if (a[0] > to) a = clipTo(a, b, to);
        if (b[0] > to) b = clipTo(b, a, to);
        final pa = surface(a[0], a[1]);
        final pb = surface(b[0], b[1]);
        if (pa == null || pb == null) continue;
        final alpha = fade.isNotEmpty ? fadeOf((pa.facing + pb.facing) / 2, fade) : 1.0;
        if (alpha <= 0.02) continue;
        out.add(Ring(pathOf([pa.p, pb.p]), alpha));
      }
    }
  }
  return out;
}

// 说明：tube.mjs **核心已移植**（tubePieces：spansOf/crossingsOf/ringsOf/capOf/stripeEnd/sideOf/runsOf）；
// 未移植的只有 ringsSvg/tubeSvg（SVG 字符串输出，本端直接 Canvas 绘制）。
