// 天猫精灵 X1 —— **Dart 参考实现**（从 app/lib/main.dart 抽取；运行版在那边，注册为 `tmall-genie-dart`）
//
// 图 = 一个画图函数 (canvas, palette, lift, time)：用引擎的图元摆零件、按时间做动画。
// 依赖引擎包 `iso_engine`（iso_kit / iso_render）。与 Lua 版 example/tmall-genie/tmall_genie.lua **等价**。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_render.dart';

// —— 尺寸与零件参数（世界单位）——
const double W = 560, H = 660, FIGH = 560;
const double R = 42, RB = 46, Z0 = 0, BODY_TOP = 118, TOP_Z = BODY_TOP + 6;
const double MAX_LIFT = 44;

Proj _fit() => fitProjection(
      boxCorners([-RB, -RB, RB * 2, RB * 2, 0], -12, TOP_Z + MAX_LIFT + 6),
      W,
      FIGH,
      pad: 36,
      azimuth: 45,
    );

// burst(age, attack, decay)：attack 内线性上升到 1，之后指数衰减
double _burst(double age, double attack, double decay) {
  if (age < 0) return 0;
  if (age < attack) return age / attack;
  return math.exp(-(age - attack) / decay);
}

void tmallGenieDartFigure(ui.Canvas c, Palette pal, double lift, double time) {
  final p = _fit();
  final ly = MAX_LIFT * lift;
  double z(double v) => v + ly;
  // 唤醒设在"开盖开始"附近（同 kit 时间线），开盖后保持较亮
  final flash = _burst(math.max(0, time - 0.42), 0.08, 0.22) * 0.7 + lift * 0.5;

  // 光晕（软投影）：随开合变大、变淡、微微下移（"抬升"感）
  c.save();
  c.translate(0, 3 + 3 * lift);
  c.drawPath(
    parsePath(haloOf([-RB, -RB, RB * 2, RB * 2, RB], -12, 10, p)),
    Paint()
      ..color = pal.halo.withValues(alpha: pal.haloOpacity * (1 - 0.3 * lift))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 + 5 * lift),
  );
  c.restore();

  // 脚 / 底座 + 机身
  drawSolid(c, cylinder(0, 0, RB, -10, 6, p, 56), pal, tone: 'lo');
  drawSolid(c, cylinder(0, 0, RB - 3, -4, 6, p, 56), pal, tone: 'mid');
  drawSolid(c, cylinder(0, 0, R, Z0, BODY_TOP, p, 64, 1.0), pal, tone: 'hi');
  // 出音缝 + 侧弧
  drawLine(c, knurl(0, 0, R, 14, 76, 140, p, 0.25), pal, tone: 'lo');
  drawLine(c, sideArc(0, 0, R, 14, p, 48), pal, tone: 'lo');
  drawLine(c, sideArc(0, 0, R, 76, p, 48), pal, tone: 'lo');
  drawLine(c, sideArc(0, 0, R, 92, p, 48), pal, tone: 'faint');

  // 顶部组件（随 lift 抬升 + 轻微倾斜，围绕顶盖中心）
  final topC = iso([0, 0, z(TOP_Z)], p);
  c.save();
  c.translate(topC[0], topC[1]);
  c.rotate(0.11 * lift + 0.02 * math.sin(time * math.pi * 4));
  c.translate(-topC[0], -topC[1]);

  drawSolid(c, cylinder(0, 0, R, z(BODY_TOP), 6, p, 64, 0.6), pal, tone: 'mid');
  drawLine(c, ring(0, 0, R - 4, z(TOP_Z), p, 64), pal, tone: 'lo');
  // LED 环：唤醒瞬间 / 开盖时更亮
  drawLine(c, ring(0, 0, 26, z(TOP_Z), p, 64), pal, tone: (flash > 0.3 || lift > 0.5) ? 'lit' : 'hi');
  // 扩散波纹：随唤醒循环扩张，透明度衰减（两圈错相）
  for (var k = 0; k < 2; k++) {
    final wv = (time * 0.9 + k * 0.5) % 1.0;
    drawLine(c, ring(0, 0, 14 + 34 * wv, z(TOP_Z), p, 64), pal,
        tone: 'faint', alpha: (1 - wv) * (0.35 + 0.65 * lift));
  }
  // 6 麦：呼吸闪烁
  for (var i = 0; i < 6; i++) {
    final a = (math.pi * 2 * i) / 6;
    final breathe = 0.5 + 0.5 * math.sin(time * math.pi * 4 - i * math.pi / 3);
    drawDots(c, [iso([24 * math.cos(a), 24 * math.sin(a), z(TOP_Z)], p)], pal,
        size: 0.9 + 0.6 * breathe, tone: 'hi');
  }
  // 中央按键
  drawSolid(c, cylinder(0, 0, 7, z(TOP_Z), 2.4, p, 32), pal, tone: 'lo');
  c.restore();

  // 中文标题
  final tp = TextPainter(
    text: TextSpan(
        text: '天猫精灵 X1 智能音箱',
        style: TextStyle(color: pal.text, fontSize: 27, fontFamily: 'TsangerJinKai02')),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(W / 2 - tp.width / 2, H - 72));
}
