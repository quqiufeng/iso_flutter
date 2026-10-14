// Dart 移植：anatomy/kit/lathe.mjs（回转体）——核心（分面明暗 + 轮廓），跳过的部分见文件末 TODO
// 原项目：https://github.com/wheresryan22/anatomy (MIT)
import 'dart:math' as math;

import 'iso_kit.dart';

const double TAU = math.pi * 2;
const double LIGHT_UP = 1.2;
const List<double> BANDS = [0, 0.2, 0.42, 0.62];

// ── 三维向量 ──
double dot3(V3 a, V3 b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
V3 add3(V3 a, V3 b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
V3 sub3(V3 a, V3 b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
V3 mul3(V3 a, double k) => [a[0] * k, a[1] * k, a[2] * k];
double len3(V3 a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
V3 unit3(V3 a) {
  final l = len3(a);
  return l == 0 ? [0, 0, 0] : [a[0] / l, a[1] / l, a[2] / l];
}

V3 cross3(V3 a, V3 b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];
V3 lerp3(V3 a, V3 b, double t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

V3 viewOf(Proj p) {
  final c = cameraOf(p);
  return [c.cosA * c.cosE, c.sinA * c.cosE, c.sinE];
}

V3 lightOf(Proj p) {
  final c = cameraOf(p);
  return unit3([-c.sinA, c.cosA, LIGHT_UP]);
}

double scaleOf(Proj p) => cameraOf(p).k;

int bandOf(double score) {
  var tone = 0;
  while (tone < BANDS.length && score >= BANDS[tone]) {
    tone++;
  }
  return tone;
}

int toneOf(V3 normal, Proj p) => bandOf(dot3(unit3(normal), lightOf(p)));

class Frame {
  Frame(this.o, this.a, this.u, this.v);
  final V3 o, a, u, v;
}

Frame frameAlong(V3 o, V3 a) {
  final axis = unit3(a);
  final helper = axis[2].abs() > 0.9 ? [1.0, 0.0, 0.0] : [0.0, 0.0, 1.0];
  final u = unit3(cross3(helper, axis));
  final v = cross3(axis, u);
  return Frame(o, axis, u, v);
}

Frame frameOf(V3 o, V3 a, V3 u, V3 v) => Frame(o, a, u, v);

V3 pointOf(Frame f, double s, double r, double angle) {
  final c = math.cos(angle);
  final n = math.sin(angle);
  return [
    f.o[0] + f.a[0] * s + r * (c * f.u[0] + n * f.v[0]),
    f.o[1] + f.a[1] * s + r * (c * f.u[1] + n * f.v[1]),
    f.o[2] + f.a[2] * s + r * (c * f.u[2] + n * f.v[2]),
  ];
}

V3 radialOf(Frame f, double angle) {
  final c = math.cos(angle);
  final n = math.sin(angle);
  return [c * f.u[0] + n * f.v[0], c * f.u[1] + n * f.v[1], c * f.u[2] + n * f.v[2]];
}

V3 tangentOf(Frame f, double angle) {
  final c = math.cos(angle);
  final n = math.sin(angle);
  return [-n * f.u[0] + c * f.v[0], -n * f.u[1] + c * f.v[1], -n * f.u[2] + c * f.v[2]];
}

double angleToward(Frame f, V3 direction) => math.atan2(dot3(direction, f.v), dot3(direction, f.u));

// ── 凸包（带标签）/ runs / groups / steps ──
class Tagged {
  Tagged(this.p, this.ring);
  final P2 p;
  final int ring;
}

List<Tagged> hullTagged(List<Tagged> points) {
  final sorted = [...points]..sort((a, b) => a.p[0] != b.p[0] ? a.p[0].compareTo(b.p[0]) : a.p[1].compareTo(b.p[1]));
  if (sorted.length < 3) return sorted;
  double cross(Tagged o, Tagged a, Tagged b) => (a.p[0] - o.p[0]) * (b.p[1] - o.p[1]) - (a.p[1] - o.p[1]) * (b.p[0] - o.p[0]);
  final lower = <Tagged>[];
  for (final p in sorted) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 1e-9) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Tagged>[];
  for (var i = sorted.length - 1; i >= 0; i--) {
    final p = sorted[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 1e-9) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

List<List<int>> _runsTrue(List<bool> flags) {
  final count = flags.length;
  var start = -1;
  for (var i = 0; i < count; i++) {
    if (flags[i] != flags[(i + count - 1) % count]) {
      start = i;
      break;
    }
  }
  if (start < 0) return flags[0] ? [List<int>.generate(count + 1, (i) => i % count)] : [];
  final runs = <List<int>>[];
  List<int>? run;
  for (var step = 0; step < count; step++) {
    final index = (start + step) % count;
    if (flags[index]) {
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

class Group {
  Group(this.key, this.run);
  final int? key;
  final List<int> run;
}

List<Group> groupsOf(List<int?> keys) {
  final count = keys.length;
  final out = <Group>[];
  var start = -1;
  for (var i = 0; i < count; i++) {
    if (keys[i] != keys[(i + count - 1) % count]) {
      start = i;
      break;
    }
  }
  if (start < 0) {
    if (keys[0] != null) out.add(Group(keys[0], List<int>.generate(count + 1, (i) => i % count)));
    return out;
  }
  Group? current;
  for (var step = 0; step < count; step++) {
    final index = (start + step) % count;
    final key = keys[index];
    if (current != null && current.key == key) {
      current.run.add((index + 1) % count);
      continue;
    }
    if (current != null && current.key != null) out.add(current);
    current = Group(key, [index, (index + 1) % count]);
  }
  if (current != null && current.key != null) out.add(current);
  return out;
}

int stepsFor(double radius, [int least = 16, int most = 112, double scale = 0]) => math.max(
    least, math.min(most, scale != 0 ? (TAU * radius * scale / 3).ceil() : ((radius * 1.3 / 4).round()) * 4));

bool softOf(List<List<double>> meridian) => meridian.any((p) => p.length > 2 && p[2] != 0);

class Lathe implements SolidPaths {
  Lathe({required this.fill, required this.outline, required this.crease, required this.top, required this.shades, this.bevel});
  final String fill, outline, crease, top;
  final List<String> shades;
  final String? bevel;
}

// outlineOf 的 hull 分支（跳过了 surfaceOf；面片/圆柱用它即可）
List<List<double>> shapeOf(List<List<double>> meridian, Proj p, bool smooth, {double Function(double)? slope, double Function(double)? radius}) {
  if (smooth && radius != null) {
    final segments = List<Seg?>.generate(
        meridian.length - 1,
        (index) => (meridian[index + 1][0] - meridian[index][0]).abs() > 1e-9
            ? Seg(radius, slope ?? (s) => 0)
            : null);
    return curved(meridian, p, segments);
  }
  final curves = (smooth && slope == null) ? curveRuns(meridian) : null;
  if (curves != null && curves.any((c) => c != null)) return curved(meridian, p, curves);
  return meridian;
}

({String fill, String outline}) outlineOf(List<List<double>> meridian, Frame f, Proj p,
    {int? steps, String fill = 'auto', List<double>? hole, String rims = 'all', bool? smooth, double waist = 0.5}) {
  final isSmooth = smooth ?? softOf(meridian);
  final n = steps ?? stepsFor(meridian.map((m) => m[1]).reduce(math.max), 32, 160, scaleOf(p));
  final shape = shapeOf(meridian, p, isSmooth);
  final side = (fill == 'auto' || fill == 'surface') ? sideOf(shape) : null;
  final surface = (side != null && hole == null) ? surfaceOf(side, f, p, rims) : null;
  if (surface != null && (fill == 'surface' || surface.gap > waist)) {
    return (fill: surface.fill, outline: surface.outline);
  }
  if (fill == 'hull' || fill == 'auto' || fill == 'surface') {
    final most = shape.map((m) => m[1]).reduce(math.max);
    final around = math.min(320, math.max(n, (TAU * most * scaleOf(p) / 1.5).ceil()));
    final tagged = <Tagged>[];
    for (var index = 0; index < shape.length; index++) {
      final s = shape[index][0], r = shape[index][1];
      for (var j = 0; j < around; j++) {
        tagged.add(Tagged(iso(pointOf(f, s, r, (j / around) * TAU), p), index));
      }
    }
    final hull = hullTagged(tagged);
    final holePath = hole != null
        ? pathOf(
            List.generate(around, (j) => iso(pointOf(f, hole[0], hole[1], (j / around) * TAU), p)), true)
        : '';
    final fillPath = pathOf(hull.map((t) => t.p).toList(), true) + holePath;
    if (rims == 'all') return (fill: fillPath, outline: fillPath);
    final keepFirst = rims == 'first' || rims == 'ends';
    final keepLast = rims == 'last' || rims == 'ends';
    final edges = <List<Object>>[];
    for (var index = 0; index < hull.length; index++) {
      final a = hull[index];
      final b = hull[(index + 1) % hull.length];
      final same = a.ring == b.ring;
      final keep = !same ||
          (a.ring != 0 && a.ring != shape.length - 1) ||
          (keepFirst && a.ring == 0) ||
          (keepLast && a.ring == shape.length - 1);
      edges.add([a.p, b.p, keep]);
    }
    final outline = _chains(edges).map((points) => pathOf(points)).join('') + holePath;
    return (fill: fillPath, outline: outline);
  }
  return (fill: '', outline: '');
}

Lathe lathe(List<List<double>> meridian, Frame f, Proj p,
    {int? steps, String fill = 'auto', List<double>? hole, double bevel = 0, String rims = 'all', double waist = 0.5, bool? smooth}) {
  final isSmooth = smooth ?? softOf(meridian);
  final view = viewOf(p);
  final light = lightOf(p);
  final aV = dot3(f.a, view), uV = dot3(f.u, view), vV = dot3(f.v, view);
  final aL = dot3(f.a, light), uL = dot3(f.u, light), vL = dot3(f.v, light);
  final n = steps ?? stepsFor(meridian.map((m) => m[1]).reduce(math.max), 32, 160, scaleOf(p));
  final m = meridian.length;
  final rings = meridian
      .map((mr) => List.generate(n, (j) => iso(pointOf(f, mr[0], mr[1], (j / n) * TAU), p)))
      .toList();
  final midC = <double>[], midS = <double>[];
  for (var j = 0; j < n; j++) {
    final t = ((j + 0.5) / n) * TAU;
    midC.add(math.cos(t));
    midS.add(math.sin(t));
  }
  final seen = <List<bool>>[];
  final tones = <List<int>>[];
  for (var i = 0; i < m - 1; i++) {
    final ds = meridian[i + 1][0] - meridian[i][0];
    final dr = meridian[i + 1][1] - meridian[i][1];
    final length = math.sqrt(ds * ds + dr * dr);
    final row = <bool>[];
    final toneRow = <int>[];
    for (var j = 0; j < n; j++) {
      if (length < 1e-9) {
        row.add(false);
        toneRow.add(0);
        continue;
      }
      final facing = ds * (midC[j] * uV + midS[j] * vV) - dr * aV;
      final lit = (ds * (midC[j] * uL + midS[j] * vL) - dr * aL) / length;
      row.add(facing > 1e-6 * length);
      toneRow.add(bandOf(lit));
    }
    seen.add(row);
    tones.add(toneRow);
  }
  final buckets = List.generate(5, (_) => <String>[]);
  final all = <String>[];
  if (isSmooth) {
    final smoothed = smoothRows(meridian, f, p, steps: n);
    for (var tone = 0; tone < smoothed.length; tone++) {
      for (final d in smoothed[tone]) {
        buckets[tone].add(d);
        all.add(d);
      }
    }
  }
  for (var i = 0; i < m - 1; i++) {
    if (isSmooth && (meridian[i + 1][0] - meridian[i][0]).abs() > 1e-9) continue;
    final keys = List<int?>.generate(n, (j) => seen[i][j] ? tones[i][j] : null);
    for (final g in groupsOf(keys)) {
      final a = g.run.map((j) => rings[i][j]).toList();
      final b = g.run.map((j) => rings[i + 1][j]).toList().reversed.toList();
      final d = pathOf(oriented([...a, ...b]), true);
      buckets[g.key!].add(d);
      all.add(d);
    }
  }
  // 接缝 + 倒角
  final phi = math.atan2(vV, uV);
  final flatV = math.sqrt(uV * uV + vV * vV);
  List<double>? rangeOf(int i) {
    final ds = meridian[i + 1][0] - meridian[i][0];
    final dr = meridian[i + 1][1] - meridian[i][1];
    if (math.sqrt(ds * ds + dr * dr) < 1e-9) return null;
    if (ds.abs() < 1e-9 || flatV < 1e-9) return -dr * aV > 1e-9 ? [-1.0, 1.0] : null;
    final c = (dr * aV) / (ds * flatV);
    return ds > 0 ? [math.max(-1.0, c), 1.0] : [-1.0, math.min(1.0, c)];
  }

  List<List<double>> arcsOf(List<List<double>?> ranges) {
    if (ranges.any((r) => r == null)) return [];
    final lo = ranges.map((r) => r![0]).reduce(math.max);
    final hi = ranges.map((r) => r![1]).reduce(math.min);
    if (lo >= hi - 1e-9) return [];
    final near = math.acos(math.min(1.0, hi));
    final far = math.acos(math.max(-1.0, lo));
    if (hi >= 1 && lo <= -1) return [
      [phi, phi + TAU]
    ];
    if (hi >= 1) return [
      [phi - far, phi + far]
    ];
    if (lo <= -1) return [
      [phi + near, phi + TAU - near]
    ];
    return [
      [phi + near, phi + far],
      [phi - far, phi - near],
    ];
  }

  List<P2> along(double s, double r, List<double> span) {
    final count = math.max(2, ((span[1] - span[0]) * math.max(r, 1e-6) * scaleOf(p) / 1.5).ceil());
    return List.generate(count + 1, (j) => iso(pointOf(f, s, r, span[0] + (span[1] - span[0]) * j / count), p));
  }

  final creases = <String>[];
  for (var i = 1; i < m - 1; i++) {
    if ((meridian[i].length > 2 && meridian[i][2] != 0) || meridian[i][1] <= 1e-9) continue;
    for (final arc in arcsOf([rangeOf(i - 1), rangeOf(i)])) {
      creases.add(pathOf(along(meridian[i][0], meridian[i][1], arc)));
    }
  }
  var bevelPath = '';
  if (bevel > 0 && m > 2) {
    final ends = <List<int>>[];
    if (meridian[0][1] <= 1e-9) ends.add([0, 1, 1]);
    if (meridian[m - 1][1] <= 1e-9) ends.add([m - 2, m - 2, m - 3]);
    for (final e in ends) {
      final s = meridian[e[1]][0], r = meridian[e[1]][1];
      for (final arc in arcsOf([rangeOf(e[0]), rangeOf(e[2])])) {
        final inset = along(s, math.max(0, r - bevel), arc);
        final edge = along(s, r, arc);
        bevelPath += pathOf([edge[0], ...inset.sublist(1, inset.length - 1), edge[edge.length - 1]]);
      }
    }
  }
  final out = outlineOf(meridian, f, p, steps: n, fill: fill, hole: hole, rims: rims, smooth: isSmooth, waist: waist);
  return Lathe(
    fill: out.fill,
    outline: out.outline,
    crease: creases.join(''),
    top: buckets[4].join(''),
    shades: buckets.sublist(0, 4).map((l) => l.join('')).toList(),
    bevel: bevelPath.isNotEmpty ? bevelPath : null,
  );
}

// arcOf（可见那半圈的水平弧，作为接缝线用）
String arcOf(Frame f, double s, double r, Proj p, {double slope = 0, int steps = 0, double least = 0.02, int trim = 0}) {
  final view = viewOf(p);
  final aV = dot3(f.a, view), uV = dot3(f.u, view), vV = dot3(f.v, view);
  final flat = math.sqrt(uV * uV + vV * vV);
  final phi = math.atan2(vV, uV);
  final norm = math.sqrt(1 + slope * slope);
  List<List<double>> visible;
  if (flat < 1e-9) {
    visible = (-slope * aV / norm > least) ? [
      [phi, phi + TAU]
    ] : [];
  } else {
    final c = (least * norm + slope * aV) / flat;
    visible = c >= 1
        ? []
        : c <= -1
            ? [
                [phi, phi + TAU]
              ]
            : [
                [phi - math.acos(c), phi + math.acos(c)]
              ];
  }
  final at = (double t) => iso(pointOf(f, s, r, t), p);
  int count(double span) => math.max(
      2,
      math.max(((steps > 0 ? steps : stepsFor(r, 24, 112)) * span / TAU).ceil(),
          (span * r * scaleOf(p) / 1.5).ceil()));
  final out = <String>[];
  for (final ab in visible) {
    final span = ab[1] - ab[0];
    final cn = count(span);
    out.add(pathOf(List.generate(cn + 1, (j) => at(ab[0] + span * j / cn))));
  }
  return out.join('');
}

String circleOf(Frame f, double s, double r, Proj p, [int steps = 0]) {
  final count = steps > 0 ? steps : stepsFor(r, 24, 112);
  return pathOf(List.generate(count, (j) => iso(pointOf(f, s, r, (j / count) * TAU), p)), true);
}

String arcPointsPath(Frame f, double s, double r, double a0, double a1, Proj p, [int steps = 24]) =>
    pathOf(List.generate(steps + 1, (i) => iso(pointOf(f, s, r, a0 + (a1 - a0) * i / steps), p)));

List<P2> dotsOf(Frame f, double s, double r, int count, Proj p,
    {double phase = 0, double slope = 0, double least = 0.08, bool all = false}) {
  final view = viewOf(p);
  final out = <P2>[];
  for (var index = 0; index < count; index++) {
    final t = phase + (index / count) * TAU;
    if (!all) {
      final radial = radialOf(f, t);
      final normal = unit3([radial[0] - slope * f.a[0], radial[1] - slope * f.a[1], radial[2] - slope * f.a[2]]);
      if (dot3(normal, view) < least) continue;
    }
    out.add(iso(pointOf(f, s, r, t), p));
  }
  return out;
}

String spokesOf(Frame f, double s, double r0, double r1, int count, Proj p,
    {double phase = 0, double sweep = 0, double from = 0, double to = TAU}) {
  final lines = <String>[];
  for (var index = 0; index < count; index++) {
    final t = phase + from + (index / count) * (to - from);
    lines.add(pathOf([iso(pointOf(f, s, r0, t), p), iso(pointOf(f, s, r1, t + sweep), p)]));
  }
  return lines.join('');
}

List<P2> circleRing2(double cx, double cy, double radius, [int steps = 40]) {
  return List.generate(steps, (s) {
    final angle = (s / steps) * TAU;
    return [cx + radius * math.cos(angle), cy + radius * math.sin(angle)];
  });
}

// ── 常用封装 ──
Lathe sphereOf(V3 centre, double r, Proj p, {int steps = 48}) {
  final view = viewOf(p);
  final light = lightOf(p);
  final f = frameAlong(centre, view);
  final rim = List.generate(steps, (i) => pointOf(f, 0, r, (i / steps) * TAU));
  String capOf(double threshold) {
    final points = rim
        .where((pt) => dot3(sub3(pt, centre), light) / r >= threshold)
        .map((pt) => iso(pt, p))
        .toList();
    final lf = frameAlong(add3(centre, mul3(light, r * threshold)), light);
    final radius = r * math.sqrt(math.max(0, 1 - threshold * threshold));
    for (var i = 0; i < steps; i++) {
      final pt = pointOf(lf, 0, radius, (i / steps) * TAU);
      if (dot3(sub3(pt, centre), view) >= -1e-9) points.add(iso(pt, p));
    }
    return points.length > 2 ? pathOf(hullPoints(points), true) : '';
  }

  final outline = pathOf(rim.map((pt) => iso(pt, p)).toList(), true);
  return Lathe(
    fill: outline,
    outline: outline,
    crease: '',
    top: '',
    shades: [outline, capOf(BANDS[1]), capOf(BANDS[2]), capOf(BANDS[3])],
  );
}

Lathe disc(double s0, double s1, double r, Frame f, Proj p, {int? steps}) => lathe([
      [s0, 0],
      [s0, r],
      [s1, r],
      [s1, 0],
    ], f, p, steps: steps ?? stepsFor(r, 32, 160, scaleOf(p)));

Lathe ringBand(double s0, double s1, double rIn, double rOut, Frame f, Proj p, {int? steps}) => lathe([
      [s0, rIn],
      [s0, rOut],
      [s1, rOut],
      [s1, rIn],
    ], f, p, steps: steps ?? stepsFor(rOut, 32, 160, scaleOf(p)));

Lathe solidOf(List<List<double>> profile, Frame f, Proj p, {int? steps}) {
  final first = profile.first;
  final last = profile.last;
  final meridian = [
    [first[0], 0.0],
    ...profile,
    [last[0], 0.0],
  ];
  final most = profile.map((pt) => pt[1]).reduce(math.max);
  return lathe(meridian, f, p, steps: steps ?? stepsFor(most, 32, 160, scaleOf(p)));
}

Lathe bandOfProfile(List<List<double>> profile, Frame f, Proj p, {int? steps}) {
  final most = profile.map((pt) => pt[1]).reduce(math.max);
  return lathe(profile, f, p, steps: steps ?? stepsFor(most, 32, 160, scaleOf(p)));
}

// 二维点集的凸包（sphereOf 用）
List<P2> hullPoints(List<P2> points) {
  final sorted = [...points]..sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
  if (sorted.length < 3) return sorted;
  double cross(P2 o, P2 a, P2 b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  final lower = <P2>[];
  for (final p in sorted) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 1e-9) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <P2>[];
  for (var i = sorted.length - 1; i >= 0; i--) {
    final p = sorted[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 1e-9) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

// ── 路径工具（tube 等依赖）──
double pathLength(List<V3> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += len3(sub3(points[i], points[i - 1]));
  }
  return total;
}

List<V3> resample(List<V3> points, double spacing) {
  final lengths = <double>[0];
  for (var i = 1; i < points.length; i++) {
    lengths.add(lengths[i - 1] + len3(sub3(points[i], points[i - 1])));
  }
  final total = lengths[lengths.length - 1];
  final count = math.max(1, (total / spacing).round());
  final out = <V3>[];
  var segment = 1;
  for (var step = 0; step <= count; step++) {
    final at = total * step / count;
    while (segment < points.length - 1 && lengths[segment] < at) {
      segment++;
    }
    final a = points[segment - 1];
    final b = points[segment];
    final span = lengths[segment] - lengths[segment - 1];
    out.add(lerp3(a, b, ((at - lengths[segment - 1]) / (span == 0 ? 1 : span)).clamp(0.0, 1.0)));
  }
  return out;
}

List<V3> cut(List<V3> points, double from, double to) {
  final out = <V3>[];
  var walked = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final length = len3(sub3(b, a));
    final start = walked;
    final end = walked + length;
    if (end >= from && start <= to) {
      final t0 = math.max(0.0, (from - start) / (length == 0 ? 1 : length));
      final t1 = math.min(1.0, (to - start) / (length == 0 ? 1 : length));
      if (out.isEmpty) out.add(lerp3(a, b, t0));
      out.add(lerp3(a, b, t1));
    }
    walked = end;
  }
  return out;
}

V3 pointAlong(List<V3> points, double at) {
  final piece = cut(points, at, at + 0.01);
  return piece.isNotEmpty ? piece[0] : points.last;
}

V3 tangentAlong(List<V3> points, double at) {
  final total = pathLength(points);
  final a = pointAlong(points, math.max(0, at - 0.6));
  final b = pointAlong(points, math.min(total, at + 0.6));
  return unit3(sub3(b, a));
}

double fadeOf(double value, List<double> range) {
  final span = (range[1] - range[0]) == 0 ? 1e-9 : (range[1] - range[0]);
  final t = ((value - range[0]) / span).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double facingOf(Frame f, double angle, Proj p, [double slope = 0]) {
  final radial = radialOf(f, angle);
  return dot3(unit3([radial[0] - slope * f.a[0], radial[1] - slope * f.a[1], radial[2] - slope * f.a[2]]), viewOf(p));
}

// ── 样条（curveRuns / curved）──
double _sign(double x) => x > 0 ? 1 : (x < 0 ? -1 : 0);

class Seg {
  Seg(this.radius, this.slope);
  final double Function(double) radius;
  final double Function(double) slope;
}

List<double> _hermiteSlopes(List<List<double>> run) {
  final n = run.length - 1;
  final h = List.generate(n, (j) => run[j + 1][0] - run[j][0]);
  final delta = List.generate(n, (j) => h[j] == 0 ? 0.0 : (run[j + 1][1] - run[j][1]) / h[j]);
  final d = List.filled(n + 1, 0.0);
  double end(double h0, double h1, double d0, double d1) {
    var v = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1);
    if (_sign(v) != _sign(d0)) {
      v = 0;
    } else if (_sign(d0) != _sign(d1) && v.abs() > (3 * d0).abs()) {
      v = 3 * d0;
    }
    return v;
  }

  if (n == 1) {
    d[0] = delta[0];
    d[1] = delta[0];
  } else {
    d[0] = end(h[0], h[1], delta[0], delta[1]);
    d[n] = end(h[n - 1], h[n - 2], delta[n - 1], delta[n - 2]);
  }
  for (var k = 1; k < n; k++) {
    if (delta[k - 1] * delta[k] <= 0) continue;
    final w1 = 2 * h[k] + h[k - 1];
    final w2 = h[k] + 2 * h[k - 1];
    d[k] = (w1 + w2) / (w1 / delta[k - 1] + w2 / delta[k]);
  }
  return d;
}

List<Seg?> curveRuns(List<List<double>> meridian) {
  final m = meridian.length;
  final segments = List<Seg?>.filled(m - 1, null);
  var start = 0;
  while (start < m - 1) {
    var end = start + 1;
    while (end < m - 1 &&
        (meridian[end].length > 2 && meridian[end][2] != 0) &&
        (meridian[end + 1][0] - meridian[end][0]).abs() > 1e-9 &&
        (meridian[end][0] - meridian[end - 1][0]).abs() > 1e-9) {
      end++;
    }
    final run = meridian.sublist(start, end + 1);
    final n = run.length - 1;
    var ok = n >= 2;
    for (var j = 1; j < run.length && ok; j++) {
      if ((run[j][0] - run[j - 1][0]).abs() <= 1e-9) ok = false;
    }
    if (ok) {
      final d = _hermiteSlopes(run);
      for (var j = 0; j < n; j++) {
        final s0 = run[j][0], r0 = run[j][1];
        final s1 = run[j + 1][0], r1 = run[j + 1][1];
        final hj = s1 - s0;
        final d0 = d[j], d1 = d[j + 1];
        segments[start + j] = Seg(
          (s) {
            final t = hj == 0 ? 0.0 : (s - s0) / hj;
            return (2 * t * t * t - 3 * t * t + 1) * r0 +
                (t * t * t - 2 * t * t + t) * hj * d0 +
                (-2 * t * t * t + 3 * t * t) * r1 +
                (t * t * t - t * t) * hj * d1;
          },
          (s) {
            final t = hj == 0 ? 0.0 : (s - s0) / hj;
            return ((6 * t * t - 6 * t) * r0 + (6 * t - 6 * t * t) * r1) / hj +
                (3 * t * t - 4 * t + 1) * d0 +
                (3 * t * t - 2 * t) * d1;
          },
        );
      }
    }
    start = end;
  }
  return segments;
}

List<List<double>> curved(List<List<double>> meridian, Proj p, List<Seg?> segments, {double error = 0.2, int depth = 6}) {
  final k = scaleOf(p);
  final out = <List<double>>[meridian[0]];
  for (var i = 0; i < meridian.length - 1; i++) {
    final curve = segments[i];
    final s0 = meridian[i][0], s1 = meridian[i + 1][0];
    if (curve != null) {
      void split(double a, double b, int level) {
        final mid = (a + b) / 2;
        final chord = (curve.radius(a) + curve.radius(b)) / 2;
        if (level < depth && (curve.radius(mid) - chord).abs() * k > error) {
          split(a, mid, level + 1);
          out.add([mid, curve.radius(mid), 1]);
          split(mid, b, level + 1);
        }
      }

      split(s0, s1, 0);
    }
    out.add(meridian[i + 1]);
  }
  return out;
}

// ── labelledArcs（smoothRows 用）──
class ViewLight {
  ViewLight(this.a, this.flat, this.phi);
  final double a, flat, phi;
}

class Arc {
  Arc(this.tone, this.from, this.to);
  int tone;
  double from, to;
}

List<Arc> labelledArcs(double nr, double na, ViewLight view, ViewLight light, [double gr = double.nan, double ga = double.nan]) {
  final gR = gr.isNaN ? nr : gr;
  final gA = ga.isNaN ? na : ga;
  final cuts = <double>[];
  if (gR.abs() > 1e-9) {
    final visibleCut = -(gA * view.a) / (gR * view.flat);
    if (visibleCut > -1 && visibleCut < 1) {
      final d = math.acos(visibleCut);
      cuts.add(view.phi - d);
      cuts.add(view.phi + d);
    }
  }
  if (nr.abs() > 1e-9) {
    for (final threshold in BANDS) {
      final c = (threshold - na * light.a) / (nr * light.flat);
      if (c > -1 && c < 1) {
        final d = math.acos(c);
        cuts.add(light.phi - d);
        cuts.add(light.phi + d);
      }
    }
  }
  double wrap(double angle) => ((angle % TAU) + TAU) % TAU;
  final sorted = cuts.map((a) => (wrap(a) * 1e9).round() / 1e9).toSet().toList()..sort();
  int label(double angle) {
    final facing = gR * view.flat * math.cos(angle - view.phi) + gA * view.a;
    if (facing <= 1e-9) return -1;
    return bandOf(nr * light.flat * math.cos(angle - light.phi) + na * light.a);
  }

  if (sorted.isEmpty) {
    final tone = label(0);
    return tone < 0 ? [] : [Arc(tone, 0, TAU)];
  }
  final arcs = <Arc>[];
  for (var index = 0; index < sorted.length; index++) {
    final from = sorted[index];
    final to = index + 1 < sorted.length ? sorted[index + 1] : sorted[0] + TAU;
    arcs.add(Arc(label((from + to) / 2), from, to));
  }
  final merged = <Arc>[];
  for (final arc in arcs) {
    if (merged.isNotEmpty && merged.last.tone == arc.tone && (merged.last.to - arc.from).abs() < 1e-9) {
      merged.last.to = arc.to;
    } else {
      merged.add(Arc(arc.tone, arc.from, arc.to));
    }
  }
  if (merged.length > 1 &&
      merged.first.tone == merged.last.tone &&
      (merged.last.to - TAU - merged.first.from).abs() < 1e-9) {
    final last = merged.removeLast();
    merged.first.from = last.from - TAU;
  }
  return merged.where((a) => a.tone >= 0).toList();
}

class Level {
  Level(this.i, this.u, this.groups);
  final int i;
  final double u;
  final Map<int, List<Arc>> groups;
}

List<List<String>> smoothRows(List<List<double>> meridian, Frame f, Proj p,
    {int rows = 6,
    double Function(double)? slope,
    double Function(double)? radius,
    int steps = 48,
    double error = 0.35,
    int deepest = 8,
    double fineness = 0.1}) {
  final v = viewOf(p);
  final l = lightOf(p);
  final view = ViewLight(dot3(f.a, v), math.sqrt(math.pow(dot3(f.u, v), 2) + math.pow(dot3(f.v, v), 2)),
      math.atan2(dot3(f.v, v), dot3(f.u, v)));
  final light = ViewLight(dot3(f.a, l), math.sqrt(math.pow(dot3(f.u, l), 2) + math.pow(dot3(f.v, l), 2)),
      math.atan2(dot3(f.v, l), dot3(f.u, l)));
  final m = meridian.length;
  final faces = <List<double>>[];
  for (var i = 0; i < m - 1; i++) {
    final ds = meridian[i + 1][0] - meridian[i][0];
    final dr = meridian[i + 1][1] - meridian[i][1];
    final length = math.sqrt(ds * ds + dr * dr) == 0 ? 1.0 : math.sqrt(ds * ds + dr * dr);
    faces.add([ds / length, -dr / length]);
  }
  final splines = slope != null ? null : curveRuns(meridian);
  List<double> vertexNormal(int k, List<double> own) {
    if (k <= 0 || k >= m - 1 || meridian[k].length <= 2 || meridian[k][2] == 0) return own;
    final a = faces[k - 1], b = faces[k];
    final x = a[0] + b[0], y = a[1] + b[1];
    final length = math.sqrt(x * x + y * y) == 0 ? 1.0 : math.sqrt(x * x + y * y);
    return [x / length, y / length];
  }

  List<double> normalAt(int i, double u) {
    final s0 = meridian[i][0], s1 = meridian[i + 1][0];
    final s = s0 + (s1 - s0) * u;
    final sign = _sign(s1 - s0) == 0 ? 1.0 : _sign(s1 - s0).toDouble();
    final double? g = slope != null ? slope(s) : (splines![i] != null ? splines[i]!.slope(s) : null);
    if (g != null) {
      final length = math.sqrt(1 + g * g);
      return [sign / length, (-sign * g) / length];
    }
    final a = vertexNormal(i, faces[i]);
    final b = vertexNormal(i + 1, faces[i]);
    final x = a[0] + (b[0] - a[0]) * u;
    final y = a[1] + (b[1] - a[1]) * u;
    final length = math.sqrt(x * x + y * y) == 0 ? 1.0 : math.sqrt(x * x + y * y);
    return [x / length, y / length];
  }

  P2 pointAt(int i, double u, double angle) {
    final s0 = meridian[i][0], r0 = meridian[i][1];
    final s1 = meridian[i + 1][0], r1 = meridian[i + 1][1];
    final s = s0 + (s1 - s0) * u;
    final r = radius != null
        ? radius(s)
        : (splines != null && splines[i] != null ? splines[i]!.radius(s) : r0 + (r1 - r0) * u);
    return iso(pointOf(f, s, r, angle), p);
  }

  final buckets = List.generate(5, (_) => <String>[]);
  final fine = TAU / math.max(24, math.min(192, steps * 1.5));
  List<P2> arcPoints(int i, double u, double from, double to) {
    final count = math.max(1, ((to - from) / fine).ceil());
    return List.generate(count + 1, (index) => pointAt(i, u, from + (to - from) * index / count));
  }

  double centreOf(Arc arc, double reference) {
    var mid = (arc.from + arc.to) / 2 - reference;
    mid = ((mid % TAU) + TAU) % TAU;
    return mid;
  }

  Level levelOf(int i, double u) {
    final nl = normalAt(i, u);
    final groups = <int, List<Arc>>{};
    for (final arc in labelledArcs(nl[0], nl[1], view, light, faces[i][0], faces[i][1])) {
      groups.putIfAbsent(arc.tone, () => []).add(arc);
    }
    for (final list in groups.values) {
      list.sort((x, y) => (centreOf(x, light.phi) - centreOf(y, light.phi)).sign.toInt());
    }
    return Level(i, u, groups);
  }

  bool same(Level x, Level y) {
    if (x.groups.length != y.groups.length) return false;
    for (final e in x.groups.entries) {
      if ((y.groups[e.key] ?? []).length != e.value.length) return false;
    }
    return true;
  }

  Arc align(Arc reference, Arc arc) {
    final out = Arc(arc.tone, arc.from, arc.to);
    final centre = (reference.from + reference.to) / 2;
    while ((out.from + out.to) / 2 - centre > math.pi) {
      out.from -= TAU;
      out.to -= TAU;
    }
    while (centre - (out.from + out.to) / 2 > math.pi) {
      out.from += TAU;
      out.to += TAU;
    }
    return out;
  }

  double strayOf(int i, Level a, Level mid, Level b) {
    var worst = 0.0;
    for (final e in mid.groups.entries) {
      final list = e.value;
      for (var index = 0; index < list.length; index++) {
        final arc = list[index];
        final lo = align(arc, a.groups[e.key]![index]);
        final hi = align(arc, b.groups[e.key]![index]);
        for (final key in ['from', 'to']) {
          final pa = pointAt(i, mid.u, key == 'from' ? arc.from : arc.to);
          final p0 = pointAt(i, a.u, key == 'from' ? lo.from : lo.to);
          final p1 = pointAt(i, b.u, key == 'from' ? hi.from : hi.to);
          worst = math.max(worst,
              math.sqrt(math.pow(pa[0] - (p0[0] + p1[0]) / 2, 2) + math.pow(pa[1] - (p0[1] + p1[1]) / 2, 2)));
        }
      }
    }
    return worst;
  }

  void sheet(int tone, List<Level> levels) {
    final first = levels[0].groups[tone]!;
    for (var index = 0; index < first.length; index++) {
      final chain = <Arc>[first[index]];
      for (var k = 1; k < levels.length; k++) {
        chain.add(align(chain[k - 1], levels[k].groups[tone]![index]));
      }
      final last = levels.length - 1;
      final points = <P2>[...arcPoints(levels[0].i, levels[0].u, chain[0].from, chain[0].to)];
      for (var k = 1; k < last; k++) {
        points.add(pointAt(levels[k].i, levels[k].u, chain[k].to));
      }
      points.addAll(arcPoints(levels[last].i, levels[last].u, chain[last].from, chain[last].to).reversed);
      for (var k = last - 1; k >= 1; k--) {
        points.add(pointAt(levels[k].i, levels[k].u, chain[k].from));
      }
      buckets[tone].add(pathOf(oriented(points), true));
    }
  }

  void strip(int tone, Level a, Level b) {
    final below = a.groups[tone] ?? [];
    final above = (b.groups[tone] ?? []).map((arc) => _Above(arc, false)).toList();
    void quad(double from0, double to0, double from1, double to1) {
      final points = <P2>[
        ...arcPoints(a.i, a.u, from0, to0),
        ...arcPoints(b.i, b.u, from1, to1).reversed,
      ];
      buckets[tone].add(pathOf(oriented(points), true));
    }

    for (final arc in below) {
      double score = double.negativeInfinity;
      _Above? best;
      for (final entry in above) {
        if (entry.used) continue;
        final aligned = align(arc, entry.arc);
        final value = math.min(arc.to, aligned.to) - math.max(arc.from, aligned.from);
        if (value > score) {
          score = value;
          best = entry;
        }
      }
      if (best != null && score > -0.05) {
        best.used = true;
        final aligned = align(arc, best.arc);
        quad(arc.from, arc.to, aligned.from, aligned.to);
      } else {
        final centre = (arc.from + arc.to) / 2;
        quad(arc.from, arc.to, centre, centre);
      }
    }
    for (final entry in above) {
      if (entry.used) continue;
      final centre = (entry.arc.from + entry.arc.to) / 2;
      quad(centre, centre, entry.arc.from, entry.arc.to);
    }
  }

  final k = scaleOf(p);
  var run = <Level>[];
  void flush() {
    final tones = <int>{for (final level in run) ...level.groups.keys}.toList()..sort();
    for (final tone in tones) {
      int countOf(Level level) => (level.groups[tone] ?? []).length;
      var start = 0;
      for (var at = 1; at <= run.length; at++) {
        if (at < run.length && countOf(run[at - 1]) == countOf(run[at])) continue;
        if (at - 1 > start && countOf(run[start]) > 0) sheet(tone, run.sublist(start, at));
        if (at < run.length) strip(tone, run[at - 1], run[at]);
        start = at;
      }
    }
    run = <Level>[];
  }

  for (var i = 0; i < m - 1; i++) {
    final ds = meridian[i + 1][0] - meridian[i][0];
    if (ds.abs() < 1e-9) {
      flush();
      continue;
    }
    final count = math.max(1, rows);
    final reach = math.sqrt(ds * ds + math.pow(meridian[i + 1][1] - meridian[i][1], 2)) * k / count;
    final limit = math.max(1, math.min(deepest, (math.log(math.max(2, reach / fineness)) / math.ln2).ceil()));
    final coarse = List.generate(count + 1, (index) => levelOf(i, index / count));
    run.add(coarse[0]);
    void refine(Level a, Level b, int depth) {
      final mid = levelOf(i, (a.u + b.u) / 2);
      final split = depth < limit &&
          (!same(a, b) || !same(a, mid) || (depth < 6 && strayOf(i, a, mid, b) > error));
      if (!split) {
        run.add(b);
        return;
      }
      refine(a, mid, depth + 1);
      refine(mid, b, depth + 1);
    }

    for (var index = 1; index <= count; index++) {
      refine(coarse[index - 1], coarse[index], 0);
    }
  }
  flush();
  return buckets;
}

class _Above {
  _Above(this.arc, this.used);
  final Arc arc;
  bool used;
}

// ── sideOf / surfaceOf / silhouette ──
List<List<double>>? sideOf(List<List<double>> meridian) {
  final m = meridian.length;
  var first = 0;
  var last = m - 1;
  if (meridian[0][1] <= 1e-9) first = 1;
  if (meridian[m - 1][1] <= 1e-9) last = m - 2;
  final side = meridian.sublist(first, last + 1);
  for (var index = 1; index < side.length; index++) {
    if (side[index][0] - side[index - 1][0] <= 1e-9) return null;
  }
  return side.length >= 3 ? side : null;
}

List<List<V3>> silhouettePoints(List<List<double>> profile, Frame f, Proj p,
    {int samples = 72, double Function(double)? slope, double Function(double)? radius}) {
  final v = viewOf(p);
  final aV = dot3(f.a, v), uV = dot3(f.u, v), vV = dot3(f.v, v);
  final facing = math.atan2(vV, uV);
  final flat = math.sqrt(uV * uV + vV * vV) == 0 ? 1e-9 : math.sqrt(uV * uV + vV * vV);
  final s0 = profile[0][0];
  final s1 = profile[profile.length - 1][0];
  final double Function(double) radiusAt = radius ??
      (double s) {
        var index = 1;
        while (index < profile.length - 1 && profile[index][0] < s) {
          index++;
        }
        final sa = profile[index - 1][0], ra = profile[index - 1][1];
        final sb = profile[index][0], rb = profile[index][1];
        return ra + (rb - ra) * (s - sa) / (sb - sa == 0 ? 1 : sb - sa);
      };
  List<V3> side(double sign) {
    final points = <V3>[];
    for (var step = 0; step <= samples; step++) {
      final s = s0 + (s1 - s0) * step / samples;
      final h = (s1 - s0) / samples / 2;
      final slopeV = slope != null
          ? slope(s)
          : (radiusAt(math.min(s1, s + h)) - radiusAt(math.max(s0, s - h))) /
              ((math.min(s1, s + h) - math.max(s0, s - h)) == 0 ? 1 : (math.min(s1, s + h) - math.max(s0, s - h)));
      final c = slopeV * aV / flat;
      if (c.abs() > 1) continue;
      points.add(pointOf(f, s, radiusAt(s), facing + sign * math.acos(c)));
    }
    return points;
  }

  return [side(1), side(-1)];
}

String silhouetteOf(List<List<double>> profile, Frame f, Proj p,
        {int samples = 72, double Function(double)? slope, double Function(double)? radius}) =>
    silhouettePoints(profile, f, p, samples: samples, slope: slope, radius: radius)
        .map((points) => pathOf(points.map((pt) => iso(pt, p)).toList()))
        .join('');

class Surface {
  Surface(this.fill, this.outline, this.gap);
  final String fill, outline;
  final double gap;
}

Surface? surfaceOf(List<List<double>> side, Frame f, Proj p, String rims,
    {int samples = 96, double Function(double)? slope}) {
  final v = viewOf(p);
  final aV = dot3(f.a, v);
  final facing = math.atan2(dot3(f.v, v), dot3(f.u, v));
  final sil = silhouettePoints(side, f, p, samples: samples, slope: slope);
  final left = sil[0], right = sil[1];
  if (left.length <= samples || right.length <= samples) return null;
  final s0 = side[0][0];
  final s1 = side[side.length - 1][0];
  double angleOf(V3 point) {
    final proj = add3(f.o, mul3(f.a, dot3(sub3(point, f.o), f.a)));
    return angleToward(f, sub3(point, proj));
  }

  double wrap(double angle) => ((angle % TAU) + TAU) % TAU;
  List<P2> arc(double s, double r, double from, double to, double through) {
    var sweep = wrap(to - from);
    if (wrap(through - from) > sweep) sweep -= TAU;
    final count = <int>[4, (sweep.abs() / (TAU / 96)).ceil(), (sweep.abs() * r * scaleOf(p) / 1.5).ceil()]
        .reduce(math.max);
    return List.generate(count + 1, (index) => iso(pointOf(f, s, r, from + sweep * index / count), p));
  }

  final r0 = side[0][1];
  final r1 = side[side.length - 1][1];
  final bottom = -aV > 0 ? facing + math.pi : facing;
  final top = aV > 0 ? facing + math.pi : facing;
  final lp = left.map((pt) => iso(pt, p)).toList();
  final rp = right.map((pt) => iso(pt, p)).toList();
  final topArc = arc(s1, r1, angleOf(left[left.length - 1]), angleOf(right[right.length - 1]), top);
  final bottomArc = arc(s0, r0, angleOf(right[0]), angleOf(left[0]), bottom);
  final keepFirst = rims == 'all' || rims == 'first' || rims == 'ends';
  final keepLast = rims == 'all' || rims == 'last' || rims == 'ends';
  final fill = pathOf([...lp, ...topArc, ...rp.reversed, ...bottomArc], true);
  final outline = [pathOf(lp), pathOf(rp), keepLast ? pathOf(topArc) : '', keepFirst ? pathOf(bottomArc) : ''].join('');
  final hull = hullPoints([
    ...arc(s0, r0, 0, TAU - 1e-6, math.pi),
    ...arc(s1, r1, 0, TAU - 1e-6, math.pi),
    ...lp,
    ...rp,
  ]);
  var gap = 0.0;
  for (final pt in [...lp, ...rp]) {
    var best = double.infinity;
    for (var index = 0; index < hull.length; index++) {
      final a = hull[index];
      final b = hull[(index + 1) % hull.length];
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final denom = (dx * dx + dy * dy) == 0 ? 1.0 : (dx * dx + dy * dy);
      final t = ((pt[0] - a[0]) * dx + (pt[1] - a[1]) * dy) / denom;
      final tt = t.clamp(0.0, 1.0);
      best = math.min(best, math.sqrt(math.pow(pt[0] - a[0] - dx * tt, 2) + math.pow(pt[1] - a[1] - dy * tt, 2)));
    }
    gap = math.max(gap, best);
  }
  return Surface(fill, outline, gap);
}

List<List<P2>> _chains(List<List<Object>> edges) {
  final out = <List<P2>>[];
  List<P2>? current;
  for (final e in edges) {
    final keep = e[2] as bool;
    if (!keep) {
      if (current != null) out.add(current);
      current = null;
      continue;
    }
    if (current == null) current = <P2>[e[0] as P2];
    current.add(e[1] as P2);
  }
  if (current != null) out.add(current);
  if (out.length > 1 && (edges.first[2] as bool) && (edges.last[2] as bool)) {
    final last = out.removeLast();
    out[0] = [...last, ...out[0].sublist(1)];
  }
  return out;
}

// ── prismOf / stadium / sphere 等 ──
Lathe prismOf(Frame f, List<P2> polygon, double s0, double s1, Proj p) {
  final v = viewOf(p);
  final l = lightOf(p);
  final ring = oriented(polygon.map((pt) => [pt[0], pt[1]]).toList());
  final n = ring.length;
  V3 at(double s, P2 pt) => [
        f.o[0] + f.a[0] * s + f.u[0] * pt[0] + f.v[0] * pt[1],
        f.o[1] + f.a[1] * s + f.u[1] * pt[0] + f.v[1] * pt[1],
        f.o[2] + f.a[2] * s + f.u[2] * pt[0] + f.v[2] * pt[1],
      ];
  final low = ring.map((pt) => iso(at(s0, pt), p)).toList();
  final high = ring.map((pt) => iso(at(s1, pt), p)).toList();
  final buckets = List.generate(5, (_) => <String>[]);
  final seen = <bool>[];
  for (var j = 0; j < n; j++) {
    final x0 = ring[j][0], y0 = ring[j][1];
    final x1 = ring[(j + 1) % n][0], y1 = ring[(j + 1) % n][1];
    final normal = unit3(add3(mul3(f.u, y1 - y0), mul3(f.v, -(x1 - x0))));
    final visible = dot3(normal, v) > 1e-6;
    seen.add(visible);
    if (visible) {
      buckets[bandOf(dot3(normal, l))].add(pathOf([low[j], low[(j + 1) % n], high[(j + 1) % n], high[j]], true));
    }
  }
  final ends = <List<Object>>[
    [s0, low, mul3(f.a, -1)],
    [s1, high, f.a]
  ];
  final capSeen = ends.map((e) => dot3(e[2] as V3, v) > 1e-6).toList();
  for (var index = 0; index < ends.length; index++) {
    if (capSeen[index]) {
      buckets[bandOf(dot3(ends[index][2] as V3, l))].add(pathOf(ends[index][1] as List<P2>, true));
    }
  }
  final hull = hullPoints([...low, ...high]);
  final creases = <String>[];
  for (var j = 0; j < n; j++) {
    final prev = (j - 1 + n) % n;
    final a = [ring[j][0] - ring[prev][0], ring[j][1] - ring[prev][1]];
    final b = [ring[(j + 1) % n][0] - ring[j][0], ring[(j + 1) % n][1] - ring[j][1]];
    final sharp = (a[0] * b[0] + a[1] * b[1]) /
            ((math.sqrt(a[0] * a[0] + a[1] * a[1]) * math.sqrt(b[0] * b[0] + b[1] * b[1])) == 0
                ? 1
                : (math.sqrt(a[0] * a[0] + a[1] * a[1]) * math.sqrt(b[0] * b[0] + b[1] * b[1]))) <
        math.cos(0.35);
    if (sharp && seen[j] && seen[prev]) creases.add(pathOf([low[j], high[j]]));
  }
  final poly = pathOf(hull, true);
  return Lathe(
    fill: poly,
    outline: poly,
    crease: creases.join(''),
    top: buckets[4].join(''),
    shades: buckets.sublist(0, 4).map((x) => x.join('')).toList(),
  );
}

List<P2> stadium(double r0, double r1, double offset, [int steps = 32]) {
  List<P2> circle(double cx, double r) =>
      List.generate(steps, (index) => [cx + r * math.cos(index / steps * TAU), r * math.sin(index / steps * TAU)]);
  return hullPoints([...circle(0, r0), ...circle(offset, r1)]);
}

class RodOut {
  RodOut(this.paths, this.clip, this.from, this.to, this.stroke, this.reach);
  final Lathe paths;
  final String clip;
  final double from, to, stroke, reach;
}

RodOut rodOut(Frame f, double from, double to, double r, Proj p,
    {double stroke = 0, int? steps, double bevel = 0, String rims = 'all'}) {
  final pad = 0.35 / scaleOf(p);
  List<P2> ring(double s) =>
      List.generate(48, (index) => iso(pointOf(f, s, r + pad, index / 48 * TAU), p));
  return RodOut(
    disc(from - stroke, to, r, f, p, steps: steps),
    pathOf(hullPoints([...ring(from), ...ring(to + stroke)]), true),
    from,
    to,
    stroke,
    to + stroke,
  );
}

// ── profileCurve / bandsOf ──
class ProfileCurve {
  ProfileCurve(this.s0, this.s1, this.radius, this.slope, this.analytic);
  final double s0, s1;
  final double Function(double) radius;
  final double Function(double) slope;
  final bool analytic;
}

ProfileCurve profileCurve(List<List<double>> profile, {double Function(double)? slope, double Function(double)? radius}) {
  for (var index = 1; index < profile.length; index++) {
    if (profile[index][0] - profile[index - 1][0] <= 1e-9) {
      throw ArgumentError('profileCurve: s must rise along the profile (point $index at s = ${profile[index][0]})');
    }
  }
  final segments = curveRuns(profile);
  final s0 = profile[0][0];
  final s1 = profile[profile.length - 1][0];
  int find(double s) {
    var lo = 0, hi = profile.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (profile[mid][0] <= s) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  List<double> linear(int index, double s) {
    final sa = profile[index][0], ra = profile[index][1];
    final sb = profile[index + 1][0], rb = profile[index + 1][1];
    return [ra + (rb - ra) * (s - sa) / (sb - sa), (rb - ra) / (sb - sa)];
  }

  double radiusAt(double s) {
    if (radius != null) return radius(s);
    final at = s.clamp(s0, s1);
    final index = find(at);
    return segments[index] != null ? segments[index]!.radius(at) : linear(index, at)[0];
  }

  double slopeAt(double s) {
    if (slope != null) return slope(s);
    final at = s.clamp(s0, s1);
    final index = find(at);
    return segments[index] != null ? segments[index]!.slope(at) : linear(index, at)[1];
  }

  return ProfileCurve(s0, s1, radiusAt, slopeAt, slope != null && radius != null);
}

// ── ribsOf / fillet / spiral ──
List<Object> ribsOf(Frame f, double s0, double s1, double r, int count, Proj p,
    {double phase = 0, double twist = 0, double least = 0.12, double? r1, List<double>? fade, bool seams = false}) {
  final v = viewOf(p);
  final lines = <Object>[];
  final rEnd = r1 ?? r;
  final slope = (rEnd - r) / ((s1 - s0) == 0 ? 1 : (s1 - s0));
  for (var index = 0; index < count; index++) {
    final t = phase + (index / count) * TAU;
    final radial = radialOf(f, t + twist / 2);
    final normal = unit3([radial[0] - slope * f.a[0], radial[1] - slope * f.a[1], radial[2] - slope * f.a[2]]);
    final facing = dot3(normal, v);
    final d = pathOf([iso(pointOf(f, s0, r, t), p), iso(pointOf(f, s1, rEnd, t + twist), p)]);
    if (fade != null) {
      final alpha = fadeOf(facing, fade);
      if (alpha > 0.02) lines.add([d, alpha]);
      continue;
    }
    if (facing < least) continue;
    lines.add(d);
  }
  if (seams) {
    lines.add(arcOf(f, s0, r, p, slope: slope));
    lines.add(arcOf(f, s1, rEnd, p, slope: slope));
  }
  return lines;
}

List<V3> fillet(List<V3> points, double radius, [int perArc = 7, Proj? p, double tube = 0, double margin = 1.3]) {
  if (points.length < 3) return points.map((pt) => [...pt]).toList();
  final v = (p != null && tube > 0) ? viewOf(p) : null;
  final out = <V3>[[...points[0]]];
  for (var index = 1; index < points.length - 1; index++) {
    final prev = points[index - 1];
    final here = points[index];
    final next = points[index + 1];
    final into = unit3(sub3(here, prev));
    final outOf = unit3(sub3(next, here));
    final cosTurn = dot3(into, outOf).clamp(-1.0, 1.0);
    final turn = math.acos(cosTurn);
    if (turn < 1e-3) {
      out.add([...here]);
      continue;
    }
    final room = math.min(len3(sub3(here, prev)), len3(sub3(next, here))) * 0.48;
    final facing = v != null ? dot3(unit3(cross3(into, outOf)), v).abs() : 1.0;
    final bend = v != null ? math.max(radius, (margin * tube) / (0.7 * math.pow(math.max(0.05, facing), 2))) : radius;
    final cutV = math.min(bend * math.tan(turn / 2), room);
    final a = sub3(here, mul3(into, cutV));
    final b = add3(here, mul3(outOf, cutV));
    final count = math.max(2, (perArc * turn / (math.pi / 2)).ceil());
    for (var step = 0; step <= count; step++) {
      final t = step / count;
      final p0 = lerp3(a, here, t);
      final p1 = lerp3(here, b, t);
      out.add(lerp3(p0, p1, t));
    }
  }
  out.add([...points[points.length - 1]]);
  return out;
}

List<V3> spiral(Frame f, double s, double r0, double r1, double a0, double a1, [int steps = 28]) {
  return List.generate(steps + 1, (index) {
    final t = index / steps;
    return pointOf(f, s, r0 + (r1 - r0) * t, a0 + (a1 - a0) * t);
  });
}

double saddleStart(double r, double a, double angle) =>
    math.sqrt(math.max(0, r * r - a * a * math.pow(math.cos(angle), 2)));

Lathe saddleOf(Frame f, double a, Object start, double s1, Proj p, {int? steps}) {
  final v = viewOf(p);
  final l = lightOf(p);
  final n = steps ?? stepsFor(a, 24);
  double angle(int j) => (j / n) * TAU;
  double Function(double) from =
      start is double ? (t) => saddleStart(start, a, t) : (start as double Function(double));
  final low = List.generate(n, (j) => iso(pointOf(f, from(angle(j)), a, angle(j)), p));
  final high = List.generate(n, (j) => iso(pointOf(f, s1, a, angle(j)), p));
  final seen = <bool>[];
  final tones = <int>[];
  for (var j = 0; j < n; j++) {
    final normal = radialOf(f, angle(j) + TAU / n / 2);
    seen.add(dot3(normal, v) > 1e-6);
    tones.add(bandOf(dot3(normal, l)));
  }
  final buckets = List.generate(5, (_) => <String>[]);
  final fills = <String>[];
  final keys = List<int?>.generate(n, (j) => seen[j] ? tones[j] : null);
  for (final g in groupsOf(keys)) {
    final d = pathOf(oriented([...g.run.map((j) => low[j]), ...g.run.map((j) => high[j]).toList().reversed]), true);
    buckets[g.key!].add(d);
    fills.add(d);
  }
  final capSeen = dot3(f.a, v) > 1e-6;
  if (capSeen) {
    final d = pathOf(oriented(high), true);
    buckets[bandOf(dot3(f.a, l))].add(d);
    fills.add(d);
  }
  final front = _runsTrue(seen);
  final back = _runsTrue(seen.map((s) => !s).toList());
  final edges = <String>[];
  for (final run in front) {
    edges.add(pathOf(run.map((j) => low[j]).toList()));
    edges.add(pathOf([low[run[0]], high[run[0]]]));
    edges.add(pathOf([low[run[run.length - 1]], high[run[run.length - 1]]]));
  }
  for (final run in (capSeen ? back : front)) {
    edges.add(pathOf(run.map((j) => high[j]).toList()));
  }
  return Lathe(
    fill: fills.join(''),
    outline: edges.join(''),
    crease: capSeen ? front.map((run) => pathOf(run.map((j) => high[j]).toList())).join('') : '',
    top: buckets[4].join(''),
    shades: buckets.sublist(0, 4).map((x) => x.join('')).toList(),
  );
}

class Band {
  Band(this.s0, this.s1, this.profile, this.paths, this.outline, this.seam);
  final double s0, s1;
  final List<List<double>> profile;
  final Lathe paths;
  final String outline, seam;
}

class Bands {
  Bands(this.bands, this.radius, this.slope, this.steps, this.s0, this.s1);
  final List<Band> bands;
  final double Function(double) radius;
  final double Function(double) slope;
  final int steps;
  final double s0, s1;
}

Bands bandsOf(List<List<double>> profile, List<double> cuts, Frame f, Proj p,
    {double Function(double)? slope,
    double Function(double)? radius,
    int? steps,
    int rows = 6,
    String rims = 'none',
    String fill = 'auto',
    int samples = 72}) {
  final curve = profileCurve(profile, slope: slope, radius: radius);
  final s0 = curve.s0, s1 = curve.s1;
  final stops = <double>[
    s0,
    ...(cuts.toSet().where((s) => s > s0 + 1e-6 && s < s1 - 1e-6).toList()..sort()),
    s1,
  ];
  final most = [
    ...profile.map((pt) => pt[1]),
    ...stops.map((s) => curve.radius(s)),
  ].reduce(math.max);
  final n = steps ?? stepsFor(most, 32, 160, scaleOf(p));
  List<double> knot(double s, [bool soft = false]) =>
      soft ? [s, curve.radius(s), 1] : [s, curve.radius(s)];
  List<List<double>> meridianOf(double a, double b) => [
        knot(a),
        ...profile.where((pt) => pt[0] > a + 1e-9 && pt[0] < b - 1e-9).map((pt) => knot(pt[0], pt.length > 2 && pt[2] != 0)),
        knot(b),
      ];
  final bands = <Band>[];
  for (var index = 0; index < stops.length - 1; index++) {
    final a = stops[index], b = stops[index + 1];
    final meridian = meridianOf(a, b);
    final paths = lathe(meridian, f, p, steps: n, rims: rims, fill: fill, smooth: true);
    final seam = index < stops.length - 2 ? arcOf(f, b, curve.radius(b), p, slope: curve.slope(b)) : '';
    bands.add(Band(a, b, meridian, paths, paths.outline, seam));
  }
  return Bands(bands, curve.radius, curve.slope, n, s0, s1);
}

// 说明：lathe.mjs **已全量移植**——smoothRows（软/圆角表面平滑着色）、surfaceOf/silhouettePoints/silhouetteOf、
// curveRuns/curved（样条）、profileCurve/bandsOf、prismOf/saddleOf/stadium/rodOut/ribsOf/fillet/spiral、
// 以及全部路径工具（resample/cut/pointAlong/tangentAlong/fadeOf/facingOf…）。
// 未移植的只有“组装 SVG 字符串”那类（本端直接 Canvas 绘制，不需要）。签名与 JS 略有出入（如 fillet 的多余参数）。
