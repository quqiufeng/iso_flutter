# 测试与回归（TESTING.md）

> 本仓（`iso_flutter`）能力的回归清单。每次改动后按此做回归。
> 画图/动画规范见 `AGENTS.md` 与 `docs/references/`。

## 0. 前提
```bash
export PATH="$HOME/development/flutter/bin:$PATH"
# 需要：ffmpeg、love 11.x、luajit、python3（StaticPy imgproc 用于骨架/镜像）
```
> 生成/中间文件一律放 `~/iso_gen/`（禁 `/tmp`）。

---

## 1. 引擎（Dart/Lua 等价 + 出图/出动画）
| # | 项目 | 命令 | 预期 |
|---|---|---|---|
| E1 | 双引擎对拍 | `iso_engine/tool/parity.sh` | 同图两版几何一致，渲染 RMSE≈1e-5 |
| E2 | 出静态图 | `bin/iso.sh render tmall-genie` / `... tmall-genie-dart` | 两版 PNG 逐像素一致 |
| E3 | 出动画 | `bin/iso.sh anim tmall-genie --motion` | 生成 GIF/MP4，开盖动画完整 |

---

## 2. 游戏 Sim（纯 Lua · 确定性 · 回放）
| # | 项目 | 命令 | 预期 |
|---|---|---|---|
| S1 | 兵线对推 headless | `luajit iso_engine/lib/lua/game/run.lua --script "goto:14,14;pick" --json --replay` | 输出状态 JSON，回放结果一致 |
| S2 | 水晶方块 headless | `luajit game/tetris/run.lua --seed 7 --script "rotate;left:2;hard;wait:40" --history --replay` | 有落子记忆，回放一致 |
| S3 | 确定性 | 同一脚本跑两遍 | 结果完全相同 |

---

## 3. 游戏渲染（LÖVE）+ 动效自检
| # | 项目 | 命令 | 预期 |
|---|---|---|---|
| R1 | 兵线对推 | `love game/love` | 窗口起来，可布兵/技能 |
| R2 | 水晶方块 | `love game/tetris` | 可操作，触屏条/键控 |
| R3 | 抓帧 + 自检 | `CAPTURE_DIR=$HOME/iso_gen/ult AUTO=ult love game/love`；`bin/motion.sh $HOME/iso_gen/ult` | 连拍出帧，运动曲线有峰值（非空/非卡死） |
| R4 | 热重载 | `bin/dev.sh game/tetris` | 存盘即自动重开窗口 |

---

## 4. 走路动画管线（walk_anim，sd.cpp）
| # | 项目 | 命令/检查 | 预期 |
|---|---|---|---|
| A1 | 骨架 | `OUTDIR=... HAND=1 LEGX=1.0 /opt/StaticPy/anim/pose_walk` | 16 张 `f00..f15.png`，含手部 21 点 |
| A2 | LoRA 生效 | 生成日志含 `(400 / 400) LoRA tensors have been applied` | 用 `walkRL_conv`（**不是** `walkRL_diff`，后者 0/320） |
| A3 | 生成 | `POSE_DIR=<骨架> POSE_FLIP=1 CONTROL_STRENGTH=0.55 OUT=... ./dw_anim.sh` | 出 16 帧 gif |
| A4 | 方向 | 看 `anim.gif` 与镜像版 | 无太空步（腿与脸同向）；朝左=镜像 `POSE_FLIP=1` 输出 |
| A5 | 视觉自检 | 拆帧拼条 + `Read` 看图 | 斗篷飘动、斗篷颜色一致、手无重影/异物 |
| A6 | 产物 | `~/walk_{big,small}_{left,right}.gif` | 512×512×16，方向正确 |
| A7 | 换角色配方（维京人） | 按 `WALK_ANIM.md` §9 跑 DreamShaper 8 + `POSE_FLIP=1` + 16 帧 | `viking_walk_{big,small}.gif` 512×512×16，步态正确 |
| A8 | Qwen 单参考逐帧重绘（实验，已否决） | 按 `WALK_ANIM.md` §10 | 人物跨帧漂移，不作为正式产物；改用 A10 |
| A9 | 原生高分辨率 AnimateDiff | `512×672` + ControlNet | 显存不足（need ~16.8GB / free ~15.6GB） |
| A10 | 精灵图法（动画模型出帧 → Nano 4×4 高清重绘） | 按 `WALK_ANIM.md` §11：先用动画模型出动作帧并拼接触表，再把接触表作为 `--ref` 让 Nano 重绘，最后用 StaticPy `cutout → split_grid → align_head → pack_sprites` | `~/iso_gen/nano_sprite{,_small}/staticpy/aligned1024/f00..f15.png` 1024×1024 RGBA；头盔 x=512±0.5，脚底 y=989；运动均值 ~0.12，0/15 静止；帧序与旧 approved GIF 16/16 |
| A11 | 游戏素材专业后处理 | `cutout` 4K → `split_grid` 行优先 → `align_head` → `pack_sprites`；`FLIP=1` 出左向；`flatten`+`frames_to_gif` 预览 | `atlas_{right,left}_4096.png` 4096×4096 RGBA；`manifest_{right,left}.json` 4×4/16 帧/8fps/loop；`preview_white_1024.gif`；左 atlas = 右 atlas 逐格镜像；cell 0 与 `aligned1024/f00.png` RMSE=0 |

> 常见坑：缺 `POSE_FLIP` → 太空步；LoRA 用 `walkRL_diff` → 斗篷死、手糊；提示词大改 → 角色换人。

---

## 5. 判定标准
| 标记 | 含义 |
|---|---|
| ✓ | 通过 |
| ✗ | 失败（记录现象/日志） |
| — | 跳过（不适用/有副作用） |

---

## 6. 已知坑
- **生成并发**：不要同时跑两个 sd.cpp 生成（会 OOM）。
- **量化 `DTYPE`**：只省显存；本机显存充足时反而略慢、文件不缩小（SD1.5 卷积无法块量化）。
- **提示词即角色**：改 `PROMPT` 会换角色；只调细节请改 `NEG`/参数。
- **图片尺寸**：骨架 512×768，生成 `W×H` 会被缩放，改尺寸注意取景。
- **GL 窗口截图**：`import -window` 可能抓不到，用 root 抓取 + 裁剪（见 `AGENTS.md` §6）。

---

## 7. 推荐回归顺序
1. `E1` 对拍 → 2. `S1/S2` Sim 确定性 → 3. `R1/R2` 游戏能跑 → 4. `A1–A6` 动画管线 → 5. 记录结果。
