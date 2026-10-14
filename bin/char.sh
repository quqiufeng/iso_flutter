#!/usr/bin/env bash
# char.sh —— 从 CC0「分件」组装"可换武器/可染色"的角色动画帧（paper-doll）
#
# 素材：Free 2D Animated Vector Game Character Sprites（CC0）
#   下载 https://opengameart.org/sites/default/files/free_2d_animated_vector_game_character_sprites.zip
#   解压到 /opt/charpack/Free 2D Animated Vector Game Character Sprites
#
# 用法:
#   char.sh <preset> [tint-hex]
#     preset : 见下方 preset() 定义（u1/u2/u3 我方，e1/e2/e3 敌方…）
#     tint   : 可选，如 '#9ec6ff' 给我方上淡蓝、'#ff9a7a' 给敌方上暖红
# 输出:
#   game/love/assets/chars/<preset>_<anim>_<i>.png   (anim = walk/idle/hit/death)
#
# 说明：分件在 2048² 画布上**预对齐** → 同帧号直接叠加即成完整角色；
#       **换武器 = 换 Right weapons/weaponR* 件**；**换色 = tint**。
set -euo pipefail

PACK="${CHARPACK:-/opt/charpack/Free 2D Animated Vector Game Character Sprites}"
SRC="$PACK/Animated body parts"
OUT="${OUT:-$HOME/iso_flutter/game/love/assets/chars}"
ANIMS="${ANIMS:-walk idle hit death}"
TARGET_H="${TARGET_H:-200}"
PAD="${PAD:-40}"

preset() {  # 输出: "<head> <hair> <eyes> <mouth> <horn> <weapon>"（body 固定 body1；'-' 表示无）
  case "$1" in
    u1) echo "head1 hair1 eyes1 mouth1 -       weaponR1" ;;   # 我方·近战
    u2) echo "head2 hair2 eyes2 mouth2 horn2   weaponR2" ;;   # 我方·远程
    u3) echo "head3 hair3 eyes3 mouth3 horn3   weaponR3" ;;   # 我方·法师
    e1) echo "head1 hair2 eyes5 mouth5 horn5   weaponR1" ;;   # 敌方·小怪
    e2) echo "head2 hair1 eyes7 mouth1 horn1   weaponR2" ;;   # 敌方·射手
    e3) echo "head3 hair3 eyes3 mouth3 horn4   -"        ;;   # 敌方·巨兽（无武器）
    *)  echo "未知 preset: $1（可用: u1 u2 u3 e1 e2 e3）" >&2; return 1 ;;
  esac
}

name="$1"; tint="${2:-}"
read -r head hair eyes mouth horn weapon <<<"$(preset "$name")"

compose() {  # <anim> <frame> <out>
  local a="$1" f="$2" o="$3" L=()
  [ "$horn"   != "-" ] && L+=("$SRC/Horns/$horn/${a}_${f}.png")
  L+=("$SRC/Left wings/wingL1/${a}_${f}.png")
  L+=("$SRC/Left hands/handL1/${a}_${f}.png")
  L+=("$SRC/Left feet/footL1/${a}_${f}.png")
  L+=("$SRC/Bodies/body1/${a}_${f}.png")
  L+=("$SRC/Heads/$head/${a}_${f}.png")
  L+=("$SRC/Hairs/$hair/${a}_${f}.png")
  L+=("$SRC/Eyes/$eyes/${a}_${f}.png")
  L+=("$SRC/Mouths/$mouth/${a}_${f}.png")
  L+=("$SRC/Right feet/footR1/${a}_${f}.png")
  L+=("$SRC/Right hands/handR1/${a}_${f}.png")
  [ "$weapon" != "-" ] && L+=("$SRC/Right weapons/$weapon/${a}_${f}.png")
  L+=("$SRC/Right wings/wingR1/${a}_${f}.png")
  convert -background none "${L[@]}" -flatten "$o"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$OUT"

# 1) 组装所有帧（全尺寸）
for a in $ANIMS; do
  i=0
  for fp in "$SRC/Bodies/body1/${a}_"*.png; do
    fn=$(basename "$fp" .png); n=${fn##*_}
    compose "$a" "$n" "$tmp/${a}_${n}.png"
  done
done

# 2) 求所有帧的公共裁剪框（统一 → 不抖）
geom="$(for f in "$tmp"/idle_*.png "$tmp"/walk_*.png; do convert "$f" -fuzz 1% -format "%@\n" info:; done)"
minx=99999; miny=99999; maxx=0; maxy=0
while IFS= read -r g; do
  [ -z "$g" ] && continue
  W="${g%%x*}"; r="${g#*x}"; H="${r%%+*}"; xy="${r#*+}"; X="${xy%%+*}"; Y="${xy##*+}"
  (( X < minx )) && minx=$X; (( Y < miny )) && miny=$Y
  (( X+W > maxx )) && maxx=$((X+W)); (( Y+H > maxy )) && maxy=$((Y+H))
done <<<"$geom"
CW=$((maxx-minx+2*PAD)); CH=$((maxy-miny+2*PAD)); CX=$((minx-PAD)); CY=$((miny-PAD))

# 3) 裁剪 + 缩放 (+ 染色) → 输出
n=0
for f in "$tmp"/*.png; do
  bn=$(basename "$f")
  if [ -n "$tint" ]; then
    convert "$f" -crop "${CW}x${CH}+${CX}+${CY}" +repage -resize "x${TARGET_H}" \
            -fill "$tint" -colorize 65% "$OUT/${name}_${bn}"
  else
    convert "$f" -crop "${CW}x${CH}+${CX}+${CY}" +repage -resize "x${TARGET_H}" "$OUT/${name}_${bn}"
  fi
  n=$((n+1))
done
echo "组装完成: $name → $OUT (${n} 帧, 画框 ${CW}x${CH} ← ${CX},${CY}; tint=${tint:-无})"
