#!/usr/bin/env bash
# tts.sh — 文本转语音 → 音频文件（Kokoro / sherpa-onnx；可选克隆音色 CosyVoice3）。
# @usage bin/tts.sh "<文本>" [--out FILE.wav] [--sid N] [--voice <克隆音色名>] [--lang zh|en] [--mp3]
# 输出：把音频文件路径打印在最后一行（便于被调用）。
# 音色：中文女声 --sid 47（默认 zf_xiaoxiao）；英文 --sid 3（af_heart，0-19 为英文）。
set -euo pipefail
KOKORO_DIR="${KOKORO_DIR:-/data/models/kokoro-multi-lang-v1_0}"
SHERPA_BIN="${SHERPA_BIN:-/opt/sherpa-onnx/bin/sherpa-onnx-offline-tts}"
SHERPA_LIB="${SHERPA_LIB:-/opt/sherpa-onnx/lib}"
COSY="${COSYVOICE_SH:-/opt/my-agent/voice/cosyvoice.sh}"

TEXT=""; OUT=""; SID="${KOKORO_SID:-47}"; VOICE=""; MP3=0
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT="$2"; shift 2 ;;
  --sid) SID="$2"; shift 2 ;;
  --voice) VOICE="$2"; shift 2 ;;
  --lang) SID="$([ "$2" = en ] && echo 3 || echo "${KOKORO_SID:-47}")"; shift 2 ;;
  --mp3) MP3=1; shift ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \?//'; exit 0 ;;
  -*) shift ;;
  *) TEXT="${TEXT:+$TEXT }$1"; shift ;;
esac; done
[ -n "$TEXT" ] || { sed -n '2,5p' "$0" | sed 's/^# \?//' >&2; exit 2; }

OUT="${OUT:-/tmp/tts_$(date +%Y%m%d_%H%M%S).wav}"
mkdir -p "$(dirname "$OUT")"

ok=0
# ① 克隆音色（CosyVoice3，若指定且已注册）
if [ -n "$VOICE" ] && [ -x "$COSY" ]; then
  if "$COSY" synth "$VOICE" "$TEXT" "$OUT" >/dev/null 2>&1 && [ -s "$OUT" ]; then ok=1; fi
fi
# ② Kokoro（sherpa-onnx，首选）
if [ "$ok" != 1 ] && [ -x "$SHERPA_BIN" ] && [ -f "$KOKORO_DIR/model.onnx" ]; then
  if LD_LIBRARY_PATH="$SHERPA_LIB:${LD_LIBRARY_PATH:-}" "$SHERPA_BIN" \
    --kokoro-model="$KOKORO_DIR/model.onnx" \
    --kokoro-voices="$KOKORO_DIR/voices.bin" \
    --kokoro-tokens="$KOKORO_DIR/tokens.txt" \
    --kokoro-data-dir="$KOKORO_DIR/espeak-ng-data" \
    --kokoro-lexicon="$KOKORO_DIR/lexicon-us-en.txt,$KOKORO_DIR/lexicon-zh.txt" \
    --tts-rule-fsts="$KOKORO_DIR/date-zh.fst,$KOKORO_DIR/number-zh.fst" \
    --num-threads="${TTS_THREADS:-4}" --sid="$SID" \
    --output-filename="$OUT" "$TEXT" >/dev/null 2>&1 && [ -s "$OUT" ]; then ok=1; fi
fi
# ③ espeak-ng 兜底
if [ "$ok" != 1 ]; then espeak-ng -v cmn -w "$OUT" "$TEXT" 2>/dev/null && [ -s "$OUT" ] && ok=1 || true; fi
[ "$ok" = 1 ] || { echo "TTS 合成失败" >&2; exit 1; }

if [ "$MP3" = 1 ] && command -v ffmpeg >/dev/null 2>&1; then
  MP3F="${OUT%.wav}.mp3"
  ffmpeg -y -i "$OUT" "$MP3F" >/dev/null 2>&1 && OUT="$MP3F"
fi
echo "$OUT"
