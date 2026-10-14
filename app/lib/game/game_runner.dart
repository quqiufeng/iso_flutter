// 游戏侧：在 Lua host 里跑**纯 Lua Sim**（game/sim 已打成 engine assets）；每帧取 state。
import 'dart:convert';

import '../lua_figures.dart';

class GameRunner {
  GameRunner._();
  static final GameRunner i = GameRunner._();
  bool get ready => LuaFigures.i.ready;

  /// 通用透传：在同一个 Lua 状态里跑一段 Lua。
  String eval(String code) => LuaFigures.i.eval(code);

  Future<void> ensure({int npcs = 0}) async {
    await LuaFigures.i.ensure();
    _new(npcs);
  }

  void reset({int npcs = 0}) => _new(npcs);

  void _new(int npcs) {
    final opts = npcs > 0 ? '{npcs=$npcs}' : '{}';
    LuaFigures.i.eval('_GAME = require("sim").new($opts) return "ok"');
  }

  void pauseNpcs(bool p) => LuaFigures.i.eval('_GAME:pauseNpcs($p) return "ok"');

  /// 同步按键 + 推进一帧（固定 dt）→ 返回世界状态（JSON → Map）。
  Map<String, dynamic> tick(Map<String, bool> keys, double dt) {
    final sb = StringBuffer();
    for (final k in const ['up', 'down', 'left', 'right']) {
      sb.write('_GAME:key("$k", ${keys[k] == true})\n');
    }
    sb.write('_GAME:step($dt)\nreturn _GAME:json()');
    return (jsonDecode(LuaFigures.i.eval(sb.toString())) as Map).cast<String, dynamic>();
  }
}
