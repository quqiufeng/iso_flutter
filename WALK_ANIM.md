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

---

## 9. 已验证配方：维京人战士 big / small（DreamShaper 8，步态正确）

> **历史说明**：本节/§10 的旧后处理命令含 ImageMagick/Pillow/ffmpeg，仅作记录；
> 当前正式素材后处理（透明 PNG / atlas / manifest / 翻转）见 §11 和 `README.md`。

> 产物（已 cp 到仓库根与 `~`）：
> - `viking_walk_big.gif` —— 大步（`LEGX=1.0`），512×512×16 @ 8fps
> - `viking_walk_small.gif` —— 小步（`LEGX=0.5`），512×512×16 @ 8fps
>
> 结论：**DreamShaper 8 + walkRL_conv 1.0 + mm_v2_prefixed + openpose ControlNet**
> 能听 prompt 换角色；ToonYou 会被 walkRL LoRA 锁成它训练时的角色，不适合换皮。
> **必须用 `FRAMES=16`**（AnimateDiff `context_length=16`；用 8 帧测试会出条纹/巨大背景物，不是模型问题）。

### 9.1 关键参数

| 项 | 值 |
|---|---|
| 底模 | `/models/DreamShaper_8.safetensors` |
| 运动模块 | `/data/models/image/video/mm_v2_prefixed.safetensors` |
| 走路 LoRA | `/data/models/image/video/walkRL_conv.safetensors`，`LORA_STRENGTH=1.0` |
| ControlNet | `/data/models/image/controlnet/control_openpose-fp16.safetensors` |
| 骨架 | `HAND=1`，`YUP=80`，`LEGX=1.0`（big）/ `0.5`（small） |
| 生成 | `W=512 H=512 FRAMES=16 FPS=8 STEPS=25 CFG=7.5 SEED=42` |
| 步态 | `POSE_FLIP=1`、`CONTROL_STRENGTH=0.55` |
| 后处理 | BiRefNet 抠透明 → 白底 → 全局统一裁剪/缩放（去掉 DreamShaper 的背景条纹） |

固定 prompt / negative（两条命令完全相同，只换 `POSE_DIR` / `OUT`）：

```bash
PROMPT='a cute chibi cartoon male viking warrior, horned iron helmet, long braided blonde beard, brown leather armor with fur trim, leather boots, empty hands, vibrant colors, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation'
NEG='female, girl, woman, sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, static, gray background, scenery, objects, realistic, photo, 3d render'
```

### 9.2 完整复现命令（从骨架到 GIF）

```bash
cd ~/iso_flutter
export LD_LIBRARY_PATH=/opt/StaticPy/cpp/imgproc/build:${LD_LIBRARY_PATH:-}
mkdir -p ~/iso_gen/tmp

# ① 骨架：big / small（16 帧 OpenPose，含手部关键点）
OUTDIR=$HOME/iso_gen/viking_pose_big   HAND=1 LEGX=1.0 YUP=80 /opt/StaticPy/anim/pose_walk
OUTDIR=$HOME/iso_gen/viking_pose_small HAND=1 LEGX=0.5 YUP=80 /opt/StaticPy/anim/pose_walk

PROMPT='a cute chibi cartoon male viking warrior, horned iron helmet, long braided blonde beard, brown leather armor with fur trim, leather boots, empty hands, vibrant colors, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation'
NEG='female, girl, woman, sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, static, gray background, scenery, objects, realistic, photo, 3d render'

# ② 生成（big；约 3–4 分钟）
TMPDIR=$HOME/iso_gen/tmp \
POSE_DIR=$HOME/iso_gen/viking_pose_big POSE_FLIP=1 CONTROL_STRENGTH=0.55 \
MODEL=/models/DreamShaper_8.safetensors LORA_STRENGTH=1.0 \
OUT=$HOME/iso_gen/viking_ds_test2 W=512 H=512 FRAMES=16 FPS=8 STEPS=25 CFG=7.5 SEED=42 \
PROMPT="$PROMPT" NEG="$NEG" ./dw_anim.sh

# ③ 生成（small；同一模型/seed/prompt，只换骨架与输出）
TMPDIR=$HOME/iso_gen/tmp \
POSE_DIR=$HOME/iso_gen/viking_pose_small POSE_FLIP=1 CONTROL_STRENGTH=0.55 \
MODEL=/models/DreamShaper_8.safetensors LORA_STRENGTH=1.0 \
OUT=$HOME/iso_gen/viking_ds_small W=512 H=512 FRAMES=16 FPS=8 STEPS=25 CFG=7.5 SEED=42 \
PROMPT="$PROMPT" NEG="$NEG" ./dw_anim.sh

# ④ 抠图 → 白底（DreamShaper 会带横向背景条纹）
#    注意：bgremove.sh 的 white 模式会输出全白，必须用 transparent 再自己压白底
for pair in "viking_ds_test2:viking_big" "viking_ds_small:viking_small"; do
  IN=$HOME/iso_gen/${pair%%:*}; NAME=${pair##*:}
  mkdir -p $HOME/iso_gen/${NAME}_cut $HOME/iso_gen/${NAME}_white
  for f in "$IN"/frame_*.png; do
    b=$(basename "$f")
    bash /opt/static_comfyui/cpp/sd/bgremove.sh "$f" "$HOME/iso_gen/${NAME}_cut/$b" transparent >/dev/null
    convert "$HOME/iso_gen/${NAME}_cut/$b" -background white -alpha remove -alpha off \
      "$HOME/iso_gen/${NAME}_white/$b"
  done
done

# ⑤ 全局统一裁剪（同一 bbox 裁所有帧，避免逐帧 trim 抖动）→ 512×512
#    bbox 由所有帧的 -trim 并集得到；换 prompt/seed 后需重算。
#    big   : 312x461+116+17
#    small : 246x438+133+21
mkdir -p $HOME/iso_gen/viking_big_final $HOME/iso_gen/viking_small_final
for f in $HOME/iso_gen/viking_big_white/frame_*.png; do
  convert "$f" -crop 312x461+116+17 +repage -resize 512x512 \
    -background white -gravity center -extent 512x512 "$HOME/iso_gen/viking_big_final/$(basename "$f")"
done
for f in $HOME/iso_gen/viking_small_white/frame_*.png; do
  convert "$f" -crop 246x438+133+21 +repage -resize 512x512 \
    -background white -gravity center -extent 512x512 "$HOME/iso_gen/viking_small_final/$(basename "$f")"
done

# ⑥ 拼 GIF（8fps）
ffmpeg -y -framerate 8 -i $HOME/iso_gen/viking_big_final/frame_%03d.png \
  -vf "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 $HOME/iso_gen/viking_big_final/viking_walk_big.gif
ffmpeg -y -framerate 8 -i $HOME/iso_gen/viking_small_final/frame_%03d.png \
  -vf "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 $HOME/iso_gen/viking_small_final/viking_walk_small.gif

# ⑦ 产物
cp $HOME/iso_gen/viking_big_final/viking_walk_big.gif   ~/iso_flutter/viking_walk_big.gif
cp $HOME/iso_gen/viking_small_final/viking_walk_small.gif ~/iso_flutter/viking_walk_small.gif
cp ~/iso_flutter/viking_walk_big.gif ~/viking_walk_big.gif
cp ~/iso_flutter/viking_walk_small.gif ~/viking_walk_small.gif
```

### 9.3 自检（已通过）

```bash
bin/motion.sh ~/iso_gen/viking_big_final 'frame_*.png'
# 帧数=16 平均变化=0.1773 峰值=第2个间隔 近似静止=0/15
bin/motion.sh ~/iso_gen/viking_small_final 'frame_*.png'
# 帧数=16 平均变化=0.1497 峰值=第5个间隔 近似静止=0/15
```

- 朝向：角色朝左，腿与脸同向，**无太空步**。
  （prompt 里的 `walking to the right` 是复现用的原文；本配方实测输出朝左，保持不改以保证复现。需要朝右时对输出做镜像。）
- 角色：角盔、长辫胡须、皮甲/毛边、皮靴，跨帧形象一致。
- 背景：BiRefNet 抠图后纯白，无 DreamShaper 的横向条纹。
- 尺寸：512×512 × 16 帧 @ 8fps。

> 已知坑：
> - 8 帧测试会出现巨大背景物/条纹 → **必须 16 帧**。
> - `bgremove.sh ... white` 会输出全白 → 用 `transparent` + ImageMagick 压白底。
> - `walkRL_conv` 在 ToonYou 上会锁角色；换角色用 DreamShaper 8，或降 LoRA 并接受背景变脏。

### 9.4 只变清晰、不改角色：ESRGAN 4× 超分（推荐）

> 适用：`viking_walk_big.gif` / `viking_walk_small.gif` 的动作、角色都满意，**只想更清晰**。
> 产物：`viking_walk_big_clear.gif` / `viking_walk_small_clear.gif`（1024×1024×16 @ 8fps，约 2.2MB）

**为什么不用 HiResFix**：`sd-cli --hires` 的实现是「latent 放大 + 二次去噪重绘」。
- `hires-denoising-strength=0.15`：角色不变，但几乎不增加细节，仍然软；
- `0.3`：细节明显变好，但会改角色（实测彩虹辫子、盔角数量变化）；
- 加 IP-Adapter 锁角色：画面出现彩色边缘（chromatic aberration）。
所以「同一角色、只提升清晰度」用 **ESRGAN 4× + 降采样** 最稳，像素级超分不会改动作/身份。

```bash
cd ~/iso_gen
for tag in big small; do
  mkdir -p viking_${tag}_sr/{raw,frames}
  for f in viking_${tag}_final/frame_*.png; do
    b=$(basename "$f")
    /opt/StaticPy/tools/run.sh sr "$f" "viking_${tag}_sr/raw/$b"
    convert "viking_${tag}_sr/raw/$b" -resize 1024x1024 \
      -unsharp 0x0.5+0.4+0.005 "viking_${tag}_sr/frames/$b"
  done
  ffmpeg -y -framerate 8 -i "viking_${tag}_sr/frames/frame_%03d.png" \
    -vf "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a" \
    -loop 0 "viking_${tag}_sr/viking_walk_${tag}_sr.gif"
done

cp viking_big_sr/viking_walk_big_sr.gif     ~/viking_walk_big_clear.gif
cp viking_small_sr/viking_walk_small_sr.gif ~/viking_walk_small_clear.gif
cp ~/viking_walk_big_clear.gif   ~/iso_flutter/viking_walk_big_clear.gif
cp ~/viking_walk_small_clear.gif ~/iso_flutter/viking_walk_small_clear.gif
```

自检（已通过）：
```text
big  : 16 帧，平均变化 0.1878，近似静止 0/15
small: 16 帧，平均变化 0.1614，近似静止 0/15
```

---

## 10. 实验记录：Qwen 逐帧重绘（不推荐，人物会漂移）

> **结论：不用于正式资产。** 逐帧重绘会让脸/发色/装备跨帧变化（实测出现彩虹辫子、盔角数量变化），
> 且步幅会被改写；`viking_walk_hd.gif` 仅作实验产物保留。
> 正式「只变清晰、不改角色」请用 §9.4 的 ESRGAN 4×。
>
> 记录这条链路是为了说明：**单参考能保留单帧姿势，但不能保证 16 帧同一身份**。
> 如果要逐帧重绘，必须再加身份锁定（IP-Adapter / 角色 LoRA），否则一定会漂。

### 10.1 完整链路

```text
viking_ip_big/frame_001..016.png      # DreamShaper 8 + walkRL 0.35 + IP-Adapter 0.85
        │  Qwen-Image Edit（单参考，只传当前帧）
        ▼
qwen_oneref/f001..f016.png            # 干净 2D 卡通，保留原姿势
        │  BiRefNet 抠图 → 统一 bbox 裁剪 → 白底 640×640
        ▼
final16/frame_001..016.png
        │  ffmpeg 调色板 GIF @ 8fps
        ▼
viking_walk_hd.gif
```

### 10.2 逐帧重绘（核心命令）

```bash
cd ~/iso_flutter
mkdir -p ~/iso_gen/qwen_oneref/{cut16,final16}

PROMPT='convert this exact character into a clean 2D cartoon game character, keep the exact same body pose, walking phase, camera angle and composition; cute chibi male viking warrior, horned iron helmet, long braided blonde beard, brown leather armor with fur trim, leather boots, empty hands; thick clean outline, flat colors, plain pure white background; do not change the pose'

for i in $(seq -w 1 16); do
  out=$(ISO_SD_CLI=/opt/sd/build/bin/sd-cli \
    bin/img_qwen.sh "$PROMPT" \
      --ref ~/iso_gen/viking_ip_big/frame_0${i}.png \
      --size 768x768 --steps 10 --seed 42 --bg keep \
      --out ~/iso_gen/qwen_oneref --prefix f${i} 2>&1 | tail -1)
  cp "$out" ~/iso_gen/qwen_oneref/f${i}.png
done
```

- `--size 768x768`：比 512 清晰；单帧约 1.5–2 分钟（10 步）。
- `--bg keep`：保留白底，后面再统一抠图/裁剪。
- **不要**再加第二个 `--ref` 指向角色关键帧（会锁姿势）。

### 10.3 抠图、统一裁剪、拼 GIF

```bash
cd ~/iso_gen/qwen_oneref
# ① 抠透明
for i in $(seq -w 1 16); do
  bash /opt/static_comfyui/cpp/sd/bgremove.sh \
    "f${i}.png" "cut16/f${i}.png" transparent >/dev/null
done

# ② 16 帧 alpha 并集 bbox = 400x622+199+64；加 10px 边距 → 420x642+189+54
for i in $(seq 1 16); do
  ii=$(printf '%02d' "$i"); oo=$(printf '%03d' "$i")
  convert "cut16/f0${ii}.png" -crop 420x642+189+54 +repage \
    -resize x600 -background white -gravity center -extent 640x640 \
    "final16/frame_${oo}.png"
done

# ③ GIF
ffmpeg -y -framerate 8 -i final16/frame_%03d.png \
  -vf "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 viking_walk_hd.gif
cp viking_walk_hd.gif ~/iso_flutter/viking_walk_hd.gif
cp viking_walk_hd.gif ~/viking_walk_hd.gif
```

### 10.4 自检（已通过）

```bash
bin/motion.sh ~/iso_gen/qwen_oneref/final16 'frame_*.png'
# 帧数=16 平均变化=0.1795 峰值=第11个间隔 近似静止=0/15
```

- 画风：干净 2D 卡通、粗描边、平涂，脸和胡子清楚。
- 步态：16 帧完整循环，无静止帧；比 512 版清晰很多。
- 尺寸：640×640 × 16 帧 @ 8fps，约 1.2MB。

### 10.5 失败分支（别再踩）

| 方案 | 结果 |
|---|---|
| **Wan 2.1 VACE 1.3B 图生视频** | 人物转身、脸丢失、步态消失；加 OpenPose control-video 也救不回来。 |
| **Qwen 重绘传两个 `--ref`**（当前帧 + 角色关键帧） | 每帧都被拉回关键帧姿势，步幅被抹平，动画变“原地摆腿”。 |
| **DreamShaper + IP-Adapter 想直接出卡通** | IP-Adapter Plus 只传内容不传画风，结果仍是半写实。 |
| **ToonYou + `mm_v2_prefixed`** | 锁成红发女战士（披风/法球），换 prompt 无效。 |
| **ToonYou + `mm_sd15_v3`** | 红发女消失，但风格变半写实，并自动加披风/剑。 |
| **AnimateDiff 768×768 + ControlNet** | 显存不足（ControlNet 需 ~21GB，20GB 卡跑不动）。 |

---

## 11. 精灵图法：Nano Banana 4×4 重绘 + StaticPy 素材后处理（角色最稳）

> 适用：步态已经满意，但逐帧放大/重绘会让人物漂移。
> 做法：先把 16 帧拼成 **4×4 接触表**，让 Nano Banana 一次重绘成 **一张精灵图**；
> 16 个姿势在同一张图里，模型能同时看到全部姿势，身份/装备不会跨帧漂。
>
> 后处理全部用 **StaticPy ELF**（`cutout` / `align_head` / `pack_sprites` /
> `flatten` / `frames_to_gif` / `flip`），不再用 Pillow/ImageMagick/ffmpeg。
>
> 产物：
> - `~/iso_gen/nano_sprite/staticpy/atlas_right_4096.png`（4096×4096，4×4，RGBA）
> - `manifest_right.json` / `atlas_left_4096.png` / `manifest_left.json`
> - `aligned1024/f00..f15.png`（1024×1024，透明）
> - `preview_white_1024.gif`（预览）

### 11.1 准备 4×4 参考接触表

```bash
cd ~/iso_flutter
/opt/StaticPy/anim/pack_sprites \
  ~/iso_gen/sprite_ref_big.png ~/iso_gen/sprite_ref_big.json \
  512 512 0 0 512 512 4 0 ref_big \
  ~/iso_gen/viking_big_final/frame_*.png

/opt/StaticPy/anim/pack_sprites \
  ~/iso_gen/sprite_ref_small.png ~/iso_gen/sprite_ref_small.json \
  512 512 0 0 512 512 4 0 ref_small \
  ~/iso_gen/viking_small_final/frame_*.png
```

### 11.2 Nano Banana 重绘精灵图（4K）

```bash
cd ~/iso_flutter
bin/img_nano.sh "Redraw this exact 4x4 character sprite sheet as a clean, high-detail game sprite sheet. Keep EXACTLY the same 16 walking-cycle poses in the same row-major order and the same character design. Character: cute chibi male Viking warrior, horned iron helmet, long braided golden blonde hair and long braided golden blonde beard, brown leather armor with fur trim, leather boots, empty hands. Exactly 16 equal cells in a 4x4 grid, one full-body character per cell, same scale and same foot baseline, centered, no overlap, no cropping. Plain pure white background in every cell. Clean thick outlines, flat colors, sharp details, crisp edges. No text, no labels, no borders, no grid lines, no shadows, no extra characters, no weapons. Do not change the poses or the walk cycle; only increase clarity and detail." \
  --ref ~/iso_gen/sprite_ref_big.png --size 1:1 --res 4K \
  --out ~/iso_gen/nano_sprite --prefix viking_sprite
```

small 版把 `--ref` 换成 `~/iso_gen/sprite_ref_small.png`，并在 prompt 里加一句
`This is the SMALL-STEP walk version: keep the shorter stride exactly as shown.`

### 11.3 切 4×4、透明、对齐、atlas

```bash
export LD_LIBRARY_PATH=/opt/StaticPy/cpp/imgproc/build:${LD_LIBRARY_PATH:-}

SPRITE=$(ls -t ~/iso_gen/nano_sprite/viking_sprite_*.jpg | head -1)
WORK=~/iso_gen/nano_sprite/staticpy
rm -rf "$WORK"; mkdir -p "$WORK/cut" "$WORK/cells" "$WORK/aligned1024"

# 4K 白底 → 透明总图 aura_cut.png（不要用 cut/fNN 的顺序）
/opt/StaticPy/cutout "$SPRITE" "$WORK/cut" 1500

# 关键：从 aura_cut.png 按 4×4 行优先切格，避免帧序错乱
bin/split_grid "$WORK/cut/aura_cut.png" "$WORK/cells" 4 4
bin/align_head "$WORK/aligned1024" 1024 1024 512 990 "$WORK"/cells/f*.png

# 右向 / 左向 atlas + manifest
cd "$WORK"
/opt/StaticPy/anim/pack_sprites atlas_right_4096.png manifest_right.json \
  1024 1024 0 0 1024 1024 4 0 walk_right aligned1024/f*.png
/opt/StaticPy/anim/pack_sprites atlas_left_4096.png manifest_left.json \
  1024 1024 0 0 1024 1024 4 1 walk_left aligned1024/f*.png

# 白底预览 GIF
mkdir -p flat1024
for f in aligned1024/f*.png; do
  bin/flatten "$f" "flat1024/$(basename "$f")" 4294967295
done
/opt/StaticPy/anim/frames_to_gif preview_white_1024.gif 8 flat1024/f*.png
```

> 单帧/序列正反翻转用 `bin/flip in.png out.png`；左向 atlas 用 `pack_sprites ... FLIP=1`。
> 不要翻转整张 4×4 表，否则列顺序也会反转。

### 11.4 自检（已通过）

```bash
bin/motion.sh ~/iso_gen/nano_sprite/staticpy/aligned1024 'f*.png'
# big  : 16 帧，平均变化 ~0.1233，近似静止 0/15
bin/motion.sh ~/iso_gen/nano_sprite_small/staticpy/aligned1024 'f*.png'
# small: 16 帧，平均变化 ~0.1253，近似静止 0/15
```

- 角色：16 格同一张脸/发/盔/甲，跨帧不漂。
- 对齐：头盔中心 512.0–512.5（std ~0.24），脚底 989；不缩放。
- 步态：`split_grid` 行优先，帧序与旧 approved GIF 1:1（16/16）；big 步幅大，small 步幅小。
- atlas：4096×4096，4×4，1024/格，RGBA；左向由 `FLIP=1` 逐格镜像。
- 注意：这是 **重绘**，头盔铆钉/皮甲缝线等小细节会与旧版略有差异；
  若要保留旧版每一处细节，只能走逐帧方案，但会漂。
