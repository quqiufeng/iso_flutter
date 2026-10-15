# walk_anim —— 2D 角色侧视走路循环生成

用 **diffusers** 的 `AnimateDiffControlNetPipeline`，把一组 **OpenPose 骨架帧** 驱成
一段 2D 游戏角色的**侧视走路循环 GIF**。

- 底模：`dreamshaper-8`（SD1.5）
- 运动模块：`animatediff-motion-adapter-v1-5-2`（提供帧间时序一致性）
- 姿势控制：`control_v11p_sd15_openpose`（逐帧骨架）
- 走路动力学：`walkRL_diff.safetensors`（运动 LoRA）

产物为 **512×512 × 16 帧** 的红披风白甲角色侧走（步态正确、朝左前走）：

- `diffwalk_arm2_big.gif` —— 大步幅
- `diffwalk_arm2_small.gif` —— 小步幅

> 早期 `diffwalk_arm2_regen.gif` 是**太空步**（脸朝左、腿朝右迈），保留仅作对照，见第 7 节。

---

## 1. 目录结构

```
~/iso_flutter/
├── WALK_ANIM.md              # 本文档
├── dw_cn.py                  # 主生成脚本（AnimateDiff + openpose ControlNet + 走路 LoRA）
├── walk_poses.py             # 生成 OpenPose 骨架帧序列（步幅由 KEY 里髋角控制）
├── dl_models.py              # 下载 diffusers 模型到 /data/models/image/diffusers/
├── run_arm2.sh               # 一键复现脚本（含 POSE_FLIP=1）
├── diffwalk_arm2_big.gif     # 产物：大步幅（步态正确）
├── diffwalk_arm2_small.gif   # 产物：小步幅（步态正确）
├── diffwalk_arm2_regen.gif   # 早期产物：太空步（仅对照）
└── poses/
    ├── walk2/                # 大步幅骨架（髋 ±36），16 张 f00.png … f15.png
    └── walk_small/           # 小步幅骨架（髋 ±22），16 张
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
- ⚠️ 骨架是「朝 +x（右）」迈步，但模型渲染时会**把脸翻到朝左、腿仍照抄骨架方向** → 直接渲染会得到
  **太空步**。因此生成时用 `POSE_FLIP=1`（见 5.3）把骨架水平翻转后再喂 ControlNet，才能得到正常前走。

---

## 5. 生成 GIF（主流程）

### 5.1 一键复现 arm2

`run_arm2.sh`：用 `poses/walk2`（大步幅骨架）+ `POSE_FLIP=1`，默认输出 `diffwalk_arm2_big.gif`。

```bash
cd ~/iso_flutter
./run_arm2.sh                    # 直接跑
OUT=/tmp/out.gif ./run_arm2.sh   # 换输出路径
```

### 5.2 手动等价命令

```bash
cd ~/iso_flutter
IP=0 POSE_FLIP=1 POSES="$PWD/poses/walk2" W=512 H=768 FRAMES=16 STEPS=25 SEED=42 CNSCALE=0.55 \
PROMPT="a cute chibi cartoon knight, silver armor, red plume, short red cape, empty hands, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation" \
NEG="sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, extra arms, static, gray background, scenery, background objects, realistic, photo, 3d render" \
OUT=$PWD/diffwalk_arm2_big.gif /data/venv/bin/python dw_cn.py
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
| `POSE_FLIP` | `1` | `0` | **水平翻转输入骨架**再喂 ControlNet。`1`=步态正确（腿与脸同向），`0`=太空步（见第 7 节） |
| `CFG` | `7.5` | `7.5` | 文本引导强度 |
| `LORASCALE` | `1.0` | `1.0` | 走路 LoRA 权重 |
| `FREEINIT` | `0` | `0` | 是否开 FreeInit |
| `FREE_ITERS` | `3` | `3` | FreeInit 轮数（开启时） |
| `FPS` | — | `8` | 导出 gif 的 fps（不影响帧内容） |

> 管线内部：`DDIMScheduler`（`beta_schedule=linear, clip_sample=False, timestep_spacing=linspace, steps_offset=1`）、`enable_model_cpu_offload()`。

---

## 6. 产出

```
~/iso_flutter/diffwalk_arm2_big.gif     (大步幅, 512×512×16)
~/iso_flutter/diffwalk_arm2_small.gif   (小步幅, 512×512×16)
```

---

## 7. 关键经验 / 注意事项

1. **朝向：模型恒把角色渲染成朝左（改不了）。** prompt 加 `facing right`、把骨架左右翻转、
   把 `CNSCALE` 拉到 1.0，**都改不了朝向**（1.0 还会崩坏角色）。
   ⚠️ **关键：模型翻的是「脸」，翻不动「腿的迈步方向」**——骨架朝右迈（+x）时，渲染出来是
   「脸朝左、腿朝右迈」= **太空步**（早期 `diffwalk_arm2_regen.gif` 就是）。
   **正解 = `POSE_FLIP=1`：把「输入骨架」水平翻转**，让腿改朝左迈、与脸同向 → 正常朝左前走。
   （把「输出」镜像没用——输出镜像后仍是太空步。）
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
