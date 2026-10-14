#!/usr/bin/env bash
# img.sh — 生成游戏素材（位图）。基于 static_comfyui 的 backup.sh（Z-Image Turbo，HiRes 两阶段）+ BiRefNet 抠图。
# @usage bin/img.sh "<prompt>" [--kind sprite|prop|icon|tile|scene|ui] [--size WxH] [--style <lora>[:w]]
#                    [--bg transparent|white|green|black|keep] [--seed N] [--out DIR] [--prefix] [--upscale]
# 输出：把最终 PNG 路径打印在最后一行（render 风格，便于被调用）。
# 说明：素材默认 512 方图 + 透明背景 + 不加"人像"质量前缀；--prefix 才加"等距线稿"前缀；--style 走 LoRA。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP="${ISO_SD_BACKUP:-/opt/static_comfyui/cpp/sd/backup.sh}"
BGREM="${ISO_BGREMOVE:-/opt/static_comfyui/cpp/sd/bgremove.sh}"

usage(){ sed -n '2,5p' "$0" | sed 's/^# \?//' >&2; exit 2; }

PROMPT=""; KIND="sprite"; SIZE=""; STYLE=""; BG="transparent"; SEED=""; OUTD="$ROOT/assets_gen"; PREFIX=0; UPSCALE=0
while [ $# -gt 0 ]; do case "$1" in
  --kind) KIND="$2"; shift 2 ;;
  --size) SIZE="$2"; shift 2 ;;
  --style) STYLE="$2"; shift 2 ;;
  --bg) BG="$2"; shift 2 ;;
  --seed) SEED="$2"; shift 2 ;;
  --out) OUTD="$2"; shift 2 ;;
  --prefix) PREFIX=1; shift ;;
  --upscale) UPSCALE=1; shift ;;
  -h|--help) usage ;;
  -*) shift ;;
  *) PROMPT="${PROMPT:+$PROMPT }$1"; shift ;;
esac; done
[ -n "$PROMPT" ] || usage
[ -x "$BACKUP" ] || { echo "找不到图生成脚本：$BACKUP（ISO_SD_BACKUP 可指定）" >&2; exit 1; }

# 素材档尺寸（未给 --size 时按 --kind）
if [ -z "$SIZE" ]; then case "$KIND" in
  icon) SIZE=512x512 ;; sprite) SIZE=512x512 ;; prop) SIZE=768x768 ;;
  tile) SIZE=512x512 ;; scene) SIZE=1920x1080 ;; ui) SIZE=768x512 ;; *) SIZE=512x512 ;; esac; fi
W="${SIZE%x*}"; H="${SIZE#*x}"

# 素材画风（等距/线稿，非人像）；仅 --prefix 时加
ASSET_PREFIX="isometric game asset, clean vector line art, flat colors, crisp outlines, plain background, single object, centered"
[ "$PREFIX" = 1 ] && PROMPT="$ASSET_PREFIX, $PROMPT"

mkdir -p "$OUTD"
STAMP=$(date +%Y%m%d_%H%M%S)
RAW="$OUTD/${KIND}_${STAMP}_raw.png"
FINAL="$OUTD/${KIND}_${STAMP}.png"

echo "→ 生成素材：${KIND} ${W}x${H}  bg=${BG}"
ENVS=(SKIP_QUALITY_PREFIX=1 NO_QUALITY_PREFIX=1 "CFG_SCALE=${CFG_SCALE:-3.0}")
[ -n "$SEED" ] && ENVS+=("SEED=$SEED")
ARGS=("$PROMPT" "$RAW" "$W" "$H")
[ -n "$STYLE" ] && ARGS+=(--lora "$STYLE")
[ "$UPSCALE" = 1 ] && ARGS+=(--upscale)
env "${ENVS[@]}" "$BACKUP" "${ARGS[@]}"

# backup.sh 会给输出名自动加它自己的时间戳 → 取本次最新生成的 *_raw*.png
RAW="$(ls -t "$OUTD"/*_raw*.png 2>/dev/null | head -1 || true)"
[ -n "$RAW" ] && [ -f "$RAW" ] || { echo "未找到生成的原始图" >&2; exit 1; }
FINAL="${RAW/_raw/}" # 去掉 _raw 即最终名

# 背景处理（透明/白/绿/黑默认走抠图；keep 直接留原图）
if [ "$BG" = "keep" ] || [ ! -x "$BGREM" ]; then
  cp "$RAW" "$FINAL"
else
  "$BGREM" "$RAW" "$FINAL" "$BG" >/dev/null 2>&1 || cp "$RAW" "$FINAL"
fi
echo "$FINAL"
