#!/usr/bin/env bash
# 对拍：Dart 引擎 与 Lua 引擎 对同一张图输出**逐字符相同**（PASS/FAIL 退出码）。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DART="$(command -v dart || echo "$HOME/development/flutter/bin/dart")"

d=$(cd "$DIR" && "$DART" run kit_parity.dart 2>/dev/null | grep '^FILL=')
l=$(cd "$DIR/../lib/lua" && luajit "$DIR/kit_parity.lua" | grep '^FILL=')

if [ -z "$d" ] || [ -z "$l" ]; then
  echo "PARITY FAIL ❌（未拿到输出：dart='${d:0:20}' lua='${l:0:20}'）" >&2
  exit 1
fi
if [ "$d" = "$l" ]; then
  echo "PARITY PASS ✅  (fill 逐字符相同，${#d} 字符)"
else
  echo "PARITY FAIL ❌"
  echo "dart: $(printf '%s' "$d" | cut -c1-100)"
  echo "lua : $(printf '%s' "$l" | cut -c1-100)"
  exit 1
fi
