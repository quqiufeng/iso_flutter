# game —— 「兵线对推」小游戏（LÖVE 运行时）

> 详细技术方案见 [`../docs/ai-game-system.md`](../docs/ai-game-system.md) §8。

## 技术栈（当前）
| 层 | 选型 | 位置 |
|---|---|---|
| **游戏逻辑（Sim）** | **纯 Lua**（确定性/headless） | `iso_engine/lib/lua/game/`（见下「Sim 架构」） |
| **运行时 / 渲染** | **LÖVE**（开源 Lua 2D 引擎，OpenGL） | `game/love/` |
| **GUI 容器** | **Flutter**（只做窗口/工具，不做游戏渲染） | `app/` |
| **角色素材** | 动画模型出动作帧 + Nano 高清重绘 | `dw_anim.sh`、`bin/img_nano.sh`、`game/love/assets/nb/` |

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

## 角色 = 动画模型定动作 + Nano 高清（当前方案）

> **⚠️ 铁律 1：动作只能由动画模型定。**
> 先用 **SD1.5 + AnimateDiff + OpenPose ControlNet + 运动 LoRA** 出「动作正确但可能不清晰」的帧；
> **不**手绑骨、**不**逐帧手绘、**不**拿单张图当动画。
>
> **⚠️ 铁律 2：Nano Banana 只负责按姿势表高清重绘。**
> 把低清帧按行优先拼成 4×4 接触表，作为 `--ref` 一次重绘整张精灵图；
> **`--ref` 必须是该动作的真实姿势表**（不是无关角色图）；**逐帧单独重绘必漂**。
> 不要反过来先用 Nano 凭空摆姿势、再让动画模型补动作。

角色**不再靠手工绑骨/分件**，而是：

```
动作需求（走路 / 攻击 / 大招）
  │ 动画模型：AnimateDiff + 逐帧 OpenPose ControlNet + 运动 LoRA（dw_anim.sh / anim.sh）
  ▼  动作正确但可能糊的 16 帧（低清）
低清帧（动作的唯一来源）
  │ StaticPy pack_sprites → 行优先拼 4×4 接触表
  ▼
姿势接触表
  │ bin/img_nano.sh --ref 接触表 → 一次重绘整张高清精灵图
  ▼
4096×4096 高清精灵图（16 个姿势同图，身份锁死）
  │ StaticPy cutout → split_grid → align_head → pack_sprites
  ▼
assets/nb/knight_walk_0..N.png  /  atlas + manifest  /  预览 GIF
```
```bash
# 1) 动画模型出动作帧（动作对即可，不要求清晰）
POSE_DIR=$HOME/iso_gen/pose_walk POSE_FLIP=1 CONTROL_STRENGTH=0.55 \
  OUT=$HOME/iso_gen/walk_lowres W=512 H=512 FRAMES=16 FPS=8 SEED=42 ./dw_anim.sh
# 2) 低清帧 → 4×4 姿势接触表（这张表就是 Nano 的 --ref）
/opt/StaticPy/anim/pack_sprites \
  $HOME/iso_gen/sprite_ref_4x4.png $HOME/iso_gen/sprite_ref_4x4.json \
  512 512 0 0 512 512 4 0 ref_walk $HOME/iso_gen/walk_lowres/frame_*.png
# 3) Nano 一次重绘整张高清精灵图（不要逐帧重绘）
bin/img_nano.sh "保持 4×4 同样 16 个姿势、同样角色与顺序，只提升清晰度和细节，纯白底，无边框无文字" \
  --ref $HOME/iso_gen/sprite_ref_4x4.png --size 1:1 --res 4K --out ~/iso_gen/nano_sprite --prefix knight
# 4) StaticPy：抠图 → 行优先切格 → 对齐 → atlas/manifest/预览
/opt/StaticPy/cutout "$SPRITE" "$WORK/cut" 1500
bin/split_grid "$WORK/cut/aura_cut.png" "$WORK/cells" 4 4
bin/align_head "$WORK/aligned1024" 1024 1024 512 990 "$WORK"/cells/f*.png
/opt/StaticPy/anim/pack_sprites "$WORK/atlas_right_4096.png" "$WORK/manifest_right.json" \
  1024 1024 0 0 1024 1024 4 0 walk_right "$WORK"/aligned1024/f*.png
```
- **Qwen-Image 2.1（本地）** 只用于改图 / 补帧 / 修细节；不能替代动画模型定动作。
- LÖVE 里 `NBMAP`（`main.lua`）把兵种映射到角色（当前各兵种统一用 `knight`）；帧从 `assets/nb/<name>_<anim>_<i>.png` 加载，走路循环。
- 关键帧尺寸偏大 → 缩放到 `~1.9*cam.s` 高绘制；图像开 **mipmap** 保持清晰。

## 技能 / 特效制作（大招为例）
```
① 动作帧 = 动画模型出「蓄力→举剑→砸地→收势」
   低清但动作正确 → 拼 4×4 接触表 → Nano 高清重绘 → StaticPy 抠图/对齐
   → assets/nb/knight_ult_0..N（旋斩同理 knight_whirl_*）
   （动作只由动画模型定；Nano 的 --ref 必须是这组动作的姿势表）
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
