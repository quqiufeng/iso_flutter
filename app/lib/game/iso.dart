// 等距世界：地面(z=0) ↔ 屏幕 互转（拾取）+ 相机。
import 'package:iso_engine/iso_kit.dart';

const double _sinA = 0.70710678, _cosA = 0.70710678, _sinE = 0.5; // azimuth 45 / elev 30

class IsoCam {
  IsoCam({this.x = 0, this.y = 0, this.scale = 2.0, this.cx = 0, this.cy = 0});
  double x, y; // 相机对准的地面点
  double scale; // 世界单位 → 屏幕像素
  double cx, cy; // 视口中心（屏幕）

  /// 地面点 → 屏幕
  List<double> screen(double wx, double wy) {
    final k = scale;
    return [
      cx + (wx * _sinA - wy * _cosA) * k - (x * _sinA - y * _cosA) * k,
      cy + ((wx * _cosA + wy * _sinA) * _sinE) * k - ((x * _cosA + y * _sinA) * _sinE) * k,
    ];
  }

  /// 屏幕点 → 地面点（逆投影，仅 z=0 平面）
  List<double> pick(double sx, double sy) {
    final k = scale;
    final u = (sx - cx) / k + (x * _sinA - y * _cosA);
    final v = (sy - cy) / (k * _sinE) + (x * _cosA + y * _sinA);
    return [u * _sinA + v * _cosA, -u * _cosA + v * _sinA];
  }

  /// 供引擎绘制用的投影（世界→屏幕，含相机）
  Proj proj() => Proj(
        origin: [
          cx - (x * _sinA - y * _cosA) * scale,
          cy - ((x * _cosA + y * _sinA) * _sinE) * scale,
        ],
        scale: scale,
        azimuth: 45,
        elevation: 30,
      );
}

/// 地面圆内的拾取
bool hit(List<double> a, List<double> b, double r) {
  final dx = a[0] - b[0], dy = a[1] - b[1];
  return dx * dx + dy * dy <= r * r;
}
