#!/usr/bin/env bash
# iso.sh — 等距图 native 引擎：出图/出动画（PNG / GIF / MP4）
# @usage bin/iso.sh render <图名> [--ss N] [--lift 0..1] [--theme dark|light] [--out DIR]
# @usage bin/iso.sh anim   <图名> [--frames N] [--ss N] [--motion] [--theme ..] [--out DIR]
# 生成的"要发出去的文件路径"打印在最后一行（render→png；anim→gif）。
# 引擎：Dart + Lua（iso_engine/lib），渲染：Flutter 离屏；无浏览器/node/JS。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ISO_BIN:-$ROOT/app/build/linux/x64/release/bundle/iso_app}"
DISP="${DISPLAY:-:0}"
FF="$(command -v ffmpeg || true)"

CMD="${1:-}"; shift || true
FIG="${1:-}"; shift || true
[ -n "$CMD" ] && [ -n "$FIG" ] || { echo "用法: iso.sh render|anim <图名> [...]" >&2; exit 2; }

OUTD="/tmp/iso_out"; SS=2; LIFT=""; FRAMES=120; MOTION=0; THEME="light"
while [ $# -gt 0 ]; do case "$1" in
  --out) OUTD="$2"; shift 2 ;; --ss) SS="$2"; shift 2 ;; --lift) LIFT="$2"; shift 2 ;;
  --frames) FRAMES="$2"; shift 2 ;; --motion) MOTION=1; shift ;; --theme) THEME="$2"; shift 2 ;;
  -*) shift ;; *) shift ;; esac; done

[ -x "$BIN" ] || { echo "找不到程序 $BIN（先在 app/ 里 flutter build linux --release）" >&2; exit 1; }
mkdir -p "$OUTD"

ENVS=(DISPLAY="$DISP" ISO_EXPORT="$FIG" ISO_SS="$SS" ISO_THEME="$THEME")
[ -n "$LIFT" ] && ENVS+=(ISO_LIFT="$LIFT")
[ "$MOTION" = 1 ] && ENVS+=(ISO_MOTION=1)
one(){ env "${ENVS[@]}" ISO_FRAME="$1" ISO_N="$2" ISO_OUT="$3" timeout 120 "$BIN" >/dev/null 2>&1; }

case "$CMD" in
  render)
    PNG="$OUTD/${FIG}.png"; one 0 1 "$PNG"
    [ -f "$PNG" ] || { echo "出图失败（图名 $FIG 是否存在？）" >&2; exit 1; }
    echo "$PNG" ;;
  anim)
    [ -n "$FF" ] || { echo "需要 ffmpeg" >&2; exit 1; }
    FD="$OUTD/${FIG}_frames"; rm -rf "$FD"; mkdir -p "$FD"
    env "${ENVS[@]}" ISO_BATCH=1 ISO_N="$FRAMES" ISO_OUT="$FD" timeout 600 "$BIN" >/dev/null 2>&1
    GIF="$OUTD/${FIG}.gif"; MP4="$OUTD/${FIG}.mp4"
    ffmpeg -y -framerate 60 -i "$FD/f%04d.png" \
      -vf "scale=iw:ih:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$GIF" >/dev/null 2>&1
    ffmpeg -y -framerate 60 -i "$FD/f%04d.png" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$MP4" >/dev/null 2>&1
    echo "$MP4"; echo "$GIF" ;;
  *) echo "未知命令: $CMD" >&2; exit 2 ;;
esac
