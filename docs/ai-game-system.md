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
  │   Render（LÖVE / Flutter）     │   ← 游戏用 LÖVE；Flutter 只做等距图/工具
  └───────────────────────────────┘
```
> **游戏框架是 LÖVE**：`game/love`、`game/tetris` 用 `love` 跑；Flutter（`app/`）只负责等距矢量图与离屏导出，**不做游戏渲染**。

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
| **游戏逻辑（Sim）** | **纯 Lua** `iso_engine/lib/lua/game/`（`config/entity/behaviors/weapons/abilities/world/battle`） | 确定性、headless、可回放；**数据+行为+世界API+事件解耦**（加兵种只改 `config.lua`，不动主循环）；`luajit` 直接跑，**同一份**喂 LÖVE 渲染 |
| **运行时 / 渲染** | **LÖVE（开源 Lua 2D 引擎）** `game/love/` | LuaJIT + SDL/OpenGL；`love.graphics` GPU 渲染。**集成进本项目**（当运行时用），不是"把我们的东西搬过去" |
| **GUI 容器** | **Flutter**（`app/`） | **只做窗口/面板/工具**，**不再做游戏渲染**（按用户定） |
| **动作来源（第一步）** | **SD1.5 + AnimateDiff 动画模型** | `dw_anim.sh` / `/opt/static_comfyui/anim.sh`：AnimateDiff + 逐帧 OpenPose ControlNet + 运动 LoRA → **动作正确但可能不清晰**的帧。动作只由它定 |
| **高清姿势图（第二步）** | **Google 图像（Nano Banana / Gemini）** | `bin/img_nano.sh`（经 **apimart.ai**）：把低清帧拼成 4×4 接触表作为 `--ref`，**一次重绘整张精灵图** → 16 个姿势身份一致、高清 |
| **本地改图 / 补帧（辅助）** | **Qwen-Image 2.1（sd.cpp `sd-cli`）** | `bin/img_qwen.sh --ref`：本地、离线，用于改图 / 补帧 / 修细节；**不能替代动画模型定动作** |
| **游戏素材（第三步）** | **StaticPy 素材工具** | `cutout → split_grid → align_head → pack_sprites → flatten/frames_to_gif`：透明 PNG / atlas / manifest / 预览 GIF |
| **备选素材** | **CC0 paper-doll / 自建 Lua 骨骼** | `bin/char.sh`（分件组装，换武器/染色）、`iso_engine/lib/lua/rig.lua`（自建骨骼，零授权）|
| **Agent 驱动** | `luajit -e` + 截图 | 无需 MCP/协议：跑 Lua 玩/测；`xdotool`+`import` 截图，agent 自己看 |

> **⚠️ 统一原则：凡"动态效果"（角色动作 / 打斗特效），顺序固定为「动画模型定动作 → Nano 高清重绘 → StaticPy 出素材」。**
> 即：先让 **SD1.5 + AnimateDiff（动画模型）** 出**动作正确但可能不清晰**的帧；
> 再把帧的**姿势图（4×4 接触表）**交给 **Nano Banana** 重绘成高清姿势；
> 最后用 **StaticPy** 切成游戏用 GIF / PNG / atlas。
> **不**手绑骨、**不**逐帧手绘、**不**拿单张图当动画、**不**先用 Nano 凭空摆姿势。

**角色素材链路（当前用的方案）**
```
动作需求（走路 / 攻击 / 大招）
   │  动画模型：AnimateDiff + OpenPose ControlNet + 运动 LoRA（dw_anim.sh / anim.sh）
   ▼  动作正确但可能糊的 16 帧（例如 512×512）
低清帧（动作的唯一来源）
   │  StaticPy pack_sprites → 按行优先拼 4×4 接触表
   ▼
姿势接触表（2048×2048）
   │  bin/img_nano.sh --ref 接触表 --res 4K  （Nano Banana / Gemini，经 apimart.ai）
   ▼  一张 4096×4096 高清精灵图（16 个姿势同图，身份锁死）
   │  StaticPy cutout → split_grid → align_head → pack_sprites
   ▼
游戏资源：透明 PNG 帧 / atlas + manifest / 预览 GIF
```
```bash
# ① 动画模型出动作帧（动作/朝向/节奏正确即可，不要求清晰）
POSE_DIR=$HOME/iso_gen/pose_walk POSE_FLIP=1 CONTROL_STRENGTH=0.55 \
  OUT=$HOME/iso_gen/walk_lowres W=512 H=512 FRAMES=16 FPS=8 SEED=42 ./dw_anim.sh

# ② 低清帧 → 4×4 姿势接触表（行优先；这张表就是 Nano 的 --ref）
/opt/StaticPy/anim/pack_sprites \
  $HOME/iso_gen/sprite_ref_4x4.png $HOME/iso_gen/sprite_ref_4x4.json \
  512 512 0 0 512 512 4 0 ref_walk $HOME/iso_gen/walk_lowres/frame_*.png

# ③ 用姿势表让 Nano 一次重绘整张高清精灵图（不要逐帧重绘）
bin/img_nano.sh "保持 4×4 同样 16 个姿势、同样角色与顺序，只提升清晰度和细节，纯白底，无边框无文字" \
  --ref $HOME/iso_gen/sprite_ref_4x4.png --size 1:1 --res 4K --out ~/iso_gen/nano_sprite --prefix walk

# ④ StaticPy 后处理 → 透明 PNG / atlas / manifest / 预览 GIF
/opt/StaticPy/cutout "$SPRITE" "$WORK/cut" 1500
bin/split_grid "$WORK/cut/aura_cut.png" "$WORK/cells" 4 4
bin/align_head "$WORK/aligned1024" 1024 1024 512 990 "$WORK"/cells/f*.png
/opt/StaticPy/anim/pack_sprites "$WORK/atlas_right_4096.png" "$WORK/manifest_right.json" \
  1024 1024 0 0 1024 1024 4 0 walk_right "$WORK"/aligned1024/f*.png
```

> **Qwen-Image 2.1（本地）的定位**：只用于改图 / 补帧 / 修细节（`bin/img_qwen.sh --ref`），
> 或把已有高清图改成新姿势；**动作仍必须由动画模型给出**，不能拿 Qwen 逐帧摆姿势替代。
> 权重：`/data/models/image/qwen-image-2.1-Q6_K.gguf` + `qwen_image_2.1_vae_bf16.safetensors` +
> `Qwen3VL-8B-Instruct-Q4_K_M.gguf` + `mmproj-Qwen3VL-8B-Instruct-F16.gguf`（编辑需 vision）。

**技能 / 打斗特效制作（大招为例）**
```
① 动作帧    = 动画模型出「蓄力 → 举剑 → 砸地 → 收势」（AnimateDiff + ControlNet）
   低清但动作正确 → 拼接触表 → Nano 高清重绘 → StaticPy 抠图/对齐
   → knight_ult_0..N（旋斩同理 knight_whirl_*；攻击 knight_attack_*）
② 特效层    = 程序化 VFX（LÖVE 绘制，不用图），按施法进度 p 分三段：
   · 蓄力 (p<0.45)：金色光晕逐层叠加 + 光丝向剑聚拢
   · 砸地瞬间(p≈0.45)：全屏闪光 + 震屏 + 冲击环 + 放射光 + 火花粒子
   · 余波 (p>0.45)：多圈冲击环扩散淡出 + 地面光晕
   （旋斩：白色刀光弧线绕身飞转 + 扩散光圈）
③ 数值       = Sim（battle.lua）：ultimate() 全体敌方 AoE + 冷却；whirlwind() 全体我方旋风斩 + 周围 AoE
④ 播放同步   = 动画按固定时长不循环（ULT_DUR=1.1s / WHIRL_DUR=0.75s），VFX 与该进度对齐
```
即：**动作 = 动画模型出帧 + Nano 高清**，**特效 = 程序化叠加**，**数值 = Sim**，三者按同一进度同步。

**关键教训**
- **⚠️ 动作只能由动画模型定**：先 AnimateDiff/ControlNet 出「动作正确但可能糊」的帧；
  Nano 只做高清重绘。反过来（先 Nano 摆姿势、再让动画模型补动作）步态/节奏必错。
- **Nano 的 `--ref` 必须是该动作的真实姿势表**（低清帧拼的 4×4 接触表），不是另一张无关角色图；
  **一次重绘整张 4×4 精灵图**，16 个姿势同图 → 身份锁死；**逐帧重绘必漂**。
- **本地图生动画的局限**：`sd-cli -M vid_gen` 分支**不接 ControlNet**，单图只能出轻微运动；
  受控动作要用 `static_comfyui/anim.sh` / `dw_anim.sh` 的逐帧骨架控制。
- **Qwen-Image 2.1** 只用于改图 / 补帧 / 修细节，不负责定动作。
- Wan 视频（gguf 5D）在本仓库跑不了：ggml `GGML_MAX_DIMS==4`。
- 早期"自建骨骼/单图网格蒙皮"能做**受控**动作但形象一般（无 GUI 手调）；现以「动画模型 + Nano」为主。
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
| **动态动作帧**（动作来源） | `dw_anim.sh` / `/opt/static_comfyui/anim.sh` | **SD1.5 + AnimateDiff** motion module + 逐帧 OpenPose ControlNet + 运动 LoRA → 动作正确但可能不清晰的帧 |
| **高清姿势图**（4×4 重绘） | `bin/img_nano.sh` | **Nano Banana**（Google Gemini 图像，经 **apimart.ai**）：`--ref` 低清姿势接触表、一次重绘整张精灵图；密钥 `~/.env: APIMART_API_KEY` |
| **本地改图 / 补帧**（辅助）| `bin/img_qwen.sh` | **Qwen-Image 2.1**（sd.cpp `sd-cli`）：`--ref` 参考图 → **同一角色**的改图/补帧/修细节；**不负责定动作**；`--bg transparent` 走 BiRefNet 抠图 |
| **图生动画 / GIF**（仅轻微运动） | `sd-cli -M vid_gen`（`/opt/sd`）| **SD1.5 + AnimateDiff** motion module（`mm_sd15_v3`）+ `vae-ft-mse`；**不接 ControlNet**，受控动作请用 `dw_anim.sh` |
| **语音/配音** | `bin/tts.sh` | sherpa-onnx + **Kokoro**（中/英多音色）→ wav/mp3；可指定 **CosyVoice3 克隆音色** |

```bash
bin/img.sh "a cartoon treasure chest, game prop" --kind prop --bg transparent   # → 透明 PNG
bin/tts.sh "欢迎来到等距游戏世界" --out line01.wav                              # → 音频
```

三者都**脚本化、可被 AI 调用** ⇒ "AI 生成素材"闭环成立（矢量=引擎、位图=img.sh、语音=tts.sh）。
