#!/usr/bin/env bash
# img_nano.sh —— 用 Nano Banana（Google Gemini 图像，经老张API）生成 / 编辑图片
# @usage bin/img_nano.sh "<prompt>" [--model ID] [--ref IMG ...] [--out DIR] [--prefix NAME]
#   --model  默认 gemini-nano-banana-2.1（可换 gemini-3.1-flash-image 等）
#   --ref    参考图（可多张，做"同一角色/编辑"的一致生成）；支持 png/jpg/webp
#   --out    输出目录（默认 ./assets_gen）
#   --prefix 文件名前缀（默认 nano）
# 密钥：~/.env 里的 LAOZHANG_API_KEY
# 输出：把生成的图片路径打印在最后一行（render 风格）
set -euo pipefail
[ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }
: "${LAOZHANG_API_KEY:?需要在 ~/.env 设置 LAOZHANG_API_KEY}"
API="https://api.laozhang.ai/v1/chat/completions"

MODEL="gemini-nano-banana-2.1"; OUT="./assets_gen"; PREFIX="nano"; REFS=(); PROMPT=""
while [ $# -gt 0 ]; do case "$1" in
  --model) MODEL="$2"; shift 2 ;;
  --ref) REFS+=("$2"); shift 2 ;;
  --out) OUT="$2"; shift 2 ;;
  --prefix) PREFIX="$2"; shift 2 ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) PROMPT="${PROMPT:+$PROMPT }$1"; shift ;;
esac; done
[ -n "$PROMPT" ] || { echo "需要 prompt" >&2; exit 2; }
mkdir -p "$OUT"; ts=$(date +%Y%m%d_%H%M%S)

# 组装 content：文本 + 参考图(data URL)
content=$(jq -n --arg p "$PROMPT" '[{type:"text", text:$p}]')
for r in "${REFS[@]:-}"; do
  [ -z "$r" ] && continue
  [ -f "$r" ] || { echo "参考图不存在: $r" >&2; exit 1; }
  case "${r,,}" in *.png) mt=image/png ;; *.jpg|*.jpeg) mt=image/jpeg ;; *.webp) mt=image/webp ;;
    *) echo "参考图仅支持 png/jpg/webp: $r" >&2; exit 1 ;; esac
  b64=$(base64 -w0 "$r")
  content=$(jq -n --argjson c "$content" --arg u "data:$mt;base64,$b64" \
    '$c + [{type:"image_url", image_url:{url:$u}}]')
done

body=$(jq -n --arg m "$MODEL" --argjson c "$content" '{model:$m, stream:false, messages:[{role:"user", content:$c}]}')
resp=$(curl -s --max-time 300 "$API" -H "Authorization: Bearer $LAOZHANG_API_KEY" \
  -H "Content-Type: application/json" -d "$body")
if [ "$(echo "$resp" | jq -r '.error // empty')" != "" ]; then
  echo "API 错误: $(echo "$resp" | jq -c '.error')" >&2; exit 1
fi
url=$(echo "$resp" | jq -r '.choices[0].message.content // ""' | grep -oE 'data:image/[a-zA-Z]+;base64,[A-Za-z0-9+/=]+' | head -1 || true)
if [ -z "$url" ]; then echo "响应无图片：$(echo "$resp" | head -c 400)" >&2; exit 1; fi
mt="${url#data:}"; mt="${mt%%;*}"; ext="${mt#image/}"; [ "$ext" = "jpeg" ] && ext=jpg
b64="${url#*base64,}"
f="$OUT/${PREFIX}_${ts}.${ext}"
echo "$b64" | base64 -d > "$f"
echo "生成: $f ($(identify -format '%wx%h' "$f" 2>/dev/null))"
echo "$f"
