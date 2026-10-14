#!/usr/bin/env bash
# dev.sh —— LÖVE 热重载：监控游戏目录下 *.lua，存盘即自动重启（砍掉手动重启等待）
# @usage bin/dev.sh [game/love|game/tetris]      # 默认 game/love
# @rule  只监听 .lua；改动保存后 ~0.6s 内重开窗口
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
game="${1:-game/love}"
dir="$root/$game"
[ -d "$dir" ] || { echo "找不到 $dir" >&2; exit 1; }
export DISPLAY="${DISPLAY:-:0}"

snap() { find "$dir" -type f -name '*.lua' -printf '%T@ %p\n' 2>/dev/null | sort; }

lovepid=""
start() { love "$dir" >"$HOME/iso_gen/dev.log" 2>&1 & lovepid=$!; }
trap '[ -n "$lovepid" ] && kill "$lovepid" 2>/dev/null || true' EXIT INT TERM

mkdir -p "$HOME/iso_gen"
last="$(snap)"
start
echo "[dev] 运行 $game（改 .lua 存盘即重载）"
while true; do
  sleep 0.6
  now="$(snap)"
  if [ "$now" != "$last" ]; then
    last="$now"
    kill "$lovepid" 2>/dev/null || true; wait "$lovepid" 2>/dev/null || true
    start
    echo "[dev] reloaded $(date +%T)"
  elif ! kill -0 "$lovepid" 2>/dev/null; then
    start
  fi
done
