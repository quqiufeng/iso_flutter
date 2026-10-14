#!/usr/bin/env bash
# img_nano.sh —— Nano Banana（Google Gemini 图像）生成 / 编辑。走 apimart.ai（异步任务）
# @usage bin/img_nano.sh "<prompt>" [--model ID] [--ref IMG ...] [--size AR] [--res 1K|2K|4K] [--n N] [--out DIR] [--prefix NAME]
#   --model 默认 gemini-nano-banana-2.1（官方版，可多张；-ext 为按张计费单张版）
#   --ref   参考图（可多张，做"同一角色/编辑"一致性）
#   --size  宽高比，如 3:4 / 1:1 / 16:9（不传=跟随参考图/自动）
#   --res   分辨率档 1K/2K/4K（默认 2K）
#   --n     出图张数（官方版 1-4；默认 1）
# 密钥：~/.env 的 APIMART_API_KEY
# 输出：把生成的图片路径逐个打印在最后
set -euo pipefail
[ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }
: "${APIMART_API_KEY:?需要在 ~/.env 设置 APIMART_API_KEY}"
API="https://api.apimart.ai/v1"

MODEL="gemini-nano-banana-2.1"; OUT="./assets_gen"; PREFIX="nano"
SIZE=""; RES="2K"; N=1; REFS=(); PROMPT=""
while [ $# -gt 0 ]; do case "$1" in
  --model) MODEL="$2"; shift 2 ;;
  --ref) REFS+=("$2"); shift 2 ;;
  --size) SIZE="$2"; shift 2 ;;
  --res|--resolution) RES="$2"; shift 2 ;;
  --n) N="$2"; shift 2 ;;
  --out) OUT="$2"; shift 2 ;;
  --prefix) PREFIX="$2"; shift 2 ;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) PROMPT="${PROMPT:+$PROMPT }$1"; shift ;;
esac; done
[ -n "$PROMPT" ] || { echo "需要 prompt" >&2; exit 2; }
mkdir -p "$OUT"; ts=$(date +%Y%m%d_%H%M%S)

# 组装请求体（参考图 base64 大 → 用临时文件，避免 argv 过长）
tmp=$(mktemp)
jq -n --arg m "$MODEL" --arg p "$PROMPT" --arg r "$RES" --argjson n "$N" \
  '{model:$m, prompt:$p, resolution:$r, n:$n}' > "$tmp"
[ -n "$SIZE" ] && { jq --arg s "$SIZE" '. + {size:$s}' "$tmp" > "$tmp.2"; mv "$tmp.2" "$tmp"; }
if [ "${#REFS[@]}" -gt 0 ]; then
  echo '[]' > "$tmp.urls"
  for r in "${REFS[@]}"; do
    case "${r,,}" in *.png) mt=image/png ;; *.jpg|*.jpeg) mt=image/jpeg ;; *.webp) mt=image/webp ;;
      *) echo "参考图仅支持 png/jpg/webp: $r" >&2; exit 1 ;; esac
    { printf 'data:%s;base64,' "$mt"; base64 -w0 "$r"; } > "$tmp.blob"
    jq --rawfile u "$tmp.blob" '. + [$u]' "$tmp.urls" > "$tmp.u2" && mv "$tmp.u2" "$tmp.urls"
  done
  jq --slurpfile u "$tmp.urls" '. + {image_urls:$u[0]}' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
fi
tmpb=$(mktemp); printf '%s' "$(cat "$tmp")" > "$tmpb"

sub=$(curl -s --max-time 120 -X POST "$API/images/generations" \
  -H "Authorization: Bearer $APIMART_API_KEY" -H "Content-Type: application/json" --data-binary @"$tmpb")
rm -f "$tmp" "$tmp.2" "$tmp.blob" "$tmp.urls" "$tmp.u2" "$tmpb"
tid=$(echo "$sub" | jq -r '.data[0].task_id // empty')
[ -n "$tid" ] || { echo "提交失败：$(echo "$sub" | head -c 400)" >&2; exit 1; }
echo "任务 $tid 提交，轮询中…" >&2

# 轮询（3-5s，最多 ~3 分钟）
for i in $(seq 1 60); do
  sleep 4
  q=$(curl -s --max-time 60 "$API/tasks/$tid" -H "Authorization: Bearer $APIMART_API_KEY")
  st=$(echo "$q" | jq -r '.data.status // "?"')
  case "$st" in
    completed) echo "$q" > "$OUT/.last_$ts.json"
      mapfile -t urls < <(echo "$q" | jq -r '.data.result.images[].url[]? // empty')
      [ "${#urls[@]}" -gt 0 ] || { echo "完成但无图：$(echo "$q" | head -c 300)" >&2; exit 1; }
      k=0
      for u in "${urls[@]}"; do
        k=$((k+1)); ext="${u##*.}"; case "$ext" in png|jpg|jpeg|webp) : ;; *) ext=png ;; esac
        f="$OUT/${PREFIX}_${ts}_${k}.${ext}"
        curl -s --max-time 120 -o "$f" "$u"; echo "$f"
      done
      exit 0 ;;
    failed) echo "任务失败：$(echo "$q" | jq -c '.data.error // .')" >&2; exit 1 ;;
    pending|processing) : ;;
    *) echo "未知状态 $st：$(echo "$q" | head -c 200)" >&2 ;;
  esac
done
echo "超时" >&2; exit 1
