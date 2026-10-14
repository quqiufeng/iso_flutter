// M1 游戏窗口：固定步长循环 + 输入（WASD/鼠标点选）+ 等距渲染（复用渲染层）。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_render.dart';

import 'iso.dart';
import 'world.dart';

class GameApp extends StatefulWidget {
  const GameApp({super.key});
  @override
  State<GameApp> createState() => _GameState();
}

class _GameState extends State<GameApp> with SingleTickerProviderStateMixin {
  final World world = World();
  final Camera cam = Camera(scale: 12);
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  final Palette pal = Palette.light;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      final dt = (now - _last).inMicroseconds / 1e6;
      _last = now;
      _acc += dt.clamp(0, 0.1);

      // 输入 → 期望速度
      double vx = 0, vy = 0;
      if (_keys.contains(LogicalKeyboardKey.keyW)) vy -= 1;
      if (_keys.contains(LogicalKeyboardKey.keyS)) vy += 1;
      if (_keys.contains(LogicalKeyboardKey.keyA)) vx -= 1;
      if (_keys.contains(LogicalKeyboardKey.keyD)) vx += 1;
      if (vx != 0 || vy != 0) {
        final l = math.sqrt(vx * vx + vy * vy);
        world.moveTo = null;
        world.player.vx = vx / l * 9;
        world.player.vy = vy / l * 9;
      }

      // 定点更新
      const step = 1 / 60;
      while (_acc >= step) {
        world.update(step);
        _acc -= step;
      }

      // 相机跟随
      cam.x += (world.player.x - cam.x) * 0.15;
      cam.y += (world.player.y - cam.y) * 0.15;

      setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyDownEvent) _keys.add(k);
    if (e is KeyUpEvent) _keys.remove(k);
    if (e is KeyDownEvent && k == LogicalKeyboardKey.space) {
      // 选中最近的物
      Entity? best;
      double bd = double.infinity;
      for (final p in world.props) {
        final dx = p.x - world.player.x, dy = p.y - world.player.y;
        final d = dx * dx + dy * dy;
        if (d < bd) {
          bd = d;
          best = p;
        }
      }
      for (final p in world.props) {
        p.selected = identical(p, best);
      }
    }
  }

  Entity? _pickAt(double gx, double gy) {
    for (final p in world.props) {
      if (hit([p.x, p.y], [gx, gy], p.r)) return p;
    }
    return null;
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
          backgroundColor: pal.page,
          body: Listener(
            onPointerDown: (e) {
              final g = cam.pick(e.localPosition.dx, e.localPosition.dy);
              final hitE = _pickAt(g[0], g[1]);
              for (final p in world.props) {
                p.selected = identical(p, hitE);
              }
              if (hitE == null) world.moveTo = g; // 点空地 → 走过去
              _focus.requestFocus();
            },
            child: LayoutBuilder(builder: (ctx, cons) {
              cam.cx = cons.maxWidth / 2;
              cam.cy = cons.maxHeight / 2;
              return CustomPaint(painter: _GamePainter(world, cam, pal));
            }),
          ),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter(this.world, this.cam, this.pal);
  final World world;
  final Camera cam;
  final Palette pal;

  @override
  void paint(Canvas canvas, Size size) {
    final p = cam.proj();

    // 地面网格（z=0）
    final gp = Paint()
      ..color = pal.faint.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    const range = 24, stepG = 4;
    for (var i = -range; i <= range; i += stepG) {
      final a = cam.screen(i.toDouble(), -range.toDouble());
      final b = cam.screen(i.toDouble(), range.toDouble());
      canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), gp);
      final c = cam.screen(-range.toDouble(), i.toDouble());
      final d = cam.screen(range.toDouble(), i.toDouble());
      canvas.drawLine(Offset(c[0], c[1]), Offset(d[0], d[1]), gp);
    }

    // painter's order：从远到近
    final ents = world.all.toList()..sort((a, b) => a.depth.compareTo(b.depth));
    for (final e in ents) {
      _drawEntity(canvas, p, e);
    }
  }

  void _drawEntity(Canvas canvas, Proj p, Entity e) {
    final r = e.r * 0.9;
    switch (e.kind) {
      case 'tree':
        drawSolid(canvas, cylinder(e.x, e.y, r * 0.35, 0, e.h, p, 24), pal, tone: 'mid');
        drawSolid(canvas, sphereOf([e.x, e.y, e.h + r], r, p), pal, tone: 'hi');
        break;
      case 'box':
        drawSolid(canvas, slabOf([e.x - r, e.y - r, r * 2, r * 2, 1], 0, e.h, p, 6), pal, tone: 'hi');
        break;
      case 'mushroom':
        drawSolid(canvas, cylinder(e.x, e.y, r * 0.3, 0, e.h * 0.6, p, 20), pal, tone: 'mid');
        drawSolid(canvas, slabOf([e.x - r, e.y - r, r * 2, r * 2, r * 0.8], e.h * 0.6, 2, p, 8), pal, tone: 'hi');
        break;
      case 'player':
        drawSolid(canvas, cylinder(e.x, e.y, r * 0.5, 0, e.h, p, 24), pal, tone: 'hi');
        drawSolid(canvas, sphereOf([e.x, e.y, e.h + r * 0.35], r * 0.55, p), pal, tone: 'hi');
        break;
    }
    if (e.selected) {
      // 选中：地面光环
      final c = cam.screen(e.x, e.y);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c[0], c[1]), width: e.r * cam.scale * 1.4, height: e.r * cam.scale * 0.7),
        Paint()
          ..color = const Color(0xFFFF7A2F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_GamePainter old) => true;
}
