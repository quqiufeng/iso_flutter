// 游戏侧：在 Lua host 里跑**纯 Lua Sim**（battle：兵线对推）；每帧取 state。
import 'dart:convert';

import '../lua_figures.dart';

class GameRunner {
  GameRunner._();
  static final GameRunner i = GameRunner._();
  bool get ready => LuaFigures.i.ready;

  String eval(String code) => LuaFigures.i.eval(code);

  Future<void> ensure() async {
    await LuaFigures.i.ensure();
    reset();
  }

  void reset() => LuaFigures.i.eval('_G = require("battle").new() return "ok"');
  void deploy(int lane, String type) => LuaFigures.i.eval('_G:deploy($lane, "$type") return "ok"');

  /// 推进一帧 → 返回世界状态（JSON → Map）。
  Map<String, dynamic> step(double dt) =>
      (jsonDecode(LuaFigures.i.eval('_G:step($dt) return _G:json()')) as Map).cast<String, dynamic>();
}
