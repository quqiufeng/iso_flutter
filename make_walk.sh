#!/usr/bin/env bash
# make_walk.sh — big/small 走路 GIF 一键出图
#
# Nano 永远在本地调用；低清/后处理在本地或远端执行。
# 默认使用已验证的 16 帧姿势表（Viking big/small），Nano 只按 --prompt 换角色/高清。
# 姿势表默认固定模板；要换姿势，先用 dw_anim.sh 生成新的 ref，再传 --ref-big/--ref-small。
#
# 用法:
#   ./make_walk.sh --local --name knight --prompt "cute chibi knight, ..."
#   ./make_walk.sh --name knight --prompt "..." --instance <id>
#   ./make_walk.sh --local --sprite-big 4k_big.jpg --sprite-small 4k_small.jpg  # 跳过 Nano
#
# 输出:
#   ~/<name>_big.gif / ~/<name>_small.gif / *_left.gif
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL=0; NAME="hero"; PROMPT="cute chibi knight, full closed silver helmet with blue plume, blue and silver plate armor, brown leather boots, empty hands, no weapons"
NANO_PROMPT=""; REF_BIG="$HOME/iso_gen/sprite_ref_big.png"; REF_SMALL="$HOME/iso_gen/sprite_ref_small.png"
SPRITE_BIG=""; SPRITE_SMALL=""; INSTANCE_ID="${INSTANCE_ID:-$(cat "$HOME/.iso_deploy_instance" 2>/dev/null || true)}"
NANO_RES="4K"; NANO_SIZE="1:1"

usage() { sed -n '2,13p' "$0" | sed 's/^# \?//'; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL=1; shift ;;
    --name) NAME="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --nano-prompt) NANO_PROMPT="$2"; shift 2 ;;
    --ref-big) REF_BIG="$2"; shift 2 ;;
    --ref-small) REF_SMALL="$2"; shift 2 ;;
    --sprite-big) SPRITE_BIG="$2"; shift 2 ;;
    --sprite-small) SPRITE_SMALL="$2"; shift 2 ;;
    --instance) INSTANCE_ID="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "未知参数: $1" >&2; usage ;;
  esac
done
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "name 只能包含字母/数字/_/-" >&2; exit 1; }
[ -n "$PROMPT" ] || { echo "需要 --prompt" >&2; exit 1; }

WORK_ROOT="$HOME/iso_gen/${NAME}_make"
mkdir -p "$WORK_ROOT"

# ---------- Nano（永远本地） ----------
nano_one() {
  local tag="$1" ref="$2" out="$3" prompt="$4"
  mkdir -p "$out"
  bin/img_nano.sh "$prompt" --ref "$ref" --size "$NANO_SIZE" --res "$NANO_RES" --out "$out" --prefix "${NAME}_${tag}" >&2
  ls -t "$out/${NAME}_${tag}"_*.jpg 2>/dev/null | head -1
}

build_nano_prompt() {
  local tag="$1"
  local p="${NANO_PROMPT:-Redraw this exact 4x4 character sprite sheet as a clean, high-detail game sprite sheet. Keep EXACTLY the same 16 walking-cycle poses in the same row-major order and the same body proportions and silhouette. Character: ${PROMPT}. Exactly 16 equal cells in a 4x4 grid, one full-body character per cell, same scale and same foot baseline, centered, no overlap, no cropping. Plain pure white background in every cell. Clean thick outlines, flat colors, sharp details, crisp edges. No text, no labels, no borders, no grid lines, no shadows, no extra characters. Do not change the poses or the walk cycle; only change the character design and increase clarity.}"
  [ "$tag" = small ] && p="$p This is the SMALL-STEP walk version: keep the shorter stride exactly as shown."
  printf '%s' "$p"
}

if [ -z "$SPRITE_BIG" ] || [ -z "$SPRITE_SMALL" ]; then
  [ -f "$REF_BIG" ] || { echo "缺少姿势参考: $REF_BIG" >&2; exit 1; }
  [ -f "$REF_SMALL" ] || { echo "缺少姿势参考: $REF_SMALL" >&2; exit 1; }
  echo ">>> Nano big (local)"
  SPRITE_BIG="$(nano_one big "$REF_BIG" "$WORK_ROOT/nano_big" "$(build_nano_prompt big)")"
  echo ">>> Nano small (local)"
  SPRITE_SMALL="$(nano_one small "$REF_SMALL" "$WORK_ROOT/nano_small" "$(build_nano_prompt small)")"
fi
[ -n "$SPRITE_BIG" ] && [ -n "$SPRITE_SMALL" ] || { echo "Nano 没有产出 4K 图" >&2; exit 1; }
echo "sprite_big=$SPRITE_BIG"
echo "sprite_small=$SPRITE_SMALL"

# ---------- 本地后处理 ----------
post_local() {
  local tag="$1" sprite="$2"
  local work="$HOME/iso_gen/${NAME}_${tag}_final"
  rm -rf "$work"; mkdir -p "$work/cut" "$work/cells" "$work/aligned1024"
  export LD_LIBRARY_PATH="/opt/StaticPy/cpp/imgproc/build:$ROOT/bin:$HOME/iso_gen/lib:${LD_LIBRARY_PATH:-}"
  /opt/StaticPy/cutout "$sprite" "$work/cut" 1500
  "$ROOT/bin/split_grid" "$work/cut/aura_cut.png" "$work/cells" 4 4
  "$ROOT/bin/align_head" "$work/aligned1024" 1024 1024 512 990 "$work"/cells/f*.png
  (
    cd "$work"
    /opt/StaticPy/anim/pack_sprites atlas_right_4096.png manifest_right.json 1024 1024 0 0 1024 1024 4 0 walk_right aligned1024/f*.png
    mkdir -p work512/cells work512/flat
    /opt/StaticPy/anim/pack_sprites work512/atlas_512.png work512/manifest_512.json 1024 1024 0 0 512 512 4 0 walk_right aligned1024/f*.png
    "$ROOT/bin/split_grid" work512/atlas_512.png work512/cells 4 4
    for f in work512/cells/f*.png; do "$ROOT/bin/flatten" "$f" "work512/flat/$(basename "$f")" 4294967295; done
    /opt/StaticPy/anim/frames_to_gif "$HOME/${NAME}_${tag}.gif" 8 work512/flat/f*.png
    "$ROOT/bin/flip" "$HOME/${NAME}_${tag}.gif" "$HOME/${NAME}_${tag}_left.gif"
  )
  echo "gif: $HOME/${NAME}_${tag}.gif"
}

# ---------- 远端后处理 ----------
resolve_ssh() {
  [ -n "$INSTANCE_ID" ] || { echo "远程模式需要 --instance / INSTANCE_ID" >&2; exit 1; }
  local info
  info="$(cd /opt/static_comfyui; set -a; . ./.env; set +a; python3 xgc_ctl.py info "$INSTANCE_ID")"
  H="$(printf '%s\n' "$info" | awk '/ssh_domain:/{print $2}')"
  P="$(printf '%s\n' "$info" | awk '/ssh_port:/{print $2}')"
  PW="$(printf '%s\n' "$info" | awk '/password:/{print $2}')"
  [ -n "$H" ] && [ -n "$P" ] && [ -n "$PW" ] || { echo "拿不到 SSH 信息" >&2; exit 1; }
}
ssh_run() { sshpass -p "$PW" ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$P" "root@$H" "$*" </dev/null; }
ssh_script() { sshpass -p "$PW" ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$P" "root@$H" "$*"; }
scp_file() { sshpass -p "$PW" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$P" "$1" "root@$H:$2" </dev/null; }

post_remote() {
  resolve_ssh
  local tag
  for tag in big small; do
    local sprite_var="SPRITE_${tag^^}"; local sprite="${!sprite_var}"
    local rd="/root/iso_gen/${NAME}_nano_${tag}"
    ssh_run "mkdir -p '$rd'"
    scp_file "$sprite" "$rd/"
  done
  ssh_script "NAME='$NAME' bash -s" <<'REMOTE'
set -euo pipefail
export LD_LIBRARY_PATH=/opt/StaticPy/cpp/imgproc/build:/opt/iso_flutter/bin:/opt/iso_flutter/lib:/opt/sd/build-dl/bin:${LD_LIBRARY_PATH:-}
cd /opt/iso_flutter
for tag in big small; do
  SPRITE=$(ls -t /root/iso_gen/${NAME}_nano_${tag}/*.jpg | head -1)
  WORK=/root/iso_gen/${NAME}_${tag}_final
  rm -rf "$WORK"; mkdir -p "$WORK/cut" "$WORK/cells" "$WORK/aligned1024"
  /opt/StaticPy/cutout "$SPRITE" "$WORK/cut" 1500
  /opt/iso_flutter/bin/split_grid "$WORK/cut/aura_cut.png" "$WORK/cells" 4 4
  /opt/iso_flutter/bin/align_head "$WORK/aligned1024" 1024 1024 512 990 "$WORK"/cells/f*.png
  (
    cd "$WORK"
    /opt/StaticPy/anim/pack_sprites atlas_right_4096.png manifest_right.json 1024 1024 0 0 1024 1024 4 0 walk_right aligned1024/f*.png
    mkdir -p work512/cells work512/flat
    /opt/StaticPy/anim/pack_sprites work512/atlas_512.png work512/manifest_512.json 1024 1024 0 0 512 512 4 0 walk_right aligned1024/f*.png
    /opt/iso_flutter/bin/split_grid work512/atlas_512.png work512/cells 4 4
    for f in work512/cells/f*.png; do /opt/iso_flutter/bin/flatten "$f" "work512/flat/$(basename "$f")" 4294967295; done
    /opt/StaticPy/anim/frames_to_gif "/root/iso_gen/${NAME}_${tag}.gif" 8 work512/flat/f*.png
    /opt/iso_flutter/bin/flip "/root/iso_gen/${NAME}_${tag}.gif" "/root/iso_gen/${NAME}_${tag}_left.gif"
  )
done
ls -lh /root/iso_gen/${NAME}_*.gif
REMOTE
  mkdir -p "$HOME/iso_gen/${NAME}_remote"
  for tag in big small; do
    sshpass -p "$PW" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$P" "root@$H:/root/iso_gen/${NAME}_${tag}.gif" "$HOME/iso_gen/${NAME}_remote/" </dev/null
    sshpass -p "$PW" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$P" "root@$H:/root/iso_gen/${NAME}_${tag}_left.gif" "$HOME/iso_gen/${NAME}_remote/" </dev/null
    cp "$HOME/iso_gen/${NAME}_remote/${NAME}_${tag}.gif" "$HOME/${NAME}_${tag}.gif"
    cp "$HOME/iso_gen/${NAME}_remote/${NAME}_${tag}_left.gif" "$HOME/${NAME}_${tag}_left.gif"
  done
}

if [ "$LOCAL" = 1 ]; then
  post_local big "$SPRITE_BIG"
  post_local small "$SPRITE_SMALL"
else
  post_remote
fi
echo "DONE"
ls -lh "$HOME/${NAME}_big.gif" "$HOME/${NAME}_small.gif" "$HOME/${NAME}_big_left.gif" "$HOME/${NAME}_small_left.gif"
