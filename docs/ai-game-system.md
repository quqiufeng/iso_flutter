# AI 游戏开发系统（设计蓝图）

> **人类给出"想法 + 意见"，AI 负责开发、试玩、看画面、迭代 —— 一个游戏就此诞生。**
> 本文是目标与设计；多数运行时能力**待实现**（蓝图，非现状）。配套：`docs/automation.md`（全自动化闭环）。

---

## 0. 一句话

把 `iso_flutter`（等距矢量引擎）**封装成"AI 可驱动"的游戏运行时**，接上 agent 的"感知—推理—行动"闭环，
就得到一个 **AI 游戏开发系统**：它**自己写游戏、自己玩、自己看画面、自己改**；人只给方向与审美。

---

## 1. 三个能力

### 1.1 AI 开发（自动闭环）
沿用 `automation.md` 的模式：**写/改 → 构建 → 运行 → 看 → 评估 → 改**，循环直到达标。
- 素材 = **Lua（场景/规则/美术）+ Dart（渲染扩展）**；AI 直接写、可热改。
- 每轮都有**可复现的产物**（代码 + 截图 + 状态记录）。

### 1.2 AI 试玩（自己玩）
- **Headless 驱动**：`step(n)` / `act(输入)` / `replay(录像)` —— 无窗口、按帧推进。
- **确定性**：定点步长 + 种子随机 → 同样输入 = 同样结果 ⇒ 可**回放、回归、对拍**。
- **输入注入**：键鼠/游戏动作/脚本策略（甚至 AI 自己决策的动作）。
- ⇒ AI 能"**走完整游戏流程**"（通关/触发/复现 bug），无需人陪玩。

### 1.3 AI 看画面（识别）
- **观测**：离屏**逐帧截图**（已有能力）+ **世界状态 JSON**（精确）。
- **识别**：视觉模型读画面 → 判"场景/UI/异常/美术问题"（人眼看到的那份）；
  状态 JSON 做**精确断言**（坐标/血量/分数/事件）。二者**互补**：模型懂语义，JSON 保精确。
- ⇒ AI 能"**看着画面**判断哪里不对"，而不只是读日志。

---

## 2. 架构（关键：**模拟 / 渲染 分离**）

```
   人类：想法 + 意见
        │
        ▼
  ┌───────────────────────  Agent（my-agent）  ───────────────────────┐
  │  写/改 Lua·Dart  →  跑  →  看（截图+状态）  →  评估  →  改（循环）    │
  └───────────────┬───────────────────────────────────────────────────┘
                  │  命令： build · step · act · state · shot · replay
  ┌───────────────┴───────────────┐
  │   Sim（纯 Lua，确定、headless） │   ← AI 直接驱动 / 复现（LuaJIT 即可，无需 FFI）
  │   世界状态 · 规则 · 输入 · RNG   │
  └───────────────┬───────────────┘
                  │  状态
  ┌───────────────┴───────────────┐
  │   Render（Flutter / Impeller） │   ← 等距矢量渲染（iso_engine：投影/基元/线稿/shader）
  └───────────────────────────────┘
```

**为什么这么分**：Sim 是**纯 Lua、确定性、无 Flutter** →
AI 可以在**自己的 LuaJIT 里**直接 `require` 并运行它（`step/act/state`），**连 FFI 都不需要**；
而 Render 只消费 Sim 的状态画出画面。这样"AI 走流程"= 跑一段 Lua，**便宜、可复现、可 headless**。

---

## 3. 引擎必须提供的"AI 可驱动性"（Checklist）

| 能力 | 说明 | 现状 |
|---|---|---|
| **全 Lua 化** | 场景/规则/美术/关卡皆 Lua，AI 可写可热改 | 引擎是 Lua ✓，图=函数 → 需**数据化** |
| **Headless 步进** | 无窗口 `step(n)`、可单步/暂停 | ❌ 现要 DISPLAY+窗口 |
| **确定性** | 定点步长 + 种子 RNG | ❌ |
| **输入注入 / 回放** | `act(...)` / 录像回放 | ❌ |
| **状态内省** | 世界状态导出 JSON | ❌ |
| **观测** | 逐帧截图 | ✅ 离屏出图已有 |
| **目标 / 断言** | 声明成功条件；可回归 | ❌ |
| **命令面** | `build/step/act/state/shot/replay`（供 agent 工具调）| ❌ |

> 完成这张表 = 引擎对 AI "透明可操作" = 系统成立。

---

## 4. 与现有资产的关系

| 已有 | 作用 |
|---|---|
| `iso_engine`（Dart+Lua 引擎、线稿渲染、shader、DeepSort）| **Render 层**（等距矢量画面）|
| `app`（Flutter 窗口 + 离屏导出 CLI）| Render 宿主 + **观测**（出帧）|
| `docs/automation.md`（全自动化闭环）| **方法论**（感知-推理-行动）|
| `my-agent`（agent 宿主 + 工具白名单）| **Agent 本体**（写/跑/看/改）|
| `bin/iso.sh`（调用式 CLI）| 命令面的雏形 |

---

## 5. 人的角色

**只提供两样**：
1. **想法** —— 做什么游戏、什么玩法、什么世界；
2. **意见（taste）** —— 好不好玩、好不好看、手感对不对。

其余（实现、试玩、找 bug、调数值、迭代）交给 AI。
> 这就是"人类提供想法与意见，一个游戏诞生"的含义。

---

## 6. 里程碑

| | 内容 | 产出 |
|---|---|---|
| **M0** | 本蓝图 | 设计对齐 |
| **M1** | **Sim/Render 分离** + headless `step/act/state/shot` | AI 能"走游戏流程" |
| **M2** | 确定性 + 回放 + 断言 | AI 能"自动测试 / 回归" |
| **M3** | 接入**视觉识别**（读截图判问题）| AI 能"看画面" |
| **M4** | 场景**数据化**（JSON+脚本）+ 热改 | AI 能"造关卡 / 内容" |
| **M5** | 封装 `iso_game` 命令集 → agent 工具 | 端到端：想法→游戏 |

---

## 7. 边界与诚实

- **taste（好玩/好看）无法全自动化** —— 那正是留给"人的意见"的位置；
- **视觉识别靠模型**（会错）→ 与状态 JSON **互补使用**，不单独依赖；
- 本文件的运行时能力**大多尚未实现**（是蓝图）：现状只有 **渲染/几何/线稿/Lua/离屏出图** 这一层扎实，游戏运行时（循环/场景/输入/碰撞/音频/内省/回放）**待建**。

---

## 8. 技术方案（v2 · 当前落地）

> 与前面 §2 的"Sim/Render 分离"一致；下面是**选型定稿 + 已落地部分**。

| 层 | 选型 | 说明 |
|---|---|---|
| **游戏逻辑（Sim）** | **纯 Lua** `iso_engine/lib/lua/game/battle.lua` | 确定性、headless、可回放；**`luajit` 直接跑**（agent 驱动/断言/复现），**同一份**也喂 LÖVE 渲染 |
| **运行时 / 渲染** | **LÖVE（开源 Lua 2D 引擎）** `game/love/` | LuaJIT + SDL/OpenGL；`love.graphics` GPU 渲染。**集成进本项目**（当运行时用），不是"把我们的东西搬过去" |
| **GUI 容器** | **Flutter**（`app/`） | **只做窗口/面板/工具**，**不再做游戏渲染**（按用户定） |
| **角色关键帧** | **Google 图像（Nano Banana / Gemini）** | `bin/img_nano.sh`（经 **apimart.ai**）：以**同一张参考图**逐张出走路关键姿势 → **跨帧角色一致**（当前主力）|
| **动画 / GIF** | **SD1.5 + AnimateDiff 动画模型** | 本地 `sd-cli -M vid_gen --motion-module mm_sd15_v3`（`/opt/sd`）→ 由关键帧/首帧出 GIF / 视频帧 |
| **抠图 / 对齐** | **BiRefNet** + ImageMagick | 抠透明背景 → 统一画布、**脚底基线对齐 + 水平居中** → 帧序列（`game/love/assets/nb/*.png`）|
| **备选素材** | **CC0 paper-doll / 自建 Lua 骨骼** | `bin/char.sh`（分件组装，换武器/染色）、`iso_engine/lib/lua/rig.lua`（自建骨骼，零授权）|
| **Agent 驱动** | `luajit -e` + 截图 | 无需 MCP/协议：跑 Lua 玩/测；`xdotool`+`import` 截图，agent 自己看 |

> **⚠️ 统一原则：凡"动态效果"（角色动作 / 打斗特效）一律走「关键帧 + 动画模型」生成动画。**
> 即：先用 **Google 图像（Nano Banana）出关键帧** → 再用 **SD1.5 + AnimateDiff（动画模型）**处理成动画帧/GIF。
> **不**手绑骨、**不**逐帧手绘、**不**直接拿单张图当动画。

**角色素材链路（当前用的方案）**
```
参考图(角色形象)
   │  bin/img_nano.sh --ref  （Google Nano Banana / Gemini，经 apimart.ai）
   ▼  逐张出「走路周期关键姿势」：contact(左前)/passing/contact(右前)/passing
关键帧 PNG（白底，跨帧形象一致）
   │  BiRefNet 抠图 → 统一画布、脚底基线对齐 + 水平居中
   ▼
帧序列 knight_walk_0..3.png
   │  （可选）sd-cli -M vid_gen --motion-module  → 图生 GIF/视频
   ▼
LÖVE：角色按 walk 帧循环 → 在等距地图上沿兵线移动
```
```bash
# 关键帧 —— ⚠️ 必须 --ref 同一张角色图，否则形象漂移、不可用（白花钱）
bin/img_nano.sh "同参考图的骑士…走路 KEYFRAME=CONTACT：左腿前…" --ref ref.png --size 3:4 --res 1K --out out
# 图生 GIF（本地 AnimateDiff）
sd-cli -M vid_gen -m sd15.safetensors --vae vae-ft-mse.safetensors \
  --motion-module mm_sd15_v3.safetensors -i frame.png --video-frames 16 --fps 8 -o out.avi
```

**关键教训**
- **⚠️ 生成角色（关键帧/姿势）必须传参考图 `--ref`，且始终用同一张角色图**：Nano Banana 靠参考图锁定"这只角色"。**不传参考图 → 每次出的形象都不同**（发型/盔甲/配色/比例漂移）→ **白花钱、跨帧对不上、不能当动画用**。改动作只改 `prompt`，**参考图永远是同一张**。
- **关键帧一致性靠"同一参考图"**：Nano Banana 给同一张角色参考图、逐张出姿势，实测**跨帧形象高度一致**（contact/passing 互换无误）→ 是当前做角色的主力。
- **本地图生动画**：`/opt/sd` 的 `sd-cli` 支持 AnimateDiff（`-M vid_gen --motion-module`），能从关键帧/首帧出 GIF；但该分支**不接 ControlNet**（不能姿态驱动），单图只出**轻微运动** → **受控动作仍靠"逐张关键帧"**。
- Wan 视频（gguf 5D）在本仓库跑不了：ggml `GGML_MAX_DIMS==4`。
- 早期"自建骨骼/单图网格蒙皮"能做**受控**动作但形象一般（无 GUI 手调）；现以 **AI 关键帧**为主。
- 我们**自己的引擎仍负责"图表/矢量插画"**（iso.sh，`iso_engine`）；**游戏**交给 LÖVE。

**数据流**
```
人类：想法 + 意见
   │
Agent（my-agent）写 Lua(Sim + 场景/素材)
   ├─ luajit  →  headless 跑一局/断言/复现（流程测试，便宜）
   └─ LÖVE     →  OpenGL 渲染 → 截图 → agent 看图 → 迭代
        ↓
     游戏诞生（Flutter 只当 GUI 容器）
```

**目录**
- `game/love/` —— LÖVE 工程（`main.lua` + `assets/`）；`love ~/iso_flutter/game/love` 运行
- `iso_engine/lib/lua/game/battle.lua` —— 纯 Lua Sim（共用）

---

## 9. 相关文档

- `docs/automation.md` —— my-agent 全自动化开发模式（闭环方法论）
- `docs/TESTING.md` —— 测试规范
- `docs/references/*.md` —— 画图的 craft/kit/motion 规范
- 仓库根 `README.md` —— 引擎架构/原理/双引擎

---

## 9. 素材生成链路（已实现工具）

| 素材 | 工具 | 说明 |
|---|---|---|
| **矢量等距图**（场景/物件/角色/UI）| `bin/iso.sh`（+ `iso_engine`）| **代码生成**（Lua/Dart）；AI 可直接写 → 无需美术 |
| **位图素材**（贴图/精灵/道具/图标）| `bin/img.sh` | 基于 `/opt/static_comfyui` 的 `backup.sh`（Z-Image Turbo）+ BiRefNet **抠图**；素材档尺寸预设 + 透明背景 + LoRA 风格 |
| **角色关键帧**（AI 手绘卡通）| `bin/img_nano.sh` | **Nano Banana**（Google Gemini 图像，经 **apimart.ai**）：`--ref` 参考图一致性、`--size/--res/--n`；密钥 `~/.env: APIMART_API_KEY`；`bin/cutparts.sh` 切件 |
| **图生动画 / GIF** | `sd-cli -M vid_gen`（`/opt/sd`）| **SD1.5 + AnimateDiff** motion module（`mm_sd15_v3`）+ `vae-ft-mse`；`--video-frames/--fps` → avi/gif |
| **语音/配音** | `bin/tts.sh` | sherpa-onnx + **Kokoro**（中/英多音色）→ wav/mp3；可指定 **CosyVoice3 克隆音色** |

```bash
bin/img.sh "a cartoon treasure chest, game prop" --kind prop --bg transparent   # → 透明 PNG
bin/tts.sh "欢迎来到等距游戏世界" --out line01.wav                              # → 音频
```

三者都**脚本化、可被 AI 调用** ⇒ "AI 生成素材"闭环成立（矢量=引擎、位图=img.sh、语音=tts.sh）。
