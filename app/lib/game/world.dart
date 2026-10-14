// 世界：实体（地面 x,y + 半径/高度/类型）+ 定点更新。
import 'dart:math' as math;

class Entity {
  Entity({required this.x, required this.y, required this.r, required this.h, required this.kind});
  double x, y; // 地面坐标
  double vx = 0, vy = 0; // 速度（世界/秒）
  final double r; // 拾取半径
  final double h; // 高度
  final String kind; // 'player' | 'tree' | 'box' | 'mushroom'
  bool selected = false;
  double get depth => x + y; // painter's order（越大越近）
}

class World {
  World() {
    props.add(Entity(x: 6, y: -4, r: 3, h: 10, kind: 'tree'));
    props.add(Entity(x: -7, y: 5, r: 3, h: 6, kind: 'box'));
    props.add(Entity(x: 0, y: 9, r: 2.5, h: 3, kind: 'mushroom'));
    props.add(Entity(x: -5, y: -8, r: 3, h: 7, kind: 'tree'));
  }

  final Entity player = Entity(x: 0, y: 0, r: 2.5, h: 5, kind: 'player');
  final List<Entity> props = [];
  List<double>? moveTo; // 点击移动目标（地面）

  /// 定点更新：WASD 速度已在输入里设到 player.vx/vy；moveTo 有目标则走过去。
  void update(double dt) {
    if (moveTo != null) {
      final dx = moveTo![0] - player.x, dy = moveTo![1] - player.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < 0.2) {
        moveTo = null;
        player.vx = 0;
        player.vy = 0;
      } else {
        const speed = 9.0;
        player.vx = dx / d * speed;
        player.vy = dy / d * speed;
      }
    }
    player.x += player.vx * dt;
    player.y += player.vy * dt;
  }

  Iterable<Entity> get all => [player, ...props];
}
