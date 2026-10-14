// 交互窗口：显示图 + 手势（拖拽开盖 / 点击切换）+ 主题切换。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:iso_engine/iso_render.dart';

import 'figures.dart';

const String kDefaultFigure = 'tmall-genie';

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _S();
}

class _S extends State<App> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  double _lift = 0, _target = 0, _vel = 0;
  bool _drag = false;
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    var last = Duration.zero;
    _ticker = createTicker((now) {
      final dt = (now - last).inMicroseconds / 1e6;
      last = now;
      const k = 64.0, d = 14.2;
      final h = dt.clamp(0.0, 1 / 30);
      setState(() {
        _t += dt;
        if (!_drag) {
          _vel += (k * (_target - _lift) - d * _vel) * h;
          _lift += _vel * h;
        }
      });
    })..start();
    registerLuaFigures().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _dark ? const Color(0xFF0B0B0B) : const Color(0xFFF2F2EF),
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _target = _target > 0.5 ? 0 : 1),
              onVerticalDragStart: (_) => setState(() => _drag = true),
              onVerticalDragUpdate: (e) => setState(() {
                _drag = true;
                _vel = 0;
                _lift = (_lift - e.delta.dy / 140).clamp(0.0, 1.0);
              }),
              onVerticalDragEnd: (_) => setState(() {
                _drag = false;
                _target = _lift > 0.45 ? 1 : 0;
              }),
              child: SizedBox.expand(
                child: CustomPaint(painter: _Painter(_lift, _t, _dark ? Palette.dark : Palette.light)),
              ),
            ),
            // 左上角：点击切 dark/light
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _dark = !_dark),
                child: const SizedBox(width: 64, height: 64),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.lift, this.time, this.pal);
  final double lift, time;
  final Palette pal;

  // 渲染结果缓存：图/lift/time/主题未变则复用（避免每帧重渲 + 纹理 churn）
  static String? _cacheKey;
  static ui.Image? _cacheImg;

  @override
  void paint(Canvas canvas, Size size) {
    final fig = figures[kDefaultFigure] ?? figures['tmall-genie-dart'];
    if (fig == null) return;
    final double w = fig.w.toDouble(), h = fig.h.toDouble();

    // 只用整数倍缩放，避免小数缩放糊线
    var s = math.min(size.width / w, size.height / h);
    s = s >= 3 ? 3 : (s >= 2 ? 2 : 1);
    final dst = Rect.fromLTWH((size.width - w * s) / 2, (size.height - h * s) / 2, w * s, h * s);

    // 离屏 2× 超采样，再缩放显示 → 细线锐利、抗锯齿细腻
    const ss = 2.0;
    final key = '$kDefaultFigure|${lift.toStringAsFixed(4)}:${time.toStringAsFixed(4)}:${pal == Palette.dark}';
    if (key != _cacheKey || _cacheImg == null) {
      final rec = ui.PictureRecorder();
      final off = Canvas(rec)..scale(ss);
      fig.paint(off, pal, lift, time);
      final img = rec.endRecording().toImageSync((w * ss).round(), (h * ss).round());
      _cacheImg?.dispose();
      _cacheImg = img;
      _cacheKey = key;
    }
    canvas.drawImageRect(
      _cacheImg!,
      Rect.fromLTWH(0, 0, w * ss, h * ss),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_Painter old) => old.lift != lift || old.time != time;
}
