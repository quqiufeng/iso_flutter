#!/usr/bin/env bash
# img_qwen.sh — 本地 Qwen-Image 2.1（sd.cpp / sd-cli）：文生图 + **参考图编辑（保形象一致）**。
# @usage bin/img_qwen.sh "<prompt>" [--ref IMG ...] [--size WxH] [--steps N] [--seed N] [--cfg F]
#                        [--out DIR] [--prefix NAME] [--bg transparent|white|keep]
# 用途：与 bin/img_nano.sh 组成「Nano 出高质量关键图 → 本地 Qwen 出同一角色的新帧/新动作」链路。
#   --ref  参考图（可多张）；给参考图=编辑模式，保持人物/形象一致（无需联网、免费）
#   --bg   transparent=BiRefNet 抠透明（默认）；white/keep=原样
# 模型：/data/models/image/qwen-image-2.1-Q6_K.gguf 等（可用环境变量覆盖）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SD_CLI="${ISO_SD_CLI:-/opt/sd/build-dl/bin/sd-cli}"
QWEN_MODEL="${ISO_QWEN_MODEL:-/data/models/image/qwen-image-2.1-Q6_K.gguf}"
QWEN_VAE="${ISO_QWEN_VAE:-/data/models/image/qwen_image_2.1_vae_bf16.safetensors}"
QWEN_LLM="${ISO_QWEN_LLM:-/data/models/image/Qwen3VL-8B-Instruct-Q4_K_M.gguf}"
QWEN_VISION="${ISO_QWEN_VISION:-/data/models/image/mmproj-Qwen3VL-8B-Instruct-F16.gguf}"
BGREM="${ISO_BGREMOVE:-/opt/static_comfyui/cpp/sd/bgremove.sh}"
GPU_LIB="$(dirname "$SD_CLI")"

usage(){ sed -n '2,7p' "$0" | sed 's/^# \?//' >&2; exit 2; }

PROMPT=""; REFS=(); SIZE="1024x1024"; STEPS=""; SEED="42"; CFG="6.0"
OUTD="$ROOT/assets_gen"; PREFIX="qwen"; BG="transparent"
while [ $# -gt 0 ]; do case "$1" in
  --ref) REFS+=("$2"); shift 2 ;;
  --size) SIZE="$2"; shift 2 ;;
  --steps) STEPS="$2"; shift 2 ;;
  --seed) SEED="$2"; shift 2 ;;
  --cfg) CFG="$2"; shift 2 ;;
  --out) OUTD="$2"; shift 2 ;;
  --prefix) PREFIX="$2"; shift 2 ;;
  --bg) BG="$2"; shift 2 ;;
  -h|--help) usage ;;
  -*) shift ;;
  *) PROMPT="${PROMPT:+$PROMPT }$1"; shift ;;
esac; done
[ -n "$PROMPT" ] || usage
[ -x "$SD_CLI" ] || { echo "找不到 sd-cli：$SD_CLI（ISO_SD_CLI 可指定）" >&2; exit 1; }
for i in "${!REFS[@]}"; do
  r="${REFS[$i]}"; [ -f "$r" ] || { echo "参考图不存在：$r" >&2; exit 1; }
  REFS[$i]="$(realpath "$r")"
done

W="${SIZE%x*}"; H="${SIZE#*x}"
# 默认步数：编辑 12 / 文生图 20
[ -n "$STEPS" ] || { if [ "${#REFS[@]}" -gt 0 ]; then STEPS=12; else STEPS=20; fi; }

mkdir -p "$OUTD"
STAMP=$(date +%Y%m%d_%H%M%S)
RAW="$OUTD/${PREFIX}_${STAMP}_raw.png"
FINAL="$OUTD/${PREFIX}_${STAMP}.png"

ARGS=( --diffusion-model "$QWEN_MODEL" --vae "$QWEN_VAE" --llm "$QWEN_LLM"
       -p "$PROMPT" --cfg-scale "$CFG" --sampling-method euler --steps "$STEPS"
       --offload-to-cpu -W "$W" -H "$H" -s "$SEED" -o "$RAW" )
if [ "${#REFS[@]}" -gt 0 ]; then
  ARGS+=( --llm_vision "$QWEN_VISION" )
  for r in "${REFS[@]}"; do ARGS+=( -r "$r" ); done
fi

echo "[img_qwen] ${#REFS[@]} refs · ${W}x${H} · ${STEPS} steps · seed ${SEED} → $RAW" >&2
( cd "$GPU_LIB" && LD_LIBRARY_PATH="$GPU_LIB" GGML_BACKEND_PATH="$GPU_LIB/libggml-cuda.so" \
    "$SD_CLI" "${ARGS[@]}" ) >&2

if [ "$BG" = "transparent" ] && [ -x "$BGREM" ]; then
  bash "$BGREM" "$RAW" "$FINAL" transparent >/dev/null 2>&1 || cp "$RAW" "$FINAL"
else
  cp "$RAW" "$FINAL"
fi
echo "$FINAL"
