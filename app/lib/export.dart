// 离屏导出（native 出图/出动画 CLI）：由环境变量驱动，渲染到 PNG。
// ISO_EXPORT(图名) ISO_OUT ISO_SS ISO_THEME ISO_LIFT ISO_MOTION ISO_FRAME ISO_N ISO_BATCH
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:iso_engine/iso_render.dart';

import 'figures.dart';

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

  double _easeOutBack(double c) {
    const s = 1.70158;
    final c3 = c - 1;
    return 1 + (s + 1) * c3 * c3 * c3 + s * c3 * c3;
  }

  double _liftFor(double t, Map<String, String> env) {
    if (env['ISO_MOTION'] == null) return double.tryParse(env['ISO_LIFT'] ?? '') ?? 0.0;
    if (t < 0.42) return 0;
    if (t < 0.60) return _easeOutBack((t - 0.42) / 0.18);
    if (t < 0.86) return 1;
    return 1 - _easeOutBack((t - 0.86) / 0.14);
  }

  Future<void> _run() async {
    final env = Platform.environment;
    await registerLuaFigures(); // 注册 Lua 图（发现 + 预编译）
    final fig = figures[widget.name];
    if (fig == null) {
      stderr.writeln('unknown figure: ${widget.name} (have: ${figures.keys.join(", ")})');
      exit(1);
    }
    final n = int.tryParse(env['ISO_N'] ?? '1') ?? 1;
    final ss = double.tryParse(env['ISO_SS'] ?? '2') ?? 2;
    final pal = env['ISO_THEME'] == 'dark' ? Palette.dark : Palette.light;
    final outBase = env['ISO_OUT'] ?? '/tmp/iso_out/export.png';

    Future<void> renderOne(int frame, String out) async {
      final t = n > 1 ? frame / n : 0.0;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(ss);
      c.drawRect(Rect.fromLTWH(0, 0, fig.w.toDouble(), fig.h.toDouble()), Paint()..color = pal.page);
      fig.paint(c, pal, _liftFor(t, env), t);
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
