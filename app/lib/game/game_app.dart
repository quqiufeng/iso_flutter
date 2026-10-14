// 兵线对推（左=我方防守 / 右=敌方进攻）：Flutter 渲染 + 纯 Lua Sim（battle.lua）。
// 1/2/3 选兵种 · 点地面(左半)布兵 · R 重开 · 打掉对方基地即胜。
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_lathe.dart';
import 'package:iso_engine/iso_render.dart';

import 'game_runner.dart';
import 'game_sprites.dart';
import 'iso.dart';

// Q版：按 hue 造一套彩色"线稿"调色板（浅底实体 + 深线）
Palette _tint(double hue) {
  ui.Color h(double l, [double s = 0.85]) => HSLColor.fromAHSL(1, hue, s, l).toColor();
  return Palette(
    page: h(0.97), paper: h(0.90), top: h(0.95),
    shades: [h(0.72), h(0.80), h(0.85), h(0.88)],
    hi: h(0.28), mid: h(0.42), lo: h(0.60), faint: h(0.76), lit: h(0.18),
    halo: h(0.45), haloOpacity: 0.28, dot: h(0.40), text: h(0.32), weight: 0.75,
  );
}

const Map<String, String> kTypes = {'1': 'sword', '2': 'archer', '3': 'mage'};
const Map<String, String> kTypeName = {'sword': '剑士', 'archer': '弓手', 'mage': '法师'};
// 敌方类型也用同一套 hue 上色
final Map<double, Palette> kPalCache = {};

Palette _pal(double hue) {
  final key = (hue / 10).round() * 10.0;
  return kPalCache[key] ??= _tint(key);
}

class GameApp extends StatefulWidget {
  const GameApp({super.key});
  @override
  State<GameApp> createState() => _GameState();
}

class _GameState extends State<GameApp> with SingleTickerProviderStateMixin {
  final IsoCam cam = IsoCam(scale: 34);
  final FocusNode _focus = FocusNode();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0, _fps = 0;
  String _sel = 'sword';
  Map<String, dynamic> _st = const {};

  @override
  void initState() {
    super.initState();
    GameRunner.i.ensure().then((_) {
      if (mounted) setState(() {});
    });
    Sprites.load().then((_) {
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    if (dt > 0) _fps = _fps == 0 ? 1 / dt : _fps * 0.92 + (1 / dt) * 0.08;
    if (GameRunner.i.ready) {
      _acc += dt;
      const step = 1 / 60;
      while (_acc >= step) {
        _st = GameRunner.i.step(step);
        _acc -= step;
      }
      // 相机对准战场中心
      final cols = (_st['cols'] as num?)?.toDouble() ?? 12;
      final rows = (_st['rows'] as num?)?.toDouble() ?? 3;
      cam.x += ((cols - 1) / 2 - cam.x) * 0.2;
      cam.y += ((rows - 1) / 2 - cam.y) * 0.2;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  int _laneOf(double gy) {
    final n = (_st['rows'] as num?)?.toInt() ?? 3;
    return gy.round().clamp(0, n - 1);
  }

  /// 相机：把战场铺满视口（启发式；可调）
  void _fitCam(BoxConstraints cons) {
    final rows = ((_st['rows'] as num?)?.toDouble() ?? 5);
    final cols = ((_st['cols'] as num?)?.toDouble() ?? 10);
    final span = (cols + rows); // 等距下横向跨度 ≈ (cols+rows)·0.707·k
    cam.scale = math.min(cons.maxWidth / (span * 1.45), cons.maxHeight / (span * 0.75));
    cam.cx = cons.maxWidth / 2;
    cam.cy = cons.maxHeight / 2 + cam.scale * 0.9;
    cam.x = (cols - 1) / 2;
    cam.y = (rows - 1) / 2;
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final k = e.logicalKey;
    for (final ent in kTypes.entries) {
      if (k.keyLabel == ent.key) _sel = ent.value;
    }
    if (k == LogicalKeyboardKey.keyR) GameRunner.i.reset();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: const Color(0xFFEFF0EC),
          body: Listener(
            onPointerDown: (e) {
              final g = cam.pick(e.localPosition.dx, e.localPosition.dy);
              // 仅左半场可布兵
              if (g[0] < ((_st['cols'] as num?)?.toDouble() ?? 12) / 2) {
                GameRunner.i.deploy(_laneOf(g[1]), _sel);
              }
              _focus.requestFocus();
            },
            child: LayoutBuilder(builder: (ctx, cons) {
              _fitCam(cons);
              return Stack(children: [
                CustomPaint(size: Size(cons.maxWidth, cons.maxHeight), painter: _Painter(cam, _st)),
                Positioned(left: 12, top: 10, child: _hud()),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _hud() {
    final res = (_st['resource'] as num?)?.toDouble() ?? 0;
    final wave = _st['wave'] ?? 0;
    final bases = _st['bases'] as Map?;
    int hp(String s) => ((bases?[s] as Map?)?['hp'] as num?)?.toInt() ?? 100;
    final over = _st['over'] == true;
    final winner = _st['winner'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('资源 ${res.toStringAsFixed(0)}   ·   波次 $wave   ·   ${_fps.toStringAsFixed(0)} fps',
          style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
      const SizedBox(height: 4),
      Row(children: [
        _pill('我方基地 ${hp('left')}', const Color(0xFF3E63DD)),
        const SizedBox(width: 8),
        _pill('敌方基地 ${hp('right')}', const Color(0xFFE5484D)),
      ]),
      const SizedBox(height: 6),
      Text('选兵：1 剑士${_sel == "sword" ? "✓" : ""}  2 弓手${_sel == "archer" ? "✓" : ""}  3 法师${_sel == "mage" ? "✓" : ""}   ·   点左半场布兵 · R 重开',
          style: const TextStyle(fontSize: 13, color: Color(0xFF777777))),
      if (over)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(winner == 'left' ? '🏆 我方胜利！' : '💀 基地失守…',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
    ]);
  }

  Widget _pill(String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20), border: Border.all(color: c, width: 1)),
        child: Text(s, style: TextStyle(fontSize: 13, color: c)),
      );
}

class _Painter extends CustomPainter {
  _Painter(this.cam, this.st);
  final IsoCam cam;
  final Map<String, dynamic> st;

  Proj get _p0 => Proj(origin: const [0, 0], scale: cam.scale, azimuth: 45, elevation: 30);

  @override
  void paint(Canvas canvas, Size size) {
    if (st.isEmpty) return;
    final rows = (st['rows'] as num?)?.toInt() ?? 3;
    final cols = (st['cols'] as num?)?.toInt() ?? 12;
    final p = cam.proj();

    // 地面：整块填充 + 网格线 + 敌方半场暖色
    List<double> sp(double x, double y) => cam.screen(x, y);
    ui.Path quad(double x0, double y0, double x1, double y1) {
      final a = sp(x0, y0), b = sp(x1, y0), c = sp(x1, y1), d = sp(x0, y1);
      return ui.Path()
        ..moveTo(a[0], a[1])
        ..lineTo(b[0], b[1])
        ..lineTo(c[0], c[1])
        ..lineTo(d[0], d[1])
        ..close();
    }


    canvas.drawPath(quad(cols / 2, 0, cols.toDouble(), rows.toDouble()), Paint()..color = const Color(0x1FD0873A));
    final line = Paint()
      ..color = const Color(0xFF9AA692)
      ..strokeWidth = 1.4;
    for (var c = 0; c <= cols; c++) {
      final a = sp(c.toDouble(), 0), b = sp(c.toDouble(), rows.toDouble());
      canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), line);
    }
    for (var r = 0; r <= rows; r++) {
      final a = sp(0, r.toDouble()), b = sp(cols.toDouble(), r.toDouble());
      canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), line);
    }

    // 基地（两端）
    final bases = st['bases'] as Map?;
    double hp(String s) => ((bases?[s] as Map?)?['hp'] as num?)?.toDouble() ?? 100;
    _base(canvas, p, rows, true, const Color(0xFF3E63DD), hp('left'));
    _base(canvas, p, rows, false, const Color(0xFFE5484D), hp('right'));

    // 单位：按深度排序
    final items = ((st['units'] as List?) ?? const [])
        .map((u) => (u as Map).cast<String, dynamic>())
        .toList()
      ..sort((a, b) => ((a['x'] as num) + (a['lane'] as num)).compareTo((b['x'] as num) + (b['lane'] as num)));
    for (final u in items) {
      _unit(canvas, u);
    }
  }


  void _base(Canvas c, Proj p, int rows, bool left, Color col, double hp) {
    final cols = (st['cols'] as num).toDouble();
    final x = left ? -0.45 : cols - 0.55;
    final top = cam.screen(x + 0.5, rows / 2);
    final im = Sprites.img[left ? 'castle_blue' : 'castle_red'];
    if (im != null) {
      final h = 3.4 * cam.scale, w = h * im.width / im.height;
      c.drawImageRect(
        im,
        Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
        Rect.fromLTWH(top[0] - w / 2, top[1] - h, w, h),
        Paint()..filterQuality = FilterQuality.medium..isAntiAlias = true,
      );
    } else {
      drawSolid(c, slabOf([x, rows / 2 - 0.7, 0.8, 1.4, 0.25], 0, 2.2, p, 4), _pal(left ? 220 : 0), tone: 'hi');
    }
    final bw = 66.0;
    final frac = (hp / 100).clamp(0.0, 1.0);
    c.drawRect(Rect.fromLTWH(top[0] - bw / 2, top[1] - 114, bw, 8), Paint()..color = const Color(0x22000000));
    c.drawRect(Rect.fromLTWH(top[0] - bw / 2, top[1] - 114, bw * frac, 8), Paint()..color = col);
  }

  void _unit(Canvas canvas, Map<String, dynamic> u) {
    final x = (u['x'] as num).toDouble(), lane = (u['lane'] as num).toDouble();
    final kind = (u['type'] as String?) ?? 'npc';
    final right = u['side'] == 'right';
    final s = cam.screen(x, lane);
    final im = Sprites.img[kind];
    final t = (st['tick'] as num? ?? 0) / 60.0;
    final moving = u['moving'] == true;
    final cd = (u['cd'] as num?)?.toDouble() ?? 0;
    final rate = (u['rate'] as num?)?.toDouble() ?? 1;
    final attacked = cd > rate * 0.82;               // cd 刚重置 = 刚攻击
    final phase = x * 1.7 + lane * 2.3;
    final bob = moving ? math.sin(t * 9 + phase) * cam.scale * 0.07 : 0.0;
    final lean = moving ? math.sin(t * 9 + phase) * 0.05 : (attacked ? (right ? 0.22 : -0.22) : 0.0);
    final lunge = attacked ? (right ? -0.3 : 0.3) * cam.scale : 0.0;
    if (im != null) {
      final h = 1.35 * cam.scale;
      final w = h * im.width / im.height;
      canvas.save();
      canvas.translate(s[0] + lunge, s[1] + bob);
      canvas.rotate(lean);
      if (right) canvas.scale(-1, 1); // 敌方朝左
      canvas.drawImageRect(
        im,
        Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
        Rect.fromLTWH(-w / 2, -h, w, h),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..isAntiAlias = true
          ..colorFilter = attacked ? const ColorFilter.mode(Color(0x66FFFFFF), BlendMode.srcATop) : null,
      );
      canvas.restore();
    } else {
      // 后备：矢量 Q版
      final pal = _pal((u['hue'] as num?)?.toDouble() ?? 200);
      final p0 = _p0;
      canvas.save();
      canvas.translate(s[0], s[1]);
      drawSolid(canvas, cylinder(0, 0, 0.27, 0, 0.7, p0, 12), pal, tone: 'hi');
      drawSolid(canvas, sphereOf([0, 0, 1.05], 0.32, p0), pal, tone: 'hi');
      canvas.restore();
    }
    // HP 条
    final hp = (u['hp'] as num).toDouble(), max = (u['max'] as num).toDouble();
    final frac = (hp / max).clamp(0.0, 1.0);
    if (frac < 0.999) {
      canvas.drawRect(Rect.fromLTWH(s[0] - 16, s[1] - 2.5 * cam.scale, 32, 4), Paint()..color = const Color(0x33000000));
      canvas.drawRect(Rect.fromLTWH(s[0] - 16, s[1] - 2.5 * cam.scale, 32 * frac, 4),
          Paint()..color = right ? const Color(0xFFE5484D) : const Color(0xFF3E63DD));
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
