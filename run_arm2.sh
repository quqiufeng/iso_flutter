#!/usr/bin/env bash
# 生成走路动画（sd.cpp / comfycli 路径，无 diffusers/torch/PIL）
# 关键参数：walk2 骨架 + openpose ControlNet + 运动 LoRA，SEED 42
# 用法： ./run_arm2.sh            # → $HOME/iso_gen/dw_anim/{frames,anim.gif}
#        OUT=dir W=512 H=512 ./run_arm2.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

export POSE_DIR="${POSE_DIR:-$HERE/poses/walk2}"   # openpose 骨架帧目录
export CONTROL_STRENGTH="${CONTROL_STRENGTH:-1.0}" # 逐帧 control 强度
export W="${W:-512}"; export H="${H:-512}"
export FRAMES="${FRAMES:-16}"; export FPS="${FPS:-8}"
export STEPS="${STEPS:-25}"; export CFG="${CFG:-7.5}"; export SEED="${SEED:-42}"
export OUT="${OUT:-$HOME/iso_gen/dw_anim}"
export PROMPT="${PROMPT:-a cute chibi cartoon knight, silver armor, red plume, short red cape, empty hands, walking to the right, side view, full body, arms swinging naturally in sync with the legs, plain white background, thick clean outline, flat colors, smooth 2d game character animation}"
export NEG="${NEG:-sword, weapon, shield, object in hand, arms crossed, folded arms, hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, static, gray background, scenery, objects, realistic, photo, 3d render}"

exec "$HERE/dw_anim.sh"
