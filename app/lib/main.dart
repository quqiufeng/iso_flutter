// iso_app 入口：ISO_EXPORT 有值 → 离屏导出 CLI；否则 → 交互窗口。
import 'dart:io';

import 'package:flutter/material.dart';

import 'export.dart';
import 'game/game_app.dart';
import 'ui.dart';

void main() {
  final env = Platform.environment;
  if (env['ISO_GAME'] != null) {
    runApp(const GameApp()); // M1 游戏垂直切片（等距地面+角色+WASD+点选）
    return;
  }
  final name = env['ISO_EXPORT'];
  runApp((name != null && name.isNotEmpty) ? ExportApp(name) : const App());
}
