# walk_anim —— 2D 角色侧视走路循环生成

> **现状（sd.cpp 版）**：图像处理走 **StaticPy `imgproc`**（`pose_walk`(StaticPy)/`imgproc/mirror_gif`，无 PIL/numpy）；
> 生成走 **sd.cpp + comfycli**（`/opt/static_comfyui`，`anim.sh` 入口），**无 diffusers/torch**。
> 旧 diffusers 版 `dw_cn.py` **已删除**；`dw_anim.sh` 现为 **bash**（调 sd.cpp）。

## 流水线
```
pose_walk（StaticPy 画 OpenPose 骨架帧）
    │  CONTROL_DIR=<骨架目录> POSE_FLIP=1
    ▼
dw_anim.sh  →  /opt/static_comfyui/anim.sh
    │  sd.cpp：AnimateDiff 运动模块 + 逐帧 openpose ControlNet + 走路 LoRA
    ▼
~/iso_gen/<out>/anim.gif
    │  imgproc/mirror_gif（朝左的正确走 → 镜像成朝右）
    ▼
~/walk_{big,small}_{left,right}.gif      (512×512 × 16 帧)
```

---

## 1. 目录
```
~/iso_flutter/
├── WALK_ANIM.md            # 本文档
│   · 骨架：StaticPy `/opt/StaticPy/anim/pose_walk`（env: OUTDIR/LEGX/ARMX/YUP/HAND）
├── dw_anim.sh              # 主生成脚本（bash → sd.cpp/comfycli）
│   · 镜像：StaticPy `/opt/StaticPy/imgproc/mirror_gif`
├── poses/                  # 随附骨架（walk2 大步 / walk_smaller 小步 …）
└── ~/walk_*.gif            # 产物（在 HOME，不在仓库）
```

---

## 2. 骨架 `pose_walk`（StaticPy）
侧视 OpenPose，16 帧循环（4 个关键姿态线性插值）。

| env | 默认 | 说明 |
|---|---|---|
| `OUTDIR` | `<脚本目录>/walk6` | 输出目录（`f00.png … f15.png`） |
| `LEGX` | `1.0` | **步幅**（腿横向压缩）。`1.0` 大步、`0.5` 小步。★调步幅用它，别改 KEY 髋角 |
| `ARMX` | `1.0` | 手臂横向摆幅放大 |
| `YUP` | `0` | 整体上移像素（底部留白，防脚贴边） |
| `HAND` | `1` | **是否画 OpenPose 手部 21 关键点/手**（洋红色，沿前臂摆动） |

```bash
OUTDIR=$HOME/iso_gen/pose_big   HAND=1 LEGX=1.0 /opt/StaticPy/anim/pose_walk   # 大步
OUTDIR=$HOME/iso_gen/pose_small HAND=1 LEGX=0.5 /opt/StaticPy/anim/pose_walk   # 小步
```
> `pose_walk`(StaticPy) 的 `KEY` 髋角固定 **±22**；步幅只靠 `LEGX`（骨架形状尽量不变、角色漂移最小）。

---

## 3. 生成 `dw_anim.sh`
```bash
# 小步、朝左（POSE_FLIP 修步态；随后用 mirror_gif 出朝右）
cd ~/iso_flutter
POSE_DIR=$HOME/iso_gen/pose_small POSE_FLIP=1 CONTROL_STRENGTH=0.55 \
OUT=$HOME/iso_gen/g_small W=512 H=512 FRAMES=16 STEPS=25 SEED=42 ./dw_anim.sh
cp ~/iso_gen/g_small/anim.gif ~/walk_small_left.gif
/opt/StaticPy/imgproc/mirror_gif ~/walk_small_left.gif ~/walk_small_right.gif
```
> `OUT` 是**输出目录**（自动在其下写 `anim.gif` + 逐帧 `frame_*.png`）。

### `dw_anim.sh` 环境变量
| 变量 | 默认 | 说明 |
|---|---|---|
| `MODEL` | `/data/models/image/video/toonyou_alpha3.safetensors` | 底模（ToonYou，2D 动画向） |
| `VAE` | `vae-ft-mse.safetensors` | |
| `MOTION` | `mm_v2_prefixed.safetensors` | AnimateDiff 运动模块 |
| `LORA` | `walkRL_conv.safetensors` | 走路 LoRA（★必须是 sd.cpp 认的格式，见 §5） |
| `LORA_STRENGTH` | `1.0` | |
| `CONTROL_NET` | `control_openpose-fp16.safetensors` | openpose ControlNet |
| `CONTROL_DIR` | `$POSE_DIR` | 逐帧骨架目录 |
| `CONTROL_STRENGTH` | `1.0`（arm2 配方用 `0.55`） | ControlNet 权重 |
| `POSE_FLIP` | `0`（★正确步态用 `1`） | 水平翻转**输入骨架** |
| `PROMPT` / `NEG` | arm2 原版 | 提示词 |
| `W` `H` | `512` `512` | 输出尺寸 |
| `FRAMES` `FPS` | `16` `8` | |
| `STEPS` `CFG` `SEED` | `25` `7.5` `42` | |
| `DTYPE` | （空=fp16） | 直传 `anim.sh`：加载期量化 `q8_0`/`q4_0`（省显存，本机略慢） |

`anim.sh` 还支持 `NODE_SET`、`GEN`（先跑 StaticPy `pose_walk`）等，详见其头部注释。

---

## 4. 朝向 / 步态（★核心经验）
- **太空步根因**：模型把角色的**脸**恒渲染成一个方向，但**照抄骨架的迈步方向**。骨架朝右迈 + 脸朝左 ⇒ 倒退（moonwalk）。
- **正解 = `POSE_FLIP=1`**：把**输入骨架**水平翻转，让"腿的迈步方向"与"脸"同向 ⇒ 正确前走。
- **本机实测（sd.cpp + ToonYou）**：`POSE_FLIP=1` 时角色**朝右**正常走；因此
  - **朝左** = 对 `POSE_FLIP=1` 的输出用 `imgproc/mirror_gif` 镜像；
  - **朝右** = `POSE_FLIP=1` 原始输出。
  （旧 diffusers 文档里"POSE_FLIP=1 即朝左"的结论**不适用于新管线**，以实测为准。）
- 顺序：**先修步态（POSE_FLIP），再镜像朝向**；直接镜像一个太空步只会得到镜像的太空步。

---

## 5. 走路 LoRA 的格式（★）
sd.cpp **只认 kohya 格式**（`lora_down.weight`/`lora_up.weight`）：

| 文件 | 格式 | sd.cpp 生效 |
|---|---|---|
| `walkRL_conv.safetensors` | kohya `lora_down/up` | **400/400 ✓** |
| `walkRL_ab.safetensors` | kohya `lora_A/B` | 400/400 ✓ |
| `walkRL_unet.safetensors` | 400/400 ✓ | |
| `walkRL_diff.safetensors` | diffusers `_lora.down/up` | **0/320 ✗（不生效）** |

日志确认：`(400 / 400) LoRA tensors have been applied`。挂上后斗篷飘动、走路动力学才正常。

---

## 6. 手部（HAND）
- 骨架默认 `HAND=1`：每只手画 **OpenPose 21 关键点**（洋红色，沿前臂方向），让 ControlNet 也约束手。
- 效果：手的**重影/漂移**明显减少。
- 局限：我们的 `control_openpose` 是**身体版**训练，喂手部关键点属"超纲"——位置能大致控住，但**手的形状/手臂姿态会被带偏**（易糊成红色"连指手套/球"）。仍在调（改形状/改提示词/FreeInit/换底模等）。

---

## 7. 一键复现 4 张
```bash
cd ~/iso_flutter
OUTDIR=$HOME/iso_gen/pb_hand HAND=1 LEGX=1.0 /opt/StaticPy/anim/pose_walk
OUTDIR=$HOME/iso_gen/ps_hand HAND=1 LEGX=0.5 /opt/StaticPy/anim/pose_walk
gen() { POSE_DIR="$1" POSE_FLIP=1 CONTROL_STRENGTH=0.55 OUT="$2" W=512 H=512 FRAMES=16 STEPS=25 SEED=42 ./dw_anim.sh; }
gen $HOME/iso_gen/pb_hand $HOME/iso_gen/h_big
gen $HOME/iso_gen/ps_hand $HOME/iso_gen/h_small
cp ~/iso_gen/h_big/anim.gif   ~/walk_big_left.gif
cp ~/iso_gen/h_small/anim.gif ~/walk_small_left.gif
/opt/StaticPy/imgproc/mirror_gif ~/walk_big_left.gif   ~/walk_big_right.gif
/opt/StaticPy/imgproc/mirror_gif ~/walk_small_left.gif ~/walk_small_right.gif
```

---

## 8. 注意事项
1. **GPU**：单实例约 7–8 GB 显存；**不要并发**两个生成（会 OOM）。
2. **量化**：`DTYPE=q8_0/q4_0` 只省显存；本机（3080 显存充足）**反而略慢**，文件不变小（gguf 对 SD1.5 的 3×3 卷积无法块量化）。
3. **尺寸**：骨架帧为 512×768，生成 `W×H`（如 512×512）时会被缩放；改 `W/H` 注意取景。
4. **换骨架必须重跑**；`SEED` 固定才复现同一角色。
5. **提示词是"角色身份证"**：大改 prompt 会换角色；只想修细节时优先改 `NEG` / 参数，别动角色描述。
6. 生成/中间文件统一放 `~/iso_gen/`（禁 `/tmp`）。
