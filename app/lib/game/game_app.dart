// M1 游戏窗口：Flutter 渲染 + 纯 Lua Sim（game/sim，经 Lua host 驱动）。
// WASD 走 · 空格 pick · P 暂停NPC · R 重开。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_lathe.dart';
import 'package:iso_engine/iso_render.dart';

import 'game_runner.dart';
import 'iso.dart';

const int kGameNpcs = 60;

class GameApp extends StatefulWidget {
  const GameApp({super.key});
  @override
  State<GameApp> createState() => _GameState();
}

class _GameState extends State<GameApp> with SingleTickerProviderStateMixin {
  final IsoCam cam = IsoCam(scale: 11);
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  final Palette pal = Palette.light;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;
  bool _paused = false;
  Map<String, dynamic> _st = const {};

  @override
  void initState() {
    super.initState();
    GameRunner.i.ensure(npcs: kGameNpcs).then((_) {
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    if (GameRunner.i.ready) {
      _acc += dt;
      const step = 1 / 60;
      final keys = {
        'up': _keys.contains(LogicalKeyboardKey.keyW),
        'down': _keys.contains(LogicalKeyboardKey.keyS),
        'left': _keys.contains(LogicalKeyboardKey.keyA),
        'right': _keys.contains(LogicalKeyboardKey.keyD),
      };
      while (_acc >= step) {
        _st = GameRunner.i.tick(keys, step);
        _acc -= step;
      }
      final p = _st['player'];
      if (p is Map) {
        cam.x += ((p['x'] as num).toDouble() - cam.x) * 0.12;
        cam.y += ((p['y'] as num).toDouble() - cam.y) * 0.12;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyDownEvent) {
      _keys.add(k);
      if (k == LogicalKeyboardKey.space) GameRunner.i.eval('_GAME:act("pick") return "ok"');
      if (k == LogicalKeyboardKey.keyP) {
        _paused = !_paused;
        GameRunner.i.pauseNpcs(_paused);
      }
      if (k == LogicalKeyboardKey.keyR) GameRunner.i.reset(npcs: kGameNpcs);
    }
    if (e is KeyUpEvent) _keys.remove(k);
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
          body: LayoutBuilder(builder: (ctx, cons) {
            cam.cx = cons.maxWidth / 2;
            cam.cy = cons.maxHeight / 2;
            final n = (_st['npcs'] as List?)?.length ?? 0;
            return Stack(children: [
              CustomPaint(size: Size(cons.maxWidth, cons.maxHeight), painter: _GamePainter(cam, pal, _st)),
              Positioned(
                left: 12,
                top: 10,
                child: Text(
                  'WASD 走 · 空格 pick · P 暂停NPC(${_paused ? "停" : "动"}) · R 重开 · NPC $n',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter(this.cam, this.pal, this.st);
  final IsoCam cam;
  final Palette pal;
  final Map<String, dynamic> st;

  @override
  void paint(Canvas canvas, Size size) {
    final p = cam.proj();

    // 地面网格
    final gp = Paint()
      ..color = pal.faint.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = -40; i <= 40; i += 4) {
      final a = cam.screen(i.toDouble(), -40), b = cam.screen(i.toDouble(), 40);
      canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), gp);
      final c = cam.screen(-40, i.toDouble()), d = cam.screen(40, i.toDouble());
      canvas.drawLine(Offset(c[0], c[1]), Offset(d[0], d[1]), gp);
    }

    // 目标标记
    final g = st['goal'];
    if (g is Map) _goal(canvas, g.cast<String, dynamic>());

    // 物件 + NPC + 主角：按深度（x+y）排序
    final items = <Map<String, dynamic>>[];
    for (final o in (st['props'] as List? ?? const [])) {
      items.add({...(o as Map).cast<String, dynamic>(), '_t': 'prop'});
    }
    for (final o in (st['npcs'] as List? ?? const [])) {
      items.add({...(o as Map).cast<String, dynamic>(), '_t': 'npc'});
    }
    final pl = st['player'];
    if (pl is Map) items.add({...pl.cast<String, dynamic>(), '_t': 'player'});
    items.sort((a, b) =>
        ((a['x'] as num) + (a['y'] as num)).compareTo((b['x'] as num) + (b['y'] as num)));
    for (final e in items) {
      _entity(canvas, p, e);
    }
  }

  void _goal(Canvas c, Map<String, dynamic> g) {
    final s = cam.screen((g['x'] as num).toDouble(), (g['y'] as num).toDouble());
    final r = (g['r'] as num).toDouble() * cam.scale;
    c.drawOval(Rect.fromCenter(center: Offset(s[0], s[1]), width: r * 1.4, height: r * 0.7),
        Paint()
          ..color = const Color(0xFF33B36B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  void _entity(Canvas canvas, Proj p, Map<String, dynamic> e) {
    final x = (e['x'] as num).toDouble(), y = (e['y'] as num).toDouble();
    final r = (e['r'] as num).toDouble() * 0.9;
    final kind = (e['kind'] as String?) ?? '';
    final t = e['_t'];
    if (t == 'prop') {
      switch (kind) {
        case 'tree':
          drawSolid(canvas, cylinder(x, y, r * 0.35, 0, 10, p, 20), pal, tone: 'mid');
          drawSolid(canvas, sphereOf([x, y, 10 + r], r, p), pal, tone: 'hi');
          break;
        case 'box':
          drawSolid(canvas, slabOf([x - r, y - r, r * 2, r * 2, 1], 0, 6, p, 6), pal, tone: 'hi');
          break;
        default:
          drawSolid(canvas, cylinder(x, y, r * 0.3, 0, 3, p, 16), pal, tone: 'mid');
          drawSolid(canvas, slabOf([x - r, y - r, r * 2, r * 2, r * 0.8], 3, 2, p, 8), pal, tone: 'hi');
      }
    } else {
      final h = t == 'player' ? 5.5 : 4.0;
      drawSolid(canvas, cylinder(x, y, r * 0.5, 0, h, p, 18), pal, tone: t == 'player' ? 'hi' : 'mid');
      drawSolid(canvas, sphereOf([x, y, h + r * 0.35], r * 0.55, p), pal, tone: 'hi');
      if (e['paused'] == true) {
        final s = cam.screen(x, y);
        canvas.drawCircle(Offset(s[0], s[1] - h * cam.scale * 0.55), 2.5, Paint()..color = const Color(0xFF999999));
      }
    }
  }

  @override
  bool shouldRepaint(_GamePainter old) => true;
}
