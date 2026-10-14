# AGENTS.md — 写图规范（写任何等距图 / 动画前**必读**）

## 1. 先读规范（`docs/references/`）

| 文档 | 内容 | 必读 |
|---|---|---|
| `docs/references/craft.md` | 构图 / 明暗 / 零件库 —— **怎么画才好看** | ★ 最重要 |
| `docs/references/kit.md` | 引擎 API（`iso`/`extrude`/`slabOf`/`cylinder`/`lathe`/`sphereOf`/`tubePieces`…） | ★ |
| `docs/references/motion.md` | 运动 / 交互 —— **动画最佳实践**（缓动 / 弹簧 / 一次性事件） | ★ |
| `docs/references/verify.md` | 自检 / 验证 | ★ |
| `docs/references/{3d,webgl,react,publish,walkthrough}.md` | 原项目文档（浏览器 / React / 画廊），按需参考 | — |

> `kit.md` 写的是原 JS API；**Dart / Lua 版 API 同名**（见 `iso_engine/lib/`）。

## 2. 写图步骤

1. **图定义**（用引擎摆零件 + 做动画）：
   - **Lua**：`app/lib/lua/figures/<name>.lua` —— `return function(lift, time) -> 绘制指令 JSON`；
   - **Dart**：`app/lib/main.dart` 写 `xxxFigure(canvas, palette, lift, time)`。
2. **注册**：在 `app/lib/main.dart` 的 `_figures` 加 `'<name>': Figure(...)`。
3. **构建**：`cd app && flutter build linux --release`。
4. **出图 / 出动画**：`bin/iso.sh render <name>` / `bin/iso.sh anim <name> --motion`。
5. **对照**：参考 `example/tmall-genie/`（同一张图的 **Lua + Dart 两版**，逐像素一致）。

## 3. 原则（摘自 craft）

- **单色线稿**（不是写实）：实体填充=**卡片底色**、可见面=**4 档近底色阴影**、边缘=**细线**（`hi/mid/lo/faint` 色阶）、`halo`=一层 blur 软投影。**light 主题**（白机身/浅底/深灰细边）才是"产品图"那版。
- **painter's order**：`depthOf = 点·视线`，从远到近画；**运动件每帧重排**。
- 图只管"**摆零件 + 动画**"，风格交给渲染层（`drawSolid`/`drawLine`/`drawDots`/`drawTube`）。

## 4. 引擎 / 架构

见仓库根 `README.md`（架构、技术栈、原理、双引擎、流水线）。
