// 图：定义（摆零件 + 动画）+ 注册表。
// 图可用 Dart 写（本文件）或 Lua 写（lib/lua/figures/*.lua，由 registerLuaFigures 自动注册）。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_lathe.dart';
import 'package:iso_engine/iso_render.dart';
import 'package:iso_engine/iso_tube.dart';

import 'lua_figures.dart';

class Figure {
  const Figure(this.w, this.h, this.paint);
  final int w, h;
  final void Function(Canvas, Palette, double lift, double time) paint;
}

// ══════════ 天猫精灵 X1（Dart 参考实现；默认图 tmall-genie 是它的 Lua 版）══════════
const double _GW = 560, _GH = 660, _FIGH = 560;
const double _R = 42, _RB = 46, _BODY_TOP = 118, _TOP_Z = _BODY_TOP + 6, _MAX_LIFT = 44;

Proj _genieFit() => fitProjection(
      boxCorners([-_RB, -_RB, _RB * 2, _RB * 2, 0], -12, _TOP_Z + _MAX_LIFT + 6),
      _GW,
      _FIGH,
      pad: 36,
      azimuth: 45,
    );

double _burst(double age, double attack, double decay) {
  if (age < 0) return 0;
  if (age < attack) return age / attack;
  return math.exp(-(age - attack) / decay);
}

void tmallGenieDartFigure(ui.Canvas c, Palette pal, double lift, double time) {
  final p = _genieFit();
  final ly = _MAX_LIFT * lift;
  double z(double v) => v + ly;
  final flash = _burst(math.max(0, time - 0.42), 0.08, 0.22) * 0.7 + lift * 0.5;

  c.save();
  c.translate(0, 3 + 3 * lift);
  c.drawPath(
    parsePath(haloOf([-_RB, -_RB, _RB * 2, _RB * 2, _RB], -12, 10, p)),
    Paint()
      ..color = pal.halo.withValues(alpha: pal.haloOpacity * (1 - 0.3 * lift))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 + 5 * lift),
  );
  c.restore();

  drawSolid(c, cylinder(0, 0, _RB, -10, 6, p, 56), pal, tone: 'lo');
  drawSolid(c, cylinder(0, 0, _RB - 3, -4, 6, p, 56), pal, tone: 'mid');
  drawSolid(c, cylinder(0, 0, _R, 0, _BODY_TOP, p, 64, 1.0), pal, tone: 'hi');
  drawLine(c, knurl(0, 0, _R, 14, 76, 140, p, 0.25), pal, tone: 'lo');
  drawLine(c, sideArc(0, 0, _R, 14, p, 48), pal, tone: 'lo');
  drawLine(c, sideArc(0, 0, _R, 76, p, 48), pal, tone: 'lo');
  drawLine(c, sideArc(0, 0, _R, 92, p, 48), pal, tone: 'faint');

  final topC = iso([0, 0, z(_TOP_Z)], p);
  c.save();
  c.translate(topC[0], topC[1]);
  c.rotate(0.11 * lift + 0.02 * math.sin(time * math.pi * 4));
  c.translate(-topC[0], -topC[1]);

  drawSolid(c, cylinder(0, 0, _R, z(_BODY_TOP), 6, p, 64, 0.6), pal, tone: 'mid');
  drawLine(c, ring(0, 0, _R - 4, z(_TOP_Z), p, 64), pal, tone: 'lo');
  drawLine(c, ring(0, 0, 26, z(_TOP_Z), p, 64), pal, tone: (flash > 0.3 || lift > 0.5) ? 'lit' : 'hi');
  for (var k = 0; k < 2; k++) {
    final wv = (time * 0.9 + k * 0.5) % 1.0;
    drawLine(c, ring(0, 0, 14 + 34 * wv, z(_TOP_Z), p, 64), pal,
        tone: 'faint', alpha: (1 - wv) * (0.35 + 0.65 * lift));
  }
  for (var i = 0; i < 6; i++) {
    final a = (math.pi * 2 * i) / 6;
    final breathe = 0.5 + 0.5 * math.sin(time * math.pi * 4 - i * math.pi / 3);
    drawDots(c, [iso([24 * math.cos(a), 24 * math.sin(a), z(_TOP_Z)], p)], pal,
        size: 0.9 + 0.6 * breathe, tone: 'hi');
  }
  drawSolid(c, cylinder(0, 0, 7, z(_TOP_Z), 2.4, p, 32), pal, tone: 'lo');
  c.restore();

  final tp = TextPainter(
    text: TextSpan(
        text: '天猫精灵 X1 智能音箱',
        style: TextStyle(color: pal.text, fontSize: 27, fontFamily: 'TsangerJinKai02')),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(_GW / 2 - tp.width / 2, _GH - 72));
}

// ══════════ 引擎测试图（lathe / tube，对拍用）══════════
void latheTestFigure(ui.Canvas c, Palette pal) {
  final p = fitProjection(boxCorners([-80, -80, 160, 160, 0], -10, 170), 560, 560, pad: 40, azimuth: 45);
  final fv = frameAlong([-45, -45, 0], [0, 0, 1]);
  final meridian = <List<double>>[
    [0, 0],
    [0, 60, 1],
    [14, 70, 1],
    [46, 70, 1],
    [60, 60, 1],
    [60, 0],
  ];
  drawSolid(c, lathe(meridian, fv, p, bevel: 0.8), pal, tone: 'hi');
  drawSolid(c, sphereOf([45, 45, 42], 36, p), pal, tone: 'hi');
  drawSolid(c, disc(0, 44, 32, frameAlong([45, -45, 0], [0, 0, 1]), p), pal, tone: 'hi');
}

void tubeTestFigure(ui.Canvas c, Palette pal) {
  final p = fitProjection(boxCorners([-70, -70, 140, 140, 0], 0, 90), 560, 560, pad: 40, azimuth: 45);
  final path = <V3>[
    [-55, -30, 15],
    [-20, -30, 60],
    [20, -30, 60],
    [55, -30, 15],
  ];
  for (final pc in tubePieces(path, (t) => 7, p, caps: true)) {
    drawTube(c, pc, pal, tone: 'hi');
  }
}

// ══════════ 注册表 ══════════
final Map<String, Figure> figures = {
  'tmall-genie-dart': const Figure(560, 660, _geniePaint),
  'lathe': Figure(560, 560, (c, p, l, t) => latheTestFigure(c, p)),
  'tube': Figure(560, 560, (c, p, l, t) => tubeTestFigure(c, p)),
};

void _geniePaint(Canvas c, Palette p, double l, double t) => tmallGenieDartFigure(c, p, l, t);

/// 把 assets 里发现的 Lua 图（lib/lua/figures/*.lua）自动注册进来（图名 = 文件名）。
Future<void> registerLuaFigures() async {
  await LuaFigures.i.ensure();
  for (final n in LuaFigures.i.names) {
    figures[n] = Figure(560, 660, (c, p, l, t) => drawLuaFigure(c, p, n, l, t));
  }
}
