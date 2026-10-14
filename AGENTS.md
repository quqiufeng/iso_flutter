# AGENTS.md — 写图规范（写任何等距图 / 动画前**必读**）

> ## ⚠️ 铁律：生成图 / 动画，必须遵守 `docs/references/` 的最佳实践
> **任何一次生成图或动画前，必须先读、并严格遵守**：
> - **动画** → `docs/references/motion.md`（运动/交互最佳实践）—— **不遵守不算完成**；
> - 构图/明暗 → `docs/references/craft.md`；
> - 引擎用法 → `docs/references/kit.md`；
> - 自检 → `docs/references/verify.md`。
>
> 这些文档是"怎么画才好看 / 动画怎么做才对"的规范，**优先级高于个人直觉**。

> ## 📁 工作文件位置（铁律）
> **所有生成 / 中间 / 临时文件一律放 `~/iso_gen/`，禁止用 `/tmp`**（`/tmp` 会被清理，已经丢过文件）。
> 例：`~/iso_gen/<任务>/...`；最终产物再 `cp` 进仓库 `assets/`。

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

## 5. 蓝图：AI 游戏开发系统

把引擎封装成"AI 可驱动"的游戏运行时（Sim 纯 Lua / Render Flutter + headless 步进 + 输入注入/回放 + 状态内省），
接上 agent 闭环 → **人类给想法与意见，AI 自己开发/试玩/看画面/迭代**。见 `docs/ai-game-system.md`；闭环方法论见 `docs/automation.md`。

## 6. 自驱视觉闭环：**截图 → 识别 → 调整**（agent 自己跑、自己看、自己改）

> 这就是 `docs/ai-game-system.md` 的"感知—推理—行动"落地：**不用人截图**，agent 自己抓窗口、看画面、改代码、再截。

```bash
# ① 跑（游戏窗口；或 ISO_EXPORT=<图名> 走离屏出图，无需窗口）
DISPLAY=:0 ISO_GAME=1 ~/iso_flutter/app/build/linux/x64/release/bundle/iso_app &

# ② 定位窗口（Flutter 窗口 WM_CLASS = com.example.iso_demo）
WID=$(wmctrl -lx | awk '/iso_demo/{print $1; exit}')   # 或 xdotool search --name iso

# ③ 激活 + 截图（抓不到时抓 root 再裁）
xdotool windowactivate "$WID"; xdotool windowraise "$WID"; sleep 1
import -window "$WID" ~/iso_gen/shot.png || { eval "$(xdotool getwindowgeometry --shell "$WID")"; \
  import -window root -crop ${WIDTH}x${HEIGHT}+${X}+${Y} +repage ~/iso_gen/shot.png; }

# ④ 看：直接用 Read 打开 ~/iso_gen/shot.png（agent 能看图）
# ⑤ 调：改代码/图 → cd app && flutter build linux --release → 回 ① 再截
```

**要点**
- HUD 里有 **fps**（评估渲染开销）；`P` 暂停 NPC、`WASD` 走、`空格` pick、`R` 重开。
- **纯 Lua 玩法**用 `luajit` 驱动即可，**不需要窗口**（更快）：
  `luajit iso_engine/lib/lua/game/run.lua --script "goto:14,14;pick" --json --replay`
- 循环 = **写(码) → build → 跑 → 截图 → 看图 → 改**；人只给"想法/意见"。

