#!/usr/bin/env bash
# 复现 diffwalk_arm2.gif（逐帧 RMSE=0，与存档一致）
# 关键：IP=0（不挂参考图），CNSCALE=0.55，walk2 姿势，512 输出，seed 42
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

IP=0 FLIP="${FLIP:-0}" POSES="$HERE/poses/walk2" W=512 H=768 FRAMES=16 STEPS=25 SEED=42 CNSCALE=0.55 \
PROMPT="a cute chibi cartoon knight, silver armor, red plume, short red cape, empty hands, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation" \
NEG="sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, extra arms, static, gray background, scenery, background objects, realistic, photo, 3d render" \
OUT="${OUT:-$HERE/diffwalk_arm2_regen.gif}" /data/venv/bin/python "$HERE/dw_cn.py"
