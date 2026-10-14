// 精灵素材（img.sh/SD 生成）：加载 PNG → ui.Image 缓存，供游戏渲染贴图。
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

class Sprites {
  static final Map<String, ui.Image> img = {};
  static bool loaded = false;

  static const List<String> names = [
    'sword', 'archer', 'mage', 'goblin', 'shooter', 'ogre',
    'castle_blue', 'castle_red', 'tile',
  ];

  static Future<void> load() async {
    if (loaded) return;
    for (final n in names) {
      try {
        final data = await rootBundle.load('assets/sprites/$n.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        img[n] = frame.image;
      } catch (_) {
        // 缺图则回退矢量
      }
    }
    loaded = true;
  }
}
