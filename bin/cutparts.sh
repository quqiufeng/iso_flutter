#!/usr/bin/env bash
# cutparts.sh —— 把「手绘卡通正面角色」按人体比例切成骨骼分件（head/torso/armL/armR/legL/legR）
#
# 思路：角色正面、平色、带描边 → 用「区域矩形 ∩ 角色 alpha」切件。
#      每个分件裁到其区域矩形（**保持与原图坐标对齐**），故 pivot = 关节 - 区域左上角；
#      绑骨时把分件以 pivot 对齐到骨骼原点即可。输出 parts.json 供 rig 使用。
#
# 用法: cutparts.sh <char.png> <outdir> [KEY=VAL ...]
# 比例（相对 bbox，可覆盖）：
#   NECK 脖线 | HEAD_HW 头半宽 | TORSO_HW 躯干半宽 | SHO_HW 肩距中线 | SHO_Y 肩高
#   ARM_H 手臂带宽 | HIP_Y 髋/裙摆高
set -euo pipefail

char="$1"; out="$2"; shift 2 || true
for kv in "$@"; do case "$kv" in *=*) export "$kv" ;; esac; done

NECK=${NECK:-0.32}       # 脖线（head 底 / torso 顶）
HEAD_HW=${HEAD_HW:-0.24} # 头半宽（含头发/兜帽）
TORSO_HW=${TORSO_HW:-0.22}
SHO_HW=${SHO_HW:-0.20}   # 肩距中线的水平距离（=臂 pivot x）
SHO_Y=${SHO_Y:-0.45}     # 肩高（=臂 pivot y / 手臂带中心）
ARM_H=${ARM_H:-0.14}     # 手臂带高度
HIP_Y=${HIP_Y:-0.70}     # 髋高（=躯干底 / 腿顶）

[ -f "$char" ] || { echo "找不到: $char" >&2; exit 1; }
mkdir -p "$out"

geo=$(convert "$char" -format "%@" info: 2>/dev/null)
W=${geo%%x*}; _r=${geo#*x}; H=${_r%%+*}; _xy=${_r#*+}; OFFX=${_xy%%+*}; OFFY=${_xy##*+}
[ -n "${W:-}" ] || { echo "无法取 bbox" >&2; exit 1; }
convert "$char" -crop "${W}x${H}+${OFFX}+${OFFY}" +repage "$out/_char.png"
convert "$out/_char.png" -alpha extract "$out/_alpha.png"

px(){ awk "BEGIN{printf \"%d\", ($1)}"; }
cx=$(px "$W*0.5"); neck=$(px "$H*$NECK"); shoY=$(px "$H*$SHO_Y")
headHW=$(px "$W*$HEAD_HW"); torsoHW=$(px "$W*$TORSO_HW"); shoHW=$(px "$W*$SHO_HW")
hipY=$(px "$H*$HIP_Y"); armH=$(px "$H*$ARM_H")
armY0=$((shoY-armH/2)); armY1=$((shoY+armH/2))

declare -A X0 X1 Y0 Y1 PVX PVY
# head
X0[head]=$((cx-headHW)); X1[head]=$((cx+headHW)); Y0[head]=0; Y1[head]=$neck
PVX[head]=$((cx-X0[head])); PVY[head]=$neck
# torso
X0[torso]=$((cx-torsoHW)); X1[torso]=$((cx+torsoHW)); Y0[torso]=$neck; Y1[torso]=$hipY
PVX[torso]=$((cx-X0[torso])); PVY[torso]=$((hipY-neck))
# arms（左：0..肩；右：肩..W）
X0[armL]=0; X1[armL]=$((cx-shoHW)); Y0[armL]=$armY0; Y1[armL]=$armY1
PVX[armL]=$((cx-shoHW-X0[armL])); PVY[armL]=$((shoY-armY0))
X0[armR]=$((cx+shoHW)); X1[armR]=$W; Y0[armR]=$armY0; Y1[armR]=$armY1
PVX[armR]=0; PVY[armR]=$((shoY-armY0))
# legs（左：中左；右：中右）
X0[legL]=$((cx-torsoHW)); X1[legL]=$cx; Y0[legL]=$hipY; Y1[legL]=$H
PVX[legL]=$(((cx-torsoHW+cx)/2-X0[legL])); PVY[legL]=0
X0[legR]=$cx; X1[legR]=$((cx+torsoHW)); Y0[legR]=$hipY; Y1[legR]=$H
PVX[legR]=$(((cx+cx+torsoHW)/2-X0[legR])); PVY[legR]=0

json=""
for p in head torso armL armR legL legR; do
  x0=${X0[$p]}; x1=${X1[$p]}; y0=${Y0[$p]}; y1=${Y1[$p]}
  w=$((x1-x0)); h=$((y1-y0)); { [ "$w" -gt 0 ] && [ "$h" -gt 0 ]; } || { echo "空区域 $p" >&2; continue; }
  convert -size "${W}x${H}" xc:black -fill white -draw "rectangle $x0,$y0 $((x1-1)),$((y1-1))" "$out/_reg.png"
  convert "$out/_alpha.png" "$out/_reg.png" -compose multiply -composite "$out/_pa.png"
  convert "$out/_char.png" \( "$out/_pa.png" \) -alpha off -compose CopyOpacity -composite \
          -crop "${w}x${h}+${x0}+${y0}" +repage "$out/$p.png"
  json="$json\"$p\":{\"file\":\"$p.png\",\"x\":$x0,\"y\":$y0,\"w\":$w,\"h\":$h,\"pivotX\":${PVX[$p]},\"pivotY\":${PVY[$p]}}"
  [ "$p" != "legR" ] && json="$json,"
done

cat > "$out/parts.json" <<JSON
{
  "image": "$(basename "$char")",
  "charW": $W, "charH": $H,
  "joints": {
    "neck": [$cx, $neck],
    "shoulderL": [$((cx-shoHW)), $shoY], "shoulderR": [$((cx+shoHW)), $shoY],
    "hip": [$cx, $hipY]
  },
  "parts": { $json }
}
JSON
rm -f "$out/_char.png" "$out/_alpha.png" "$out/_reg.png" "$out/_pa.png"
echo "切件完成 → $out (bbox ${W}x${H})"
