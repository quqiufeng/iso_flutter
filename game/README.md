# game —— 「兵线对推」小游戏（LÖVE 运行时）

> 详细技术方案见 [`../docs/ai-game-system.md`](../docs/ai-game-system.md) §8。

## 技术栈（当前）
| 层 | 选型 | 位置 |
|---|---|---|
| **游戏逻辑（Sim）** | **纯 Lua**（确定性/headless） | `iso_engine/lib/lua/game/battle.lua` |
| **运行时 / 渲染** | **LÖVE**（开源 Lua 2D 引擎，OpenGL） | `game/love/` |
| **GUI 容器** | **Flutter**（只做窗口/工具，不做游戏渲染） | `app/` |
| **角色素材** | **AI 关键帧**（Nano Banana）+ 抠图对齐 | `bin/img_nano.sh`、`game/love/assets/nb/` |

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
# 2) 抠图对齐（BiRefNet + ImageMagick）→ 存到 game/love/assets/nb/
bash /opt/static_comfyui/cpp/sd/bgremove.sh w1.png nobg1.png transparent
# 3) 图生动画（本地 AnimateDiff，可选）
sd-cli -M vid_gen -m sd15.safetensors --vae vae-ft-mse.safetensors \
  --motion-module mm_sd15_v3.safetensors -i frame.png --video-frames 16 --fps 8 -o out.avi
```
- LÖVE 里 `NBMAP`（`main.lua`）把兵种映射到角色（当前各兵种统一用 `knight`）；帧从 `assets/nb/<name>_<anim>_<i>.png` 加载，走路循环。
- 关键帧尺寸偏大 → 缩放到 `~1.9*cam.s` 高绘制；图像开 **mipmap** 保持清晰。

## 备选方案（仍在仓库，可切换）
- **CC0 paper-doll**：`bin/char.sh u1 '#9ec6ff'` —— 分件按帧组装，换武器/染色。素材源 `/opt/charpack/`。
- **自建 Lua 骨骼**：`iso_engine/lib/lua/rig.lua`（`bin/cutparts.sh` 切件 → 绑骨）。
- **单图网格蒙皮**：`iso_engine/lib/lua/skin.lua`（LBS，不切图；形变一般）。
- **本地图生视频**：`/opt/sd` 的 `sd-cli -M vid_gen`（SD1.5 + AnimateDiff）；单图只能出**轻微运动**（该分支不接 ControlNet）。
