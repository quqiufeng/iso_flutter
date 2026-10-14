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

## 7. 开发提速：热重载 + 抓图/录像 + 动效自检

> ### ⭐ 默认动作（改任何游戏 / 动效都按这个来，**不做=未完成**）
> 1. **用热重载跑**：`bin/dev.sh <game>` —— 改 `.lua` 存盘即自动重开，**不要手动 kill + 重启**；
> 2. **每次改动后「抓/录 + 自检」**：
>    - 抓帧：`AUTO=… CAPTURE_DIR=… love <game>`（动画触发时连拍）；
>    - 或录屏：`ffmpeg x11grab` 录窗口 → mp4；
>    - **自检**：`bin/motion.sh <帧目录>` → 看运动曲线，**确认真在动**（有峰值、非空帧、非卡死）；
> 3. 产物统一放 `~/iso_gen/`（**禁 `/tmp`**），需要给人看的再 `cp` 一份到 `~`。

### 用法
| 命令 | 作用 |
|---|---|
| `bin/dev.sh [game/love\|game/tetris]` | **热重载**：监控 `*.lua`，存盘即自动重开窗口（日志 `~/iso_gen/dev.log`）|
| `AUTO=ult\|whirl CAPTURE_DIR=DIR love game/love` | 无人值守：自动布兵放招并**触发时连拍** N 帧（`CAPTURE_FRAMES`，默认 40）|
| `AUTO=1 CAPTURE_DIR=DIR love game/tetris` | AI 自动玩，**消行时连拍** |
| 游戏内 `F2` | 手动开始连拍 |
| `bin/motion.sh <帧目录> [glob]` | **动效自检**：相邻帧 RMSE 运动曲线（峰值帧/近似静止/强度）|
| `ffmpeg -f x11grab -video_size WxH -framerate 30 -i :0.0+X,Y -t 秒 …` | 录窗口（`xdotool getwindowgeometry --shell $WID` 取 X/Y/W/H）|

```bash
# ① 改代码即时看（热重载）
bin/dev.sh game/tetris

# ② 抓「大招」全过程并自检
AUTO=ult CAPTURE_DIR=$HOME/iso_gen/ult CAPTURE_FRAMES=55 love game/love
bin/motion.sh ~/iso_gen/ult 'ult_*.png'      # → 帧数/平均变化/峰值帧/运动曲线

# ③ 录屏（更顺，动效完整）
DISPLAY=:0 AUTO=ult love game/love & sleep 1.2
WID=$(xdotool search --class love | head -1); eval "$(xdotool getwindowgeometry --shell $WID)"
ffmpeg -f x11grab -video_size ${WIDTH}x${HEIGHT} -framerate 30 -i :0.0+${X},${Y} -t 3.4 -pix_fmt yuv420p ~/iso_gen/ult.mp4
```

