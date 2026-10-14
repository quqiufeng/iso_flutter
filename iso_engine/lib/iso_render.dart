// Dart 移植：anatomy 的 SVG/CSS「线稿」样式 → Flutter Canvas
// 原项目：https://github.com/wheresryan22/anatomy (MIT)
import 'dart:ui' as ui;

import 'iso_kit.dart';
import 'iso_tube.dart';

class Palette {
  const Palette({
    required this.page,
    required this.paper,
    required this.top,
    required this.shades,
    required this.hi,
    required this.mid,
    required this.lo,
    required this.faint,
    required this.lit,
    required this.halo,
    required this.haloOpacity,
    required this.dot,
    required this.text,
    required this.weight,
  });
  final ui.Color page, paper, top, lit, halo, dot, text, hi, mid, lo, faint;
  final List<ui.Color> shades;
  final double haloOpacity, weight;

  ui.Color tone(String name) => switch (name) {
        'hi' => hi,
        'mid' => mid,
        'lo' => lo,
        'faint' => faint,
        'lit' => lit,
        _ => lo,
      };

  static const dark = Palette(
    page: ui.Color(0xFF0B0B0B),
    paper: ui.Color(0xFF131313),
    top: ui.Color(0xFF1C1C1C),
    shades: [ui.Color(0xFF0F0F0F), ui.Color(0xFF121212), ui.Color(0xFF151515), ui.Color(0xFF181818)],
    hi: ui.Color(0xFFD4D4D4),
    mid: ui.Color(0xFF6A6A6A),
    lo: ui.Color(0xFF3E3E3E),
    faint: ui.Color(0xFF2A2A2A),
    lit: ui.Color(0xFFFFFFFF),
    halo: ui.Color(0xFF050505),
    haloOpacity: 0.9,
    dot: ui.Color(0xFFE6E6E6),
    text: ui.Color(0xFFA3A3A3),
    weight: 0.75,
  );

  static const light = Palette(
    page: ui.Color(0xFFF2F2EF),
    paper: ui.Color(0xFFFBFBFA),
    top: ui.Color(0xFFFFFFFF),
    shades: [ui.Color(0xFFDCDCD9), ui.Color(0xFFE5E5E2), ui.Color(0xFFEDEDEA), ui.Color(0xFFF4F4F1)],
    hi: ui.Color(0xFF26262A),
    mid: ui.Color(0xFF8A8A8F),
    lo: ui.Color(0xFFB4B4B8),
    faint: ui.Color(0xFFD4D4D6),
    lit: ui.Color(0xFF000000),
    halo: ui.Color(0xFF8A8A80),
    haloOpacity: 0.32,
    dot: ui.Color(0xFF3A3A3E),
    text: ui.Color(0xFF57575A),
    weight: 0.75,
  );
}

final _pathRe = RegExp(r'([MLZmlz])([^MLZmlz]*)');

// d 字符串 → ui.Path 的缓存（同串复用，避免每帧重复解析几何）
final Map<String, ui.Path> _pathCache = {};

ui.Path parsePath(String d) {
  final hit = _pathCache[d];
  if (hit != null) return hit;
  final p = _parsePath(d);
  if (_pathCache.length > 4096) _pathCache.clear();
  _pathCache[d] = p;
  return p;
}

ui.Path _parsePath(String d) {
  final path = ui.Path();
  for (final m in _pathRe.allMatches(d)) {
    final cmd = m.group(1)!;
    final nums = m
        .group(2)!
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map(double.parse)
        .toList();
    if (cmd == 'M' || cmd == 'm') {
      for (var i = 0; i + 1 < nums.length; i += 2) {
        path.moveTo(nums[i], nums[i + 1]);
      }
    } else if (cmd == 'L' || cmd == 'l') {
      for (var i = 0; i + 1 < nums.length; i += 2) {
        path.lineTo(nums[i], nums[i + 1]);
      }
    } else {
      path.close();
    }
  }
  return path;
}

bool _notEmpty(String? d) => d != null && d.isNotEmpty;

// → solidSvg：底色填充 + 4 档阴影 + 顶面 + 折线 + 边线（+ 可选光晕）
void drawSolid(
  ui.Canvas canvas,
  SolidPaths p,
  Palette pal, {
  String tone = 'hi',
  String crease = 'faint',
  bool halo = false,
  bool lit = false,
  bool flat = false,
  List<dynamic> inner = const [],
}) {
  if (halo) {
    canvas.save();
    canvas.translate(0, 3);
    canvas.drawPath(
      parsePath(p.fill),
      ui.Paint()
        ..color = pal.halo.withValues(alpha: pal.haloOpacity)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
    );
    canvas.restore();
  }
  canvas.drawPath(parsePath(p.fill), ui.Paint()..color = lit ? pal.shades[2] : pal.paper);
  if (!flat) {
    for (var i = 0; i < p.shades.length; i++) {
      if (p.shades[i].isEmpty) continue;
      canvas.drawPath(parsePath(p.shades[i]), ui.Paint()..color = lit ? pal.shades[3] : pal.shades[i]);
    }
    canvas.drawPath(parsePath(p.top), ui.Paint()..color = pal.top);
  }
  final stroke = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = pal.weight
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  if (crease != 'none' && _notEmpty(p.crease)) {
    canvas.drawPath(parsePath(p.crease), stroke..color = pal.tone(crease));
  }
  if (crease != 'none' && _notEmpty(p.bevel)) {
    canvas.drawPath(parsePath(p.bevel!), stroke..color = pal.tone(crease));
  }
  canvas.drawPath(parsePath(p.outline), stroke..color = tone == 'lit' ? pal.lit : pal.tone(tone));
}

// → lineSvg（细描边，默认 lo；alpha 便于做衰减/呼吸）
void drawLine(ui.Canvas canvas, String d, Palette pal, {String tone = 'lo', double alpha = 1, double width = 0}) {
  if (d.isEmpty || alpha <= 0.01) return;
  canvas.drawPath(
    parsePath(d),
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = width > 0 ? width : pal.weight
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..color = (tone == 'lit' ? pal.lit : pal.tone(tone)).withValues(alpha: alpha.clamp(0.0, 1.0)),
  );
}

// → dotsSvg（圆点 + 各 tone 的透明度）
void drawDots(ui.Canvas canvas, List<List<double>> points, Palette pal, {double size = 0.5, String tone = 'mid'}) {
  final opacity = switch (tone) {
        'hi' => 0.85,
        'mid' => 0.45,
        'lo' => 0.22,
        'faint' => 0.12,
        _ => 0.32,
      };
  final paint = ui.Paint()..color = pal.dot.withValues(alpha: opacity);
  for (final p in points) {
    canvas.drawCircle(ui.Offset(p[0], p[1]), size, paint);
  }
}

// → tubeSvg：tb-body(shade-2) + tb-shine(top) + tb-shade(shade-0) + tb-ring(lo) + iso-line tb-edge(tone)
void drawTube(ui.Canvas canvas, TubePiece piece, Palette pal, {String tone = 'hi'}) {
  canvas.drawPath(parsePath(piece.body), ui.Paint()..color = pal.shades[2]);
  if (piece.wide) {
    canvas.drawPath(parsePath(piece.shine), ui.Paint()..color = pal.top);
    canvas.drawPath(parsePath(piece.shade), ui.Paint()..color = pal.shades[0]);
  }
  final ringPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 0.45
    ..strokeCap = ui.StrokeCap.butt
    ..strokeJoin = ui.StrokeJoin.round;
  for (final ring in piece.rings) {
    if (ring.alpha <= 0) continue;
    ringPaint.color = pal.tone(piece.ringTone).withValues(alpha: ring.alpha.clamp(0.0, 1.0));
    canvas.drawPath(parsePath(ring.d), ringPaint);
  }
  if (piece.edges.isNotEmpty) {
    canvas.drawPath(
      parsePath(piece.edges),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = pal.weight
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..color = tone == 'lit' ? pal.lit : pal.tone(tone),
    );
  }
}

