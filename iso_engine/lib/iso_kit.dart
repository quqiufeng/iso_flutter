// Dart 移植：anatomy/kit/iso-kit.mjs（仅移植天猫精灵用到的部分）
// 原项目：https://github.com/wheresryan22/anatomy (MIT)
import 'dart:math' as math;

const double AZIMUTH = 45;
const double ELEVATION = 30;
const int SHADES = 4;
const double _RAD = math.pi / 180;
final double _UNIT = math.sqrt(1.6);

typedef V3 = List<double>;
typedef P2 = List<double>;

class Camera {
  Camera(this.sinA, this.cosA, this.sinE, this.cosE, this.k);
  final double sinA, cosA, sinE, cosE, k;
}

class Proj {
  Proj({required this.origin, required this.scale, this.azimuth = AZIMUTH, this.elevation = ELEVATION});
  final P2 origin;
  final double scale, azimuth, elevation;
}

Camera cameraOf(Proj p) {
  final a = p.azimuth * _RAD, e = p.elevation * _RAD;
  return Camera(math.sin(a), math.cos(a), math.sin(e), math.cos(e), p.scale * _UNIT);
}

P2 iso(V3 v, Proj p) {
  final c = cameraOf(p);
  return [
    p.origin[0] + (v[0] * c.sinA - v[1] * c.cosA) * c.k,
    p.origin[1] + ((v[0] * c.cosA + v[1] * c.sinA) * c.sinE - v[2] * c.cosE) * c.k,
  ];
}

P2 towardViewer(Proj p) {
  final c = cameraOf(p);
  return [c.cosA, c.sinA];
}

double depthOf(V3 v, Proj p) {
  final c = cameraOf(p);
  return (v[0] * c.cosA + v[1] * c.sinA) * c.cosE + v[2] * c.sinE;
}

String _tenth(double value) {
  var r = (value * 10).roundToDouble() / 10;
  if (r == 0) r = 0;
  var s = r.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s == '-0' ? '0' : s;
}

String pathOf(List<P2> points, [bool closed = false]) {
  if (points.isEmpty) return '';
  final b = StringBuffer();
  for (var i = 0; i < points.length; i++) {
    b.write(i == 0 ? 'M' : 'L');
    b.write('${_tenth(points[i][0])} ${_tenth(points[i][1])}');
  }
  if (closed) b.write('Z');
  return b.toString();
}

String joinPaths(List<String> paths) => paths.where((p) => p.isNotEmpty).join('');

List<P2> roundedPlan(List<double> plan, [int steps = 8]) {
  final x = plan[0], y = plan[1], w = plan[2], d = plan[3], r0 = plan[4];
  final radius = math.max(0, math.min(r0, math.min(w / 2, d / 2)));
  final corners = [
    [x + w - radius, y + radius, -90.0],
    [x + w - radius, y + d - radius, 0.0],
    [x + radius, y + d - radius, 90.0],
    [x + radius, y + radius, 180.0],
  ];
  final out = <P2>[];
  for (final corner in corners) {
    final cx = corner[0], cy = corner[1], start = corner[2];
    final count = radius > 0 ? steps : 0;
    for (var step = 0; step <= count; step++) {
      final angle = (start + (count > 0 ? (90 * step) / count : 45)) * _RAD;
      out.add([cx + radius * math.cos(angle), cy + radius * math.sin(angle)]);
    }
  }
  return out;
}

double _signedArea(List<P2> points) {
  var area = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    area += a[0] * b[1] - b[0] * a[1];
  }
  return area / 2;
}

List<P2> oriented(List<P2> points) => _signedArea(points) < 0 ? points.reversed.toList() : points;

List<P2> convexHull(List<P2> points) {
  final sorted = [...points]..sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
  if (sorted.length < 3) return sorted;
  double cross(P2 o, P2 a, P2 b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  final lower = <P2>[];
  for (final p in sorted) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <P2>[];
  for (var i = sorted.length - 1; i >= 0; i--) {
    final p = sorted[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

List<List<int>> runsOf(List<bool> flags, bool want) {
  final count = flags.length;
  final runs = <List<int>>[];
  var start = -1;
  for (var i = 0; i < count; i++) {
    if (flags[i] != flags[(i + count - 1) % count]) {
      start = i;
      break;
    }
  }
  if (start < 0) {
    if (flags[0] == want) {
      return [List<int>.generate(count + 1, (i) => i % count)];
    }
    return [];
  }
  List<int>? run;
  for (var step = 0; step < count; step++) {
    final index = (start + step) % count;
    if (flags[index] == want) {
      run ??= [index];
      run.add((index + 1) % count);
    } else if (run != null) {
      runs.add(run);
      run = null;
    }
  }
  if (run != null) runs.add(run);
  return runs;
}

abstract class SolidPaths {
  String get fill;
  String get outline;
  String get crease;
  String get top;
  List<String> get shades;
  String? get bevel;
}

class Extrude implements SolidPaths {
  Extrude({required this.fill, required this.outline, required this.crease, required this.top, required this.shades, this.bevel});
  final String fill, outline, crease, top;
  final List<String> shades;
  final String? bevel;
}

Extrude extrude(List<P2> ring, double z, double height, Proj projection, {bool convex = true, double bevel = 0}) {
  final count = ring.length;
  final counter = _signedArea(ring) > 0;
  final v = towardViewer(projection);
  final c = cameraOf(projection);
  final normals = <P2>[];
  for (var i = 0; i < count; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % count];
    final dx = b[0] - a[0], dy = b[1] - a[1];
    final length = math.sqrt(dx * dx + dy * dy) == 0 ? 1.0 : math.sqrt(dx * dx + dy * dy);
    normals.add(counter ? [dy / length, -dx / length] : [-dy / length, dx / length]);
  }
  final facing = normals.map((n) => n[0] * v[0] + n[1] * v[1] > 1e-9).toList();
  final top = ring.map((p) => iso([p[0], p[1], z + height], projection)).toList();
  final bottom = ring.map((p) => iso([p[0], p[1], z], projection)).toList();
  final outline = <String>[];
  final crease = <String>[];
  for (final run in runsOf(facing, false)) {
    outline.add(pathOf(run.map((i) => top[i]).toList()));
  }
  for (final run in runsOf(facing, true)) {
    crease.add(pathOf(run.map((i) => top[i]).toList()));
    if (height > 0) outline.add(pathOf(run.map((i) => bottom[i]).toList()));
  }
  if (height > 0) {
    for (var i = 0; i < count; i++) {
      if (facing[(i + count - 1) % count] != facing[i]) {
        outline.add(pathOf([top[i], bottom[i]]));
      }
    }
  }
  String fill;
  if (convex) {
    fill = pathOf(convexHull([...top, ...bottom]), true);
  } else {
    final parts = [pathOf(oriented(top), true), pathOf(oriented(bottom), true)];
    for (var i = 0; i < count; i++) {
      if (!facing[i]) continue;
      final next = (i + 1) % count;
      parts.add(pathOf(oriented([top[i], top[next], bottom[next], bottom[i]]), true));
    }
    fill = parts.join('');
  }
  final buckets = List.generate(SHADES, (_) => <String>[]);
  if (height > 0) {
    final lx = -c.sinA, ly = c.cosA;
    for (var i = 0; i < count; i++) {
      if (!facing[i]) continue;
      final n = normals[i];
      final lit = (n[0] * lx + n[1] * ly + 1) / 2;
      final shade = math.min(SHADES - 1, math.max(0, (lit * SHADES).floor()));
      final next = (i + 1) % count;
      buckets[shade].add(pathOf(oriented([top[i], top[next], bottom[next], bottom[i]]), true));
    }
  }
  String? bevelPath;
  if (bevel > 0) {
    final inset = <P2>[];
    for (var i = 0; i < count; i++) {
      final a = normals[(i + count - 1) % count];
      final b = normals[i];
      final mx = a[0] + b[0], my = a[1] + b[1];
      final length = math.sqrt(mx * mx + my * my) == 0 ? 1.0 : math.sqrt(mx * mx + my * my);
      inset.add([ring[i][0] - (mx / length) * bevel, ring[i][1] - (my / length) * bevel]);
    }
    final insetTop = inset.map((p) => iso([p[0], p[1], z + height], projection)).toList();
    bevelPath = runsOf(facing, true)
        .map((run) => pathOf([top[run[0]], ...run.sublist(1, run.length - 1).map((i) => insetTop[i]), top[run[run.length - 1]]]))
        .join('');
  }
  return Extrude(
    fill: fill,
    outline: outline.join(''),
    crease: crease.join(''),
    top: pathOf(oriented(top), true),
    shades: buckets.map((p) => p.join('')).toList(),
    bevel: bevelPath,
  );
}

List<P2> ringOf(List<double> plan, [int steps = 8]) => roundedPlan(plan, steps);

Extrude slabOf(List<double> plan, double z, double height, Proj projection, [int steps = 8, double bevel = 0]) =>
    extrude(ringOf(plan, steps), z, height, projection, convex: true, bevel: bevel);

List<P2> circleRing(double cx, double cy, double radius, [int steps = 40]) {
  return List.generate(steps, (s) {
    final angle = (s / steps) * math.pi * 2;
    return [cx + radius * math.cos(angle), cy + radius * math.sin(angle)];
  });
}

Extrude cylinder(double cx, double cy, double radius, double z, double height, Proj projection,
        [int steps = 32, double bevel = 0]) =>
    extrude(circleRing(cx, cy, radius, steps), z, height, projection, convex: true, bevel: bevel);

List<double> insetPlan(List<double> plan, double by) =>
    [plan[0] + by, plan[1] + by, plan[2] - by * 2, plan[3] - by * 2, math.max(0, plan[4] - by)];

String onTop(List<P2> points, double z, Proj projection, [bool closed = false]) =>
    pathOf(points.map((p) => iso([p[0], p[1], z], projection)).toList(), closed);

String planOutline(List<double> plan, double z, Proj projection, [int steps = 8, bool closed = true]) =>
    onTop(ringOf(plan, steps), z, projection, closed);

String lineOnTop(P2 from, P2 to, double z, Proj projection) => onTop([from, to], z, projection);

String segment(V3 from, V3 to, Proj projection) => pathOf([iso(from, projection), iso(to, projection)]);

String rise(P2 at, double from, double to, Proj projection) =>
    segment([at[0], at[1], from], [at[0], at[1], to], projection);

String ring(double cx, double cy, double radius, double z, Proj projection, [int steps = 40]) =>
    onTop(circleRing(cx, cy, radius, steps), z, projection, true);

List<P2> pointsAt(List<V3> points, Proj projection) => points.map((p) => iso(p, projection)).toList();

List<P2> dotGrid(double x, double y, int columns, int rows, double gap, double z, Proj projection) {
  final dots = <P2>[];
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      dots.add(iso([x + column * gap, y + row * gap, z], projection));
    }
  }
  return dots;
}

List<P2> corners(List<double> box, [double inset = 0]) => [
      [box[0] + inset, box[1] + inset],
      [box[0] + box[2] - inset, box[1] + inset],
      [box[0] + inset, box[1] + box[3] - inset],
      [box[0] + box[2] - inset, box[1] + box[3] - inset],
    ];

List<V3> boxCorners(List<double> box, double z0, double z1) {
  final out = <V3>[];
  for (final px in [box[0], box[0] + box[2]]) {
    for (final py in [box[1], box[1] + box[3]]) {
      for (final z in [z0, z1]) {
        out.add([px, py, z]);
      }
    }
  }
  return out;
}

String knurl(double cx, double cy, double radius, double z0, double z1, int count, Proj projection, [double inset = 0.4]) {
  final v = towardViewer(projection);
  final lines = <String>[];
  for (var i = 0; i < count; i++) {
    final angle = (i / count) * math.pi * 2;
    final nx = math.cos(angle), ny = math.sin(angle);
    if (nx * v[0] + ny * v[1] < 0.15) continue;
    lines.add(segment([cx + radius * nx, cy + radius * ny, z0 + inset], [cx + radius * nx, cy + radius * ny, z1 - inset], projection));
  }
  return lines.join('');
}

String sideArc(double cx, double cy, double radius, double z, Proj projection, [int steps = 24]) {
  final v = towardViewer(projection);
  final facing = math.atan2(v[1], v[0]);
  final points = <P2>[];
  for (var step = 0; step <= steps; step++) {
    final angle = facing - math.pi / 2 + (step / steps) * math.pi;
    points.add(iso([cx + radius * math.cos(angle), cy + radius * math.sin(angle), z], projection));
  }
  return pathOf(points);
}

String sideSeam(List<double> plan, double z, Proj projection, [int steps = 8]) {
  final r = ringOf(plan, steps);
  final count = r.length;
  final counter = _signedArea(r) > 0;
  final v = towardViewer(projection);
  final facing = <bool>[];
  for (var i = 0; i < count; i++) {
    final a = r[i], b = r[(i + 1) % count];
    final dx = b[0] - a[0], dy = b[1] - a[1];
    final n = counter ? [dy, -dx] : [-dy, dx];
    facing.add(n[0] * v[0] + n[1] * v[1] > 1e-9);
  }
  return runsOf(facing, true).map((run) => pathOf(run.map((i) => iso([r[i][0], r[i][1], z], projection)).toList())).join('');
}

String haloOf(List<double> plan, double z, double height, Proj projection) => slabOf(plan, z, height, projection).fill;

Proj fitProjection(List<V3> points, double width, double height,
    {double pad = 24, double headroom = 0, double azimuth = AZIMUTH, double elevation = ELEVATION}) {
  final unit = Proj(origin: [0, 0], scale: 1, azimuth: azimuth, elevation: elevation);
  final flat = points.map((p) => iso(p, unit)).toList();
  final xs = flat.map((p) => p[0]);
  final ys = flat.map((p) => p[1]);
  final left = xs.reduce(math.min), right = xs.reduce(math.max);
  final up = ys.reduce(math.min), down = ys.reduce(math.max);
  final scale = math.min((width - pad * 2) / (right - left), (height - pad * 2 - headroom) / (down - up));
  return Proj(
    origin: [
      width / 2 - ((left + right) / 2) * scale,
      headroom + (height - headroom) / 2 - ((up + down) / 2) * scale,
    ],
    scale: scale,
    azimuth: azimuth,
    elevation: elevation,
  );
}

// ── 其余 iso-kit 几何 ──
P2 axisVector(Proj projection, V3 d) {
  final origin = iso([0, 0, 0], projection);
  final moved = iso([d[0], d[1], d[2]], projection);
  return [moved[0] - origin[0], moved[1] - origin[1]];
}

double screenRise(double height, Proj projection) {
  final c = cameraOf(projection);
  return height * c.cosE * c.k;
}

P2 translateAlong(Proj projection, V3 by) => axisVector(projection, by);

String sideRing(V3 center, double radius, String axis, Proj projection, [int steps = 20]) {
  final px = center[0], py = center[1], pz = center[2];
  final points = <P2>[];
  for (var step = 0; step < steps; step++) {
    final angle = (step / steps) * math.pi * 2;
    final u = radius * math.cos(angle);
    final v = radius * math.sin(angle);
    points.add(iso(axis == 'x' ? [px, py + u, pz + v] : [px + u, py, pz + v], projection));
  }
  return pathOf(points, true);
}

class Coil {
  Coil(this.back, this.front);
  final String back, front;
}

Coil coil(double from, double to, P2 center, double radius, double turns, String axis, Proj projection, [int perTurn = 16]) {
  final count = math.max(1, (turns * perTurn).round());
  final back = <String>[];
  final front = <String>[];
  var run = <P2>[];
  bool? near;
  for (var index = 0; index <= count; index++) {
    final share = index / count;
    final angle = share * turns * math.pi * 2;
    final u = radius * math.cos(angle);
    final v = radius * math.sin(angle);
    final along = from + (to - from) * share;
    final point = axis == 'x' ? [along, center[0] + u, center[1] + v] : [center[0] + u, along, center[1] + v];
    final normal = axis == 'x' ? [0.0, math.cos(angle), math.sin(angle)] : [math.cos(angle), 0.0, math.sin(angle)];
    final facing = depthOf(normal, projection) > 0;
    final flat = iso(point, projection);
    near ??= facing;
    if (facing != near) {
      if (run.isNotEmpty) (near ? front : back).add(pathOf(run));
      run = [flat];
      near = facing;
      continue;
    }
    run.add(flat);
  }
  if (run.length > 1) (near! ? front : back).add(pathOf(run));
  return Coil(back.join(''), front.join(''));
}

class Ticks {
  Ticks(this.minor, this.major);
  final String minor, major;
}

Ticks topTicks(double from, double to, double step, int every, double edge, double z, List<double> lengths, Proj projection,
    [String axis = 'x']) {
  final minor = <String>[];
  final major = <String>[];
  final first = (from / step).ceil() * step;
  var index = (first / step).round();
  for (var at = first; at <= to + 1e-9; at += step, index++) {
    final big = index % every == 0;
    final length = big ? lengths[1] : lengths[0];
    final a = axis == 'x' ? [at, edge] : [edge, at];
    final b = axis == 'x' ? [at, edge + length] : [edge + length, at];
    (big ? major : minor).add(lineOnTop(a, b, z, projection));
  }
  return Ticks(minor.join(''), major.join(''));
}

Ticks sideTicks(double from, double to, double step, int every, double face, double top, List<double> lengths, Proj projection,
    [String axis = 'x']) {
  final minor = <String>[];
  final major = <String>[];
  final first = (from / step).ceil() * step;
  var index = (first / step).round();
  for (var at = first; at <= to + 1e-9; at += step, index++) {
    final big = index % every == 0;
    final length = big ? lengths[1] : lengths[0];
    final a = axis == 'x' ? [at, face, top] : [face, at, top];
    final b = axis == 'x' ? [at, face, top - length] : [face, at, top - length];
    (big ? major : minor).add(segment(a, b, projection));
  }
  return Ticks(minor.join(''), major.join(''));
}

Ticks radialTicks(double cx, double cy, double radius, int count, int every, double z, List<double> lengths, Proj projection,
    [double from = 0, double span = math.pi * 2]) {
  final minor = <String>[];
  final major = <String>[];
  final closed = (span - math.pi * 2).abs() < 1e-9;
  final steps = closed ? count : count + 1;
  for (var index = 0; index < steps; index++) {
    final angle = from + (index / count) * span;
    final big = index % every == 0;
    final inner = radius - (big ? lengths[1] : lengths[0]);
    final sx = math.sin(angle);
    final sy = -math.cos(angle);
    (big ? major : minor)
        .add(lineOnTop([cx + sx * inner, cy + sy * inner], [cx + sx * radius, cy + sy * radius], z, projection));
  }
  return Ticks(minor.join(''), major.join(''));
}
