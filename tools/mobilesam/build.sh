#!/bin/bash
# Build libmobilesam.so (MobileSAM encoder/decoder, ONNX Runtime).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
ORT_INC="${ORT_INC:-/data/venv/onnxruntime-linux-x64-gpu-1.20.1/include}"
mkdir -p "$ROOT/bin"
g++ -O2 -std=c++17 -fPIC -shared \
  "$DIR/mobilesam.cpp" "$DIR/mobilesam_capi.cpp" \
  -I"$DIR" -I/opt/StaticPy/cpp/birefnet -I"$ORT_INC" \
  -L/usr/local/lib -l:libonnxruntime.so.1 \
  -o "$ROOT/bin/libmobilesam.so"
echo "built: $ROOT/bin/libmobilesam.so"
