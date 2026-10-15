# game —— 「兵线对推」小游戏（LÖVE 运行时）

> 详细技术方案见 [`../docs/ai-game-system.md`](../docs/ai-game-system.md) §8。

## 技术栈（当前）
| 层 | 选型 | 位置 |
|---|---|---|
| **游戏逻辑（Sim）** | **纯 Lua**（确定性/headless） | `iso_engine/lib/lua/game/`（见下「Sim 架构」） |
| **运行时 / 渲染** | **LÖVE**（开源 Lua 2D 引擎，OpenGL） | `game/love/` |
| **GUI 容器** | **Flutter**（只做窗口/工具，不做游戏渲染） | `app/` |
| **角色素材** | **AI 关键帧**（Nano Banana）+ 抠图对齐 | `bin/img_nano.sh`、`game/love/assets/nb/` |

## Sim 架构（数据 + 行为 + 世界 + 事件）
逻辑与表现解耦：**实体只是数据；"怎么走/怎么打"是策略函数；一切交互经"世界"这扇门；结果以事件流出。**

| 模块 | 职责 |
|---|---|
| `config.lua` | **纯数值**：兵种 / 波次 / 技能（加兵种=加一行，不动逻辑） |
| `entity.lua` | 实体构造（pos/hp/team/stats/state，无逻辑） |
| `behaviors.lua` | 行为(AI)：`rush/ranged/guard…`，统一签名 `(u, w, dt)` |
| `weapons.lua` | 命中效果：`melee/arrow/splash/heavy…` |
| `abilities.lua` | 技能：`ult/whirl` |
| `arena.lua` | **世界内核**：查询 / 推进 / 交战 / 结算 / **emit 事件**（不碰 `love.*`，可 headless）<br>（`world.lua` 是另一套"地图世界"，供 `sim.lua` 走动 demo 用） |
| `battle.lua` | **组装门面**：`require("battle").new(...)`（对外 API 不变） |

- 加兵种 → `config.units` 加一行；加行为 → `behaviors.lua` 一个函数；加武器 → `weapons.lua` 一个函数——**都不动主循环**。
- Sim 只 `emit{type="hit|death|wave|base"}`；渲染/FX 去消费 → 换皮/换引擎不用动逻辑。
- 确定性可测：`luajit` 直接跑两遍结果一致。

## 运行
```bash
# 渲染版（LÖVE）——窗口 1280×800（见 conf.lua），可缩放
love ~/iso_flutter/game/love

# 纯逻辑版（headless，agent 驱动/测试）
luajit iso_engine/lib/lua/game/run.lua --script "goto:14,14;pick" --json --replay
```

## 画面
**俯视 3/4、横平竖直**（`FY=0.78` 竖向压扁）：10×8 网格铺满屏幕，一条条**横排兵线**；蓝塔在左（我方）、红塔在右（敌方），单位沿行向对方推进。

## 玩法
左=我方防守（`1/2/3` 选兵 · 点左半场布兵）· 右=敌方进攻（成波刷兵）· 双方单位射程内自动互攻 · 推掉对方城堡即胜 · `R` 重开。

## 角色 = AI 关键帧（当前方案）

> **⚠️ 铁律 1：生成角色图必须传参考图 `--ref`，且始终用同一张角色图。**
> Nano Banana 靠参考图锁定"同一只角色"；**不传参考图 → 每次形象都不同**（发型/盔甲/配色/比例漂移）→ **白花钱、跨帧对不上、不能当动画**。改动作只改 prompt，参考图永远同一张。
>
> **⚠️ 铁律 2：凡"动态效果"（角色动作 / 打斗特效）一律走「关键帧 + 动画模型」。**
> 先 NB 出关键帧 → 再用 **SD1.5 + AnimateDiff（动画模型）**处理成动画帧/GIF；不手绑骨、不逐帧手绘。

角色**不再靠手工绑骨/分件**，而是：

```
参考图(角色形象)
  │ bin/img_nano.sh --ref ref.png   ← Google Nano Banana(Gemini 图像)，经 apimart.ai
  ▼  逐张出「走路周期关键姿势」：contact(左前)/passing/contact(右前)/passing
关键帧 PNG（白底，跨帧形象一致）
  │ BiRefNet 抠透明背景 → 统一画布 + 脚底基线对齐 + 水平居中
  ▼
帧序列 assets/nb/knight_walk_0..3.png
  │ （可选）sd-cli -M vid_gen --motion-module  → 图生 GIF/视频
  ▼
LÖVE：骑士按 walk 帧循环 → 沿兵线移动
```
```bash
# 1) 关键帧（同一参考图保证一致性）
bash bin/img_nano.sh "同参考图的骑士，走路 KEYFRAME=CONTACT：左腿前…" \
  --ref example/rig-knight/knight_half.png --size 3:4 --res 1K --out /tmp/walk --prefix w1
# 1b) 本地补帧/新姿势（Qwen-Image 2.1，离线免费）——以某张关键图为参考，出"同一角色"
bin/img_qwen.sh "同一只Q版骑士，走路接触帧：右腿前…，形象配色完全一致，纯白背景，全身" \
  --ref /tmp/walk/w1.png --size 768x1024 --steps 12 --seed 5 --out /tmp/walk --prefix q1
# 2) 抠图对齐（BiRefNet + ImageMagick）→ 存到 game/love/assets/nb/
bash /opt/static_comfyui/cpp/sd/bgremove.sh w1.png nobg1.png transparent
# 3) 拼 GIF（最简 ping-pong；无模型）
ffmpeg -framerate 10 -i frames/f%02d.png -vf "split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 walk.gif
# 3b) 或图生动画（本地 AnimateDiff，可选）
sd-cli -M vid_gen -m sd15.safetensors --vae vae-ft-mse.safetensors \
  --motion-module mm_sd15_v3.safetensors -i frame.png --video-frames 16 --fps 8 -o out.avi
```
- **混合链路（当前最佳）**：**Nano 出高质量关键图 → 本地 `img_qwen.sh --ref` 出同一角色的补帧/新动作 → 拼 GIF**（形象一致、离线免费）。实测 Q 版骑士「行走」4 帧 → ping-pong 6 帧 GIF。
- LÖVE 里 `NBMAP`（`main.lua`）把兵种映射到角色（当前各兵种统一用 `knight`）；帧从 `assets/nb/<name>_<anim>_<i>.png` 加载，走路循环。
- 关键帧尺寸偏大 → 缩放到 `~1.9*cam.s` 高绘制；图像开 **mipmap** 保持清晰。

## 技能 / 特效制作（大招为例）
```
① 动作关键帧 = 关键帧方法（NB，同一参考图）
   蓄力→举剑→砸地→收势 4 帧 → assets/nb/knight_ult_0..3（旋斩 5 帧 knight_whirl_*）
   bash bin/img_nano.sh "…ULTIMATE KEYFRAME 3：砸地…" --ref example/rig-knight/knight_half.png --out /tmp/ult
   → BiRefNet 抠图 → 脚底对齐
② 特效层 = 程序化 VFX（LÖVE 画，不用图），按施法进度 p 分三段：
   蓄力金晕 → 砸地(全屏闪 + 震屏 + 冲击环 + 放射光 + 火花) → 余波扩散环
   （旋斩：白色刀光弧线绕身飞转）
③ 数值 = Sim：battle:ultimate() 全体敌方 AoE+CD；battle:whirlwind() 全体我方旋风斩
④ 播放 = 动画按固定时长不循环（ULT_DUR=1.1s / WHIRL_DUR=0.75s），VFX 同步
```
- 按键：`空格/Q` 大招 · `W` 旋斩。

## 备选方案（仍在仓库，可切换）
- **CC0 paper-doll**：`bin/char.sh u1 '#9ec6ff'` —— 分件按帧组装，换武器/染色。素材源 `/opt/charpack/`。
- **自建 Lua 骨骼**：`iso_engine/lib/lua/rig.lua`（`bin/cutparts.sh` 切件 → 绑骨）。
- **单图网格蒙皮**：`iso_engine/lib/lua/skin.lua`（LBS，不切图；形变一般）。
- **本地图生视频**：`/opt/sd` 的 `sd-cli -M vid_gen`（SD1.5 + AnimateDiff）；单图只能出**轻微运动**（该分支不接 ControlNet）。
