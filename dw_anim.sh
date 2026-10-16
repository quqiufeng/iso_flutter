#!/bin/bash
# dw_anim.sh —— 替代 dw_cn.py（diffusers）：走 sd.cpp + comfycli（StaticPy），零 torch/PIL/numpy。
# 流程：walk_poses.py(imgproc 出骨架帧) → anim.sh(comfycli AnimateDiff + 逐帧 ControlNet + 运动 LoRA)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SDDIR="${SDDIR:-/opt/static_comfyui}"

# 骨架帧目录（默认用随附的；设 GEN=1 则先跑 walk_poses.py 现生成）
POSE_DIR="${POSE_DIR:-$DIR/poses/walk2}"
if [ "${GEN:-0}" = "1" ]; then
  POSE_DIR="${OUT_POSE:-$HOME/iso_gen/poses}"
  OUTDIR="$POSE_DIR" LEGX="${LEGX:-1.0}" ARMX="${ARMX:-1.0}" YUP="${YUP:-0}" python3 "$DIR/walk_poses.py"
fi

OUT="${OUT:-$HOME/iso_gen/dw_anim}"
W="${W:-512}"; H="${H:-512}"; FRAMES="${FRAMES:-16}"; FPS="${FPS:-8}"
STEPS="${STEPS:-25}"; CFG="${CFG:-7.5}"; SEED="${SEED:-42}"
PROMPT="${PROMPT:-a cute chibi cartoon knight, silver armor, red plume, short red cape, empty hands, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation}"
NEG="${NEG:-sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, extra arms, static, gray background, scenery, background objects, realistic, photo, 3d render}"

# —— sd.cpp 后端资产 ——
export MODEL="${MODEL:-/data/models/image/video/toonyou_alpha3.safetensors}"
export VAE="${VAE:-/data/models/image/video/vae-ft-mse.safetensors}"
export MOTION="${MOTION:-/data/models/image/video/mm_v2_prefixed.safetensors}"
export LORA="${LORA:-/data/models/image/video/walkRL_diff.safetensors}"
export LORA_STRENGTH="${LORA_STRENGTH:-1.0}"
export CONTROL_NET="${CONTROL_NET:-/data/models/image/controlnet/control_openpose-fp16.safetensors}"
export CONTROL_DIR="$POSE_DIR"
export CONTROL_STRENGTH="${CONTROL_STRENGTH:-1.0}"
export NEG

echo "[dw_anim] poses=$POSE_DIR  out=$OUT  ${W}x${H} x${FRAMES}@${FPS}  steps=$STEPS seed=$SEED"
bash "$SDDIR/anim.sh" "$PROMPT" "$OUT" "$W" "$H" "$FRAMES" "$FPS" "$STEPS" "$CFG" "$SEED"
