# walk_anim —— 2D 角色侧视走路循环生成

用 **diffusers** 的 `AnimateDiffControlNetPipeline`，把一组 **OpenPose 骨架帧** 驱成
一段 2D 游戏角色的**侧视走路循环 GIF**。

- 底模：`dreamshaper-8`（SD1.5）
- 运动模块：`animatediff-motion-adapter-v1-5-2`（提供帧间时序一致性）
- 姿势控制：`control_v11p_sd15_openpose`（逐帧骨架）
- 走路动力学：`walkRL_diff.safetensors`（运动 LoRA）

本目录的产物基线为 **`diffwalk_arm2_regen.gif`**：**512×512 × 16 帧** 的红披风白甲角色侧走。

---

## 1. 目录结构

```
~/iso_flutter/
├── WALK_ANIM.md              # 本文档
├── dw_cn.py                  # 主生成脚本（AnimateDiff + openpose ControlNet + 走路 LoRA）
├── walk_poses.py             # 生成 OpenPose 骨架帧序列（步幅由 KEY 里髋角控制）
├── dl_models.py              # 下载 diffusers 模型到 /data/models/image/diffusers/
├── run_arm2.sh               # 固化 arm2 全部参数的复现脚本
├── diffwalk_arm2_regen.gif   # 产物基线
└── poses/
    └── walk2/                # arm2 用的 16 张骨架帧 f00.png … f15.png
```

---

## 2. 环境要求

| 项 | 值 |
|---|---|
| Python | `/data/venv/bin/python` |
| torch | `2.6.0+cu126` |
| diffusers | `0.38.0` |
| huggingface_hub | 需要（下载模型时） |
| GPU | NVIDIA（约需 16GB+ 显存；**两个实例并发会 OOM，须串行**） |

---

## 3. 下载模型（一次性，约 7GB）

```bash
/data/venv/bin/python dl_models.py
```

会下载到 `/data/models/image/diffusers/`：

| 目录 | 对应 `dw_cn.py` 变量 |
|---|---|
| `dreamshaper-8` | `BASE` |
| `animatediff-motion-adapter-v1-5-2` | `MOTION` |
| `control_v11p_sd15_openpose` | `CN` |
| `IP-Adapter` | `IPADAPTER`（本流程 `IP=0`，**用不到**） |

另外**走路 LoRA 不在脚本里下载**，需自备：
`/data/models/image/video/walkRL_diff.safetensors`（对应 `LORA`）。

---

## 4. 生成 OpenPose 骨架帧

骨架 = 16 帧循环（4 个关键姿态线性插值），侧视、COCO-18 配色，脚本 `walk_poses.py`。

```bash
/data/venv/bin/python walk_poses.py                          # 输出到脚本内默认 OUTDIR
OUTDIR=$PWD/poses/walk2 /data/venv/bin/python walk_poses.py  # 指定输出目录
```

- 步幅由脚本内 `KEY` 的**髋角**（`hipL/hipR` 的绝对值）决定，越大前后脚叉得越开。
  arm2 基线即随附的 **±36** 那版。
- **已附带 arm2 用过的 16 帧**：`poses/walk2/f00.png … f15.png`，
  **直接用它就能复现下面的 GIF，无需重新生成骨架**。
- 若改 `KEY` 里的髋角来调步幅，骨架形状会变，模型画出的角色外观也会**轻微漂移**（见第 7 节）。

---

## 5. 生成 GIF（主流程）

### 5.1 一键复现 arm2

`run_arm2.sh`：`POSES` 指向本目录的 `poses/walk2`，默认输出本目录的 `diffwalk_arm2_regen.gif`。

```bash
cd ~/iso_flutter
./run_arm2.sh                    # 直接跑
OUT=/tmp/out.gif ./run_arm2.sh   # 换输出路径
```

### 5.2 手动等价命令

```bash
cd ~/iso_flutter
IP=0 POSES="$PWD/poses/walk2" W=512 H=768 FRAMES=16 STEPS=25 SEED=42 CNSCALE=0.55 \
PROMPT="a cute chibi cartoon knight, silver armor, red plume, short red cape, empty hands, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation" \
NEG="sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, extra arms, static, gray background, scenery, background objects, realistic, photo, 3d render" \
OUT=$PWD/diffwalk_arm2_regen.gif /data/venv/bin/python dw_cn.py
```

### 5.3 `dw_cn.py` 全部 env 参数

| 变量 | arm2 值 | 默认 | 说明 |
|---|---|---|---|
| `BASE` | —(用默认) | `/data/models/image/diffusers/dreamshaper-8` | 底模 |
| `MOTION` | — | `.../animatediff-motion-adapter-v1-5-2` | 运动模块 |
| `CN` | — | `.../control_v11p_sd15_openpose` | ControlNet |
| `LORA` | — | `/data/models/image/video/walkRL_diff.safetensors` | 走路运动 LoRA |
| `POSES` | `./poses/walk2` | `<脚本目录>/poses/walk2` | 骨架帧目录（按文件名排序取 16 张） |
| `OUT` | `./diffwalk_arm2_regen.gif` | `<脚本目录>/diffwalk_arm2_regen.gif` | 输出 gif |
| `REF` | —（IP=0 不用） | `<脚本目录>/ref.png` | IP-Adapter 参考图（仅 `IP=1` 时用） |
| `FRAMES` | `16` | `16` | 帧数 |
| `W` `H` | `512` `768` | `512` `768` | **仅**缩放进 ControlNet 的骨架帧；输出尺寸由管线固定为 **512×512** |
| `STEPS` | `25` | `25` | 采样步数 |
| `SEED` | `42` | `42` | 随机种子（**换 seed 角色会变**） |
| `CNSCALE` | `0.55` | `1.0` | ControlNet 权重（越低越松、越像自由发挥） |
| `IP` | `0` | `1` | 是否挂 IP-Adapter 参考图（arm2 **关**） |
| `IPSCALE` | `0.7` | `0.7` | IP-Adapter 权重（`IP=1` 时生效） |
| `CFG` | `7.5` | `7.5` | 文本引导强度 |
| `LORASCALE` | `1.0` | `1.0` | 走路 LoRA 权重 |
| `FREEINIT` | `0` | `0` | 是否开 FreeInit |
| `FREE_ITERS` | `3` | `3` | FreeInit 轮数（开启时） |
| `FPS` | — | `8` | 导出 gif 的 fps（不影响帧内容） |

> 管线内部：`DDIMScheduler`（`beta_schedule=linear, clip_sample=False, timestep_spacing=linspace, steps_offset=1`）、`enable_model_cpu_offload()`。

---

## 6. 产出

```
~/iso_flutter/diffwalk_arm2_regen.gif   (≈ 3.1 MB, 512×512×16)
```

若需要「朝右 + 放慢」的后处理（PIL，勿用 `convert -delay`，对 gif 不生效）：

```python
from PIL import Image, ImageOps
im = Image.open("dw_cn.gif"); fr = []
try:
    while True: fr.append(ImageOps.mirror(im.convert("RGB")).copy()); im.seek(im.tell()+1)
except EOFError: pass
fr = [f.convert("P", palette=Image.ADAPTIVE, colors=256) for f in fr]
fr[0].save("out_right_slow.gif", save_all=True, append_images=fr[1:],
           duration=150, loop=0, optimize=False)   # duration=ms/帧；150≈6.7fps
```

---

## 7. 关键经验 / 注意事项

1. **朝向不受骨架与 prompt 控制。** 骨架是「朝 +x（右）」，但 dreamshaper-8 侧视默认
   **朝左**先验极强，模型会把角色渲染成朝左；prompt 写 `facing right` 也压不住。
   要朝右，**只能对输出 `-flop` 水平镜像**（游戏精灵左右向的标准做法）。
   > 镜像后若「看着像倒着走」，是步态相位/观感问题，不是镜像本身错误。
2. **步幅由骨架髋角决定**（`KEY` 里 `hipL/hipR`），与 prompt 无关。髋角越小步幅越小，但
   **骨架一变，模型画的角色外观（发长、裙长等）也会轻微漂移**，小步幅偶尔还会凭空多画一个球/瓶——
   可在 `NEG` 加 `ball, orb, sphere, flask, bottle, lantern, pouch` 抑制。
3. **换骨架必须重跑**，骨架是唯一的姿势来源；`SEED` 固定 42 才能复现同一张角色。
4. **不要并发**两个 `dw_cn.py`（GPU OOM）。
5. 复现判据：重跑结果与存档 `diffwalk_arm2.gif` **逐帧 RMSE = 0**。

---

## 8. 说明

- 本目录（`~/iso_flutter/`）即为该走路动画管线，**自包含**：`dw_cn.py`、`run_arm2.sh`
  内部路径都基于脚本自身目录（`__file__` / `$HERE`），不再依赖 `~/iso_gen`。
- 另有一条**无 ControlNet** 的纯 AnimateDiff 链路（生成 `~/diffwalk.gif` 那版），
  与本次产物无关，未纳入本目录。
