// 对拍：Dart 引擎算一张图，打印路径串（与 lua/kit_parity.lua 逐字符对比）
import 'package:iso_engine/iso_kit.dart';
import 'package:iso_engine/iso_lathe.dart';

void main() {
  final p = fitProjection(boxCorners([-80, -80, 160, 160, 0], -10, 170), 560, 560, pad: 40, azimuth: 45);
  final fv = frameAlong([-45, -45, 0], [0, 0, 1]);
  final mer = <List<double>>[
    [0, 0],
    [0, 60, 1],
    [14, 70, 1],
    [46, 70, 1],
    [60, 60, 1],
    [60, 0],
  ];
  final s = lathe(mer, fv, p, bevel: 0.8);
  print('FILL=${s.fill}');
  print('LEN=${s.fill.length} SHADES=${s.shades.map((x) => x.length).join(",")} OUTLINE=${s.outline.length}');
  final c = cylinder(0, 0, 42, 0, 118, p, 64, 1.0);
  print('CYL=${c.fill.length} TOP=${c.top.length}');
}
