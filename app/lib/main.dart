import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_lathe.dart';
import 'package:iso_engine/iso_render.dart';
import 'package:iso_engine/iso_tube.dart';
import 'package:iso_engine/lua_bridge.dart';

void main() {
  final name = Platform.environment['ISO_EXPORT'];
  if (name != null && name.isNotEmpty) {
    runApp(ExportApp(name));
    return;
  }
  runApp(const App());
}

// 天猫精灵：默认图 `tmall-genie` 走 Lua（lib/lua/figures/tmall_genie.lua）；
// Dart 参考版见下方的 tmallGenieDartFigure（注册为 `tmall-genie-dart`），两份等价。
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

// 对拍用：lathe / sphereOf / disc（与 /tmp/opencode/lathe_test 的 kit 参照同图）
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
  final fd = frameAlong([45, -45, 0], [0, 0, 1]);
  drawSolid(c, disc(0, 44, 32, fd, p), pal, tone: 'hi');
}

void tubeTestFigure(ui.Canvas c, Palette pal) {
  final p = fitProjection(boxCorners([-70, -70, 140, 140, 0], 0, 90), 560, 560, pad: 40, azimuth: 45);
  final path = <V3>[
    [-55, -30, 15],
    [-20, -30, 60],
    [20, -30, 60],
    [55, -30, 15],
  ];
  final pieces = tubePieces(path, (t) => 7, p, caps: true);
  for (final pc in pieces) {
    drawTube(c, pc, pal, tone: 'hi');
  }
}

// 天猫精灵（Dart 参考实现）——与 Lua 版 lib/lua/figures/tmall_genie.lua 等价
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

// ── Lua 图：跑 Lua(engine+figure) → 绘制指令 JSON → 画（渲染层复用）──
final Lua _lua = Lua();

// Lua 引擎与图都随包打成 assets（iso_engine 的 lib/lua/ + 本包的 lib/lua/figures/）；
// 运行时解包到临时目录供 require/dofile 使用 —— **自包含，不依赖开发机路径**。
Directory? _luaTmp;

Future<void> _ensureLua() async {
  if (_luaTmp != null) return;
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final dir = Directory.systemTemp.createTempSync('iso_lua_');
  for (final key in manifest.listAssets()) {
    if (!key.endsWith('.lua')) continue;
    File('${dir.path}/${key.split('/').last}').writeAsStringSync(await rootBundle.loadString(key));
  }
  _luaTmp = dir;
}

List<dynamic> _runLuaFigure(String name, double lift, double time) {
  final dir = _luaTmp!.path;
  final code = 'package.path = "$dir/?.lua;" .. package.path\n'
      'local f = dofile("$dir/$name.lua")\n'
      'return f($lift, $time)';
  return jsonDecode(_lua.run(code)) as List<dynamic>;
}

class _LuaSolid implements SolidPaths {
  _LuaSolid(this.fill, this.outline, this.crease, this.top, this.shades, this.bevel);
  @override
  final String fill, outline, crease, top;
  @override
  final List<String> shades;
  @override
  final String? bevel;
}

void tmallGenieLuaFigure(ui.Canvas c, Palette pal, double lift, double time) {
  if (_luaTmp == null) return; // assets 尚未解包好
  for (final op in _runLuaFigure('tmall_genie', lift, time)) {
    final m = (op as Map).cast<String, dynamic>();
    switch (m['k'] as String) {
      case 'halo':
        c.save();
        c.translate(0, (m['dy'] as num).toDouble());
        c.drawPath(
          parsePath(m['d'] as String),
          Paint()
            ..color = pal.halo.withValues(alpha: (pal.haloOpacity * (m['alpha'] as num).toDouble()).clamp(0.0, 1.0))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, (m['blur'] as num).toDouble()),
        );
        c.restore();
        break;
      case 'solid':
        drawSolid(
            c,
            _LuaSolid(m['fill'] as String, m['outline'] as String, m['crease'] as String, m['top'] as String,
                (m['shades'] as List).cast<String>(), m['bevel'] as String?),
            pal,
            tone: m['tone'] as String);
        break;
      case 'line':
        drawLine(c, m['d'] as String, pal, tone: m['tone'] as String, alpha: (m['alpha'] as num).toDouble());
        break;
      case 'dots':
        final pts = (m['pts'] as List).map((p) => (p as List).map((x) => (x as num).toDouble()).toList()).toList();
        drawDots(c, pts, pal, size: (m['size'] as num).toDouble(), tone: m['tone'] as String);
        break;
      case 'rotate':
        c.save();
        c.translate((m['cx'] as num).toDouble(), (m['cy'] as num).toDouble());
        c.rotate((m['a'] as num).toDouble());
        c.translate(-(m['cx'] as num).toDouble(), -(m['cy'] as num).toDouble());
        break;
      case 'restore':
        c.restore();
        break;
      case 'text':
        final tp = TextPainter(
          text: TextSpan(
              text: m['text'] as String,
              style: TextStyle(
                  color: pal.text, fontSize: (m['size'] as num).toDouble(), fontFamily: 'TsangerJinKai02')),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset((m['x'] as num).toDouble() - tp.width / 2, (m['y'] as num).toDouble()));
        break;
    }
  }
}

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
    _ensureLua().then((_) {
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
            // 左上角：主题切换
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

  @override
  void paint(Canvas canvas, Size size) {
    // 只用整数倍缩放，避免小数缩放糊线
    var s = math.min(size.width / W, size.height / H);
    s = s >= 3 ? 3 : (s >= 2 ? 2 : 1);
    final dst = Rect.fromLTWH((size.width - W * s) / 2, (size.height - H * s) / 2, W * s, H * s);

    // 离屏按 2× 渲染（超采样）再缩放显示 → 细线锐利、抗锯齿细腻（等价 gif 的 1120×1320）
    const ss = 2.0;
    final rec = ui.PictureRecorder();
    final off = Canvas(rec)..scale(ss);
    tmallGenieLuaFigure(off, pal, lift, time);
    final img = rec.endRecording().toImageSync((W * ss).round(), (H * ss).round());
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, W * ss, H * ss),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
    img.dispose();
  }

  @override
  bool shouldRepaint(_Painter old) => old.lift != lift || old.time != time;
}

// ── 离屏导出（native 出图/出动画 CLI）──
class Figure {
  const Figure(this.w, this.h, this.paint);
  final int w, h;
  final void Function(Canvas, Palette, double lift, double time) paint;
}

final Map<String, Figure> _figures = {
  'tmall-genie': Figure(W.toInt(), H.toInt(), (c, pal, lift, time) => tmallGenieLuaFigure(c, pal, lift, time)),
  'tmall-genie-dart': Figure(W.toInt(), H.toInt(), (c, pal, lift, time) => tmallGenieDartFigure(c, pal, lift, time)),
  'lathe': Figure(560, 560, (c, pal, lift, time) => latheTestFigure(c, pal)),
  'tube': Figure(560, 560, (c, pal, lift, time) => tubeTestFigure(c, pal)),
};

class ExportApp extends StatefulWidget {
  const ExportApp(this.name, {super.key});
  final String name;
  @override
  State<ExportApp> createState() => _ExportState();
}

class _ExportState extends State<ExportApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final env = Platform.environment;
    await _ensureLua();
    final fig = _figures[widget.name];
    if (fig == null) {
      stderr.writeln('unknown figure: ${widget.name} (have: ${_figures.keys.join(", ")})');
      exit(1);
    }
    final n = int.tryParse(env['ISO_N'] ?? '1') ?? 1;
    final ss = double.tryParse(env['ISO_SS'] ?? '2') ?? 2;
    final pal = env['ISO_THEME'] == 'dark' ? Palette.dark : Palette.light;
    final outBase = env['ISO_OUT'] ?? '/tmp/opencode/iso_export.png';

    double easeOutBack(double c) {
      const s = 1.70158;
      final c3 = c - 1;
      return 1 + (s + 1) * c3 * c3 * c3 + s * c3 * c3;
    }

    double liftFor(double t) {
      if (env['ISO_MOTION'] == null) return double.tryParse(env['ISO_LIFT'] ?? '') ?? 0.0;
      if (t < 0.42) return 0;
      if (t < 0.60) return easeOutBack((t - 0.42) / 0.18);
      if (t < 0.86) return 1;
      return 1 - easeOutBack((t - 0.86) / 0.14);
    }

    Future<void> renderOne(int frame, String out) async {
      final t = n > 1 ? frame / n : 0.0;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(ss);
      c.drawRect(Rect.fromLTWH(0, 0, fig.w.toDouble(), fig.h.toDouble()), Paint()..color = pal.page);
      fig.paint(c, pal, liftFor(t), t);
      final img = await rec.endRecording().toImage((fig.w * ss).round(), (fig.h * ss).round());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
      img.dispose();
    }

    if (env['ISO_BATCH'] != null && n > 1) {
      Directory(outBase).createSync(recursive: true);
      for (var i = 0; i < n; i++) {
        await renderOne(i, '$outBase/f${i.toString().padLeft(4, '0')}.png');
      }
      stdout.writeln('wrote $n frames -> $outBase');
      exit(0);
    }
    await renderOne(int.tryParse(env['ISO_FRAME'] ?? '0') ?? 0, outBase);
    stdout.writeln('wrote $outBase');
    exit(0);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
