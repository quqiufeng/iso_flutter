#!/usr/bin/env bash
# 生成大步幅正常走路（512x512x16）
# 关键：IP=0（不挂参考图），POSE_FLIP=1（翻转骨架 → 步态正确，非太空步），
#       CNSCALE=0.55，walk2 骨架，SEED 42
# 用法： ./run_arm2.sh              # → diffwalk_arm2_big.gif
#        OUT=x.gif ./run_arm2.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

IP=0 POSE_FLIP="${POSE_FLIP:-1}" POSES="$HERE/poses/walk2" W=512 H=768 FRAMES=16 STEPS=25 SEED=42 CNSCALE=0.55 \
PROMPT="a cute chibi cartoon knight, silver armor, red plume, short red cape, empty hands, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation" \
NEG="sword, weapon, shield, broom, brush, object in hand, back accessory, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, extra arms, static, gray background, scenery, background objects, realistic, photo, 3d render" \
OUT="${OUT:-$HERE/diffwalk_arm2_big.gif}" /data/venv/bin/python "$HERE/dw_cn.py"
