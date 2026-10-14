# 天猫精灵 X1 —— 同一张图的两种实现（Dart / Lua）

这里放**同一个"天猫精灵 X1"等距动画**的两个等价实现，作为引擎的**示例 / 对照**：

| 文件 | 语言 | 图名 | 说明 |
|---|---|---|---|
| `tmall_genie.lua` | **Lua** | `tmall-genie`（默认） | `return function(lift,time) -> 绘制指令 JSON`，由 app 内嵌 LuaJIT 运行 |
| `tmall_genie.dart` | **Dart** | `tmall-genie-dart` | `void tmallGenieDartFigure(canvas, palette, lift, time)`，编译进 app 运行 |

两者**逐像素一致**（渲染 RMSE≈1e-5）。**运行版**分别在 `app/lib/lua/figures/tmall_genie.lua` 与
`app/lib/main.dart`（**本目录只是拷出来的示例**）。

## 出图 / 出动画

```bash
bin/iso.sh render tmall-genie        # Lua 版
bin/iso.sh render tmall-genie-dart   # Dart 版
bin/iso.sh anim   tmall-genie --motion   # 出动画（GIF/MP4）
```

## 产物（`../res/`）

两版各自渲染的 PNG / GIF / MP4 已生成在 `example/res/`：

| 目录 | 文件 |
|---|---|
| `example/res/lua/` | `tmall-genie.png` · `tmall-genie.gif` · `tmall-genie.mp4` |
| `example/res/dart/` | `tmall-genie-dart.png` · `tmall-genie-dart.gif` · `tmall-genie-dart.mp4` |

（两版的 png 逐像素一致；gif/mp4 为 120 帧 / 60fps 的开盖动画。）

## 这张图用了什么

- **零件**：`cylinder`（脚/机身/顶盖/按键）、`knurl`+`sideArc`（出音缝/侧弧）、`ring`（LED 环/内圈/唤醒波纹）、`haloOf`（软投影）、`dotGrid`/`iso`（6 麦点）。
- **动画**：`lift` 控制顶盖抬升（+ 轻微倾斜），`time` 驱动唤醒波纹（扩张+衰减）、LED 变亮、麦克风呼吸、软阴影随开合。
- **取景**：`fitProjection(boxCorners(...), 560, 560, pad:36)`。
- **风格**：线稿样式由渲染层统一给（`drawSolid`/`drawLine`/`drawDots`），图只负责"摆零件 + 动画"。

> 引擎/渲染/桥见 `iso_engine/`；原理见仓库根 `README.md`；设计规范见 `docs/references/`。
