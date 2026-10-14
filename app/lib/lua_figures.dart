// Lua 图运行器：解包 Lua assets（引擎+图）→ 预编译 → 每帧调用 → 绘制指令 JSON → 用渲染层画。
// 通用：任何 `lib/lua/figures/<name>.lua` 都能画（不写死具体图）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_render.dart';
import 'package:iso_engine/lua_bridge.dart';

class LuaFigures {
  LuaFigures._();
  static final LuaFigures i = LuaFigures._();

  final Lua _lua = Lua();
  Directory? _tmp;
  final Set<String> names = {}; // figures/ 下的 .lua 图名
  String? _error; // 只记一次

  bool get ready => _tmp != null;

  /// 解包 assets 到临时目录并预编译所有图（只做一次）。
  Future<void> ensure() async {
    if (_tmp != null) return;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final dir = Directory.systemTemp.createTempSync('iso_lua_');
    for (final key in manifest.listAssets()) {
      if (!key.endsWith('.lua')) continue;
      final name = key.split('/').last;
      File('${dir.path}/$name').writeAsStringSync(await rootBundle.loadString(key));
      if (key.contains('/figures/')) names.add(name.substring(0, name.length - 4));
    }
    final list = names.map((n) => '"$n"').join(', ');
    _lua.run('package.path = "${dir.path}/?.lua;" .. package.path\n'
        '_FIGS = {}\n'
        'for _, n in ipairs({$list}) do _FIGS[n] = dofile("${dir.path}/" .. n .. ".lua") end\n'
        'return "ok"');
    _tmp = dir;
  }

  /// 跑一张 Lua 图（已编译）→ 绘制指令列表。
  List<dynamic> run(String name, double lift, double time) {
    if (_tmp == null) return const [];
    return jsonDecode(_lua.run('return _FIGS["$name"]($lift, $time)')) as List<dynamic>;
  }

  void reportError(Object e) {
    if (_error != null) return;
    _error = '$e';
    stderr.writeln('[iso] Lua 图出错：$e');
  }
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

/// 画一张 Lua 图（解析绘制指令 JSON → 渲染层）。
void drawLuaFigure(ui.Canvas c, Palette pal, String name, double lift, double time) {
  if (!LuaFigures.i.ready) return;
  final List<dynamic> ops;
  try {
    ops = LuaFigures.i.run(name, lift, time);
  } catch (e) {
    LuaFigures.i.reportError(e);
    return;
  }
  for (final op in ops) {
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
        drawSolid(c, _LuaSolid(m['fill'] as String, m['outline'] as String, m['crease'] as String,
            m['top'] as String, (m['shades'] as List).cast<String>(), m['bevel'] as String?), pal,
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
