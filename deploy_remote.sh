#!/usr/bin/env bash
# deploy_remote.sh — 按 staticpy_comfyui → StaticPy → 本项目 顺序部署（只传 sh/二进制/.so/缺失模型）
#
# 用法:
#   ./deploy_remote.sh list                 # 列出清单
#   ./deploy_remote.sh create               # 用镜像模板 caf6a2ee... 新开实例并等待 running
#   ./deploy_remote.sh check [instance_id]  # 检查远端缺哪些文件（不传）
#   ./deploy_remote.sh upload [instance_id] # 只传缺失文件（FORCE=1 强制覆盖）
#   ./deploy_remote.sh smoke [instance_id]  # 远端跑 pose_walk / ldd 冒烟
#   ./deploy_remote.sh all                  # create（无实例时）+ upload + check
#
# 环境:
#   INSTANCE_ID=...       指定实例；否则读 ~/.iso_deploy_instance
#   IMAGE_ID=...          默认 caf6a2ee-3141-4902-bb81-9bbad56f12f7
#   GPU_MODEL=...         默认 "NVIDIA GeForce RTX 4090 48G"
#   DATA_CENTER_ID=1
#   FORCE=1               覆盖远端已有文件
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$ROOT/deploy_manifest.tsv"
XGC_DIR="${XGC_DIR:-/opt/static_comfyui}"
IMAGE_ID="${IMAGE_ID:-caf6a2ee-3141-4902-bb81-9bbad56f12f7}"
IMAGE_TYPE="${IMAGE_TYPE:-private}"
GPU_MODEL="${GPU_MODEL:-NVIDIA GeForce RTX 4090 48G}"
DATA_CENTER_ID="${DATA_CENTER_ID:-1}"
INSTANCE_FILE="$HOME/.iso_deploy_instance"
INSTANCE_ID="${INSTANCE_ID:-$(cat "$INSTANCE_FILE" 2>/dev/null || true)}"
FORCE="${FORCE:-0}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

load_instance() {
  if [ -n "${1:-}" ]; then INSTANCE_ID="$1"; fi
  [ -n "$INSTANCE_ID" ] || die "没有实例：先 create，或传 instance_id / INSTANCE_ID"
  echo "$INSTANCE_ID" > "$INSTANCE_FILE"
}

ssh_info() {
  ( cd "$XGC_DIR"; set -a; . ./.env; set +a; python3 xgc_ctl.py info "$INSTANCE_ID" )
}

resolve_ssh() {
  local info
  info="$(ssh_info)"
  H="$(printf '%s\n' "$info" | awk '/ssh_domain:/{print $2}')"
  P="$(printf '%s\n' "$info" | awk '/ssh_port:/{print $2}')"
  PW="$(printf '%s\n' "$info" | awk '/password:/{print $2}')"
  [ -n "$H" ] && [ -n "$P" ] && [ -n "$PW" ] || die "拿不到 SSH 信息"
}

ssh_run() {
  sshpass -p "$PW" ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=20 -p "$P" "root@$H" "$*" </dev/null
}

scp_file() {
  sshpass -p "$PW" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -P "$P" "$1" "root@$H:$2" </dev/null
}

scp_dir() {
  sshpass -p "$PW" scp -q -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -P "$P" "$1/." "root@$H:$2/" </dev/null
}

remote_exists() { ssh_run "test -e '$1'"; }
remote_isdir() { ssh_run "test -d '$1'"; }

local_abs() {
  case "$1" in /*) echo "$1" ;; *) echo "$ROOT/$1" ;; esac
}

create_instance() {
  need python3
  [ -f "$XGC_DIR/.env" ] || die "缺少 $XGC_DIR/.env"
  mkdir -p "$HOME/iso_gen"
  (
    cd "$XGC_DIR"; set -a; . ./.env; set +a
    local name="iso-assets-$(date +%m%d-%H%M)"
    echo ">>> deploy image=$IMAGE_ID type=$IMAGE_TYPE gpu=$GPU_MODEL dc=$DATA_CENTER_ID name=$name"
    python3 xgc_ctl.py deploy --name "$name" --image "$IMAGE_ID" --image-type "$IMAGE_TYPE" \
      --gpu-model "$GPU_MODEL" --data-center-id "$DATA_CENTER_ID"
  ) | tee "$HOME/iso_gen/iso_deploy.out"
  local id
  id="$(sed -n 's/^instance_id=//p' "$HOME/iso_gen/iso_deploy.out" | tail -1)"
  [ -n "$id" ] || die "部署失败（常见：可用GPU不足 / 镜像ID失效）"
  INSTANCE_ID="$id"; echo "$id" > "$INSTANCE_FILE"
  ( cd "$XGC_DIR"; set -a; . ./.env; set +a; python3 xgc_ctl.py wait "$id" --status running )
  echo "instance_id=$id"
}

list_manifest() {
  printf '%-5s %-10s %-55s %s\n' KIND SIZE LOCAL REMOTE
  while IFS=$'\t' read -r kind local remote note; do
    case "$kind" in \#*|"") continue ;; esac
    [ -n "${remote:-}" ] || continue
    local p; p="$(local_abs "$local")"
    local sz="?"
    if [ "$kind" = link ]; then sz="link"; elif [ -e "$p" ]; then sz="$(du -sh "$p" 2>/dev/null | cut -f1)"; fi
    printf '%-5s %-10s %-55s %s\n' "$kind" "$sz" "$p" "$remote"
  done < "$MANIFEST"
}

check_manifest() {
  resolve_ssh
  local miss=0
  while IFS=$'\t' read -r kind local remote note; do
    case "$kind" in \#*|"") continue ;; esac
    [ -n "${remote:-}" ] || continue
    local p; p="$(local_abs "$local")"
    local ok="OK"
    if [ "$kind" = dir ]; then remote_isdir "$remote" || ok="MISSING"
    elif [ "$kind" = link ]; then ssh_run "test -L '$remote' && test -e '$remote'" || ok="MISSING"
    else remote_exists "$remote" || ok="MISSING"; fi
    [ "$ok" = MISSING ] && miss=$((miss+1))
    printf '%-7s %s\n' "$ok" "$remote"
  done < "$MANIFEST"
  echo "--- missing: $miss ---"
}

upload_manifest() {
  resolve_ssh
  local n=0
  while IFS=$'\t' read -r kind local remote note; do
    case "$kind" in \#*|"") continue ;; esac
    [ -n "${remote:-}" ] || continue
    local p; p="$(local_abs "$local")"
    if [ "$kind" = link ]; then
      if ssh_run "test -L '$remote' && test -e '$remote'" && [ "$FORCE" != 1 ]; then echo "SKIP  $remote (symlink 已存在)"; continue; fi
      ssh_run "mkdir -p '$(dirname "$remote")'; ln -sfn '$p' '$remote'"
      echo "LINK  $remote -> $p"
      n=$((n+1)); continue
    fi
    [ -e "$p" ] || die "本地不存在: $p"
    if [ "$kind" = dir ]; then
      if remote_isdir "$remote" && [ "$FORCE" != 1 ]; then echo "SKIP  $remote (已存在)"; continue; fi
      ssh_run "mkdir -p '$remote'"
      scp_dir "$p" "$remote"
    else
      if remote_exists "$remote" && [ "$FORCE" != 1 ]; then echo "SKIP  $remote (已存在)"; continue; fi
      ssh_run "mkdir -p '$(dirname "$remote")'"
      scp_file "$p" "$remote"
    fi
    echo "PUT   $remote"
    n=$((n+1))
  done < "$MANIFEST"
  echo "--- uploaded: $n ---"
}

smoke() {
  resolve_ssh
  ssh_run "export LD_LIBRARY_PATH=/opt/StaticPy/cpp/imgproc/build:/opt/iso_flutter/bin:/opt/iso_flutter/lib:/opt/sd/build-dl/bin:\$LD_LIBRARY_PATH; \
    echo '--- libs ---'; ldd /opt/StaticPy/cpp/imgproc/build/libimgproc.so | grep 'not found' || echo imgproc_OK; \
    ldd /opt/iso_flutter/bin/libmobilesam.so | grep 'not found' || echo mobilesam_OK; \
    echo '--- pose_walk ---'; rm -rf /tmp/pose_smoke; mkdir -p /tmp/pose_smoke; \
    OUTDIR=/tmp/pose_smoke HAND=1 LEGX=0.5 /opt/StaticPy/anim/pose_walk >/tmp/pose_smoke.log 2>&1; \
    tail -3 /tmp/pose_smoke.log; ls /tmp/pose_smoke | head; \
    echo '--- tools ---'; command -v ffmpeg jq convert 2>/dev/null || true"
}

case "${1:-}" in
  list) list_manifest ;;
  create) create_instance ;;
  check) shift; load_instance "${1:-}"; check_manifest ;;
  upload) shift; load_instance "${1:-}"; upload_manifest ;;
  smoke) shift; load_instance "${1:-}"; smoke ;;
  all) shift; load_instance "${1:-}"; [ -n "$INSTANCE_ID" ] || create_instance; upload_manifest; check_manifest ;;
  *) sed -n '2,18p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac
