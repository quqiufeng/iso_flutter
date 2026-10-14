// iso_app 入口：ISO_EXPORT 有值 → 离屏导出 CLI；否则 → 交互窗口。
import 'dart:io';

import 'package:flutter/material.dart';

import 'export.dart';
import 'ui.dart';

void main() {
  final name = Platform.environment['ISO_EXPORT'];
  runApp((name != null && name.isNotEmpty) ? ExportApp(name) : const App());
}
