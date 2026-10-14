#!/usr/bin/env bash
# motion.sh —— 动效自检：对帧序列算「相邻帧 RMSE」运动曲线，判断动画是否真在动/峰值在哪/是否卡住
# @usage bin/motion.sh <frames-dir> [glob]      # 默认 glob=*.png
# 输出：帧数 / 平均变化 / 峰值间隔 / 近似静止帧数 + 一行运动曲线（.:-=+*#%@ 由弱到强）
set -euo pipefail
dir="${1:?用法: bin/motion.sh <frames-dir> [glob]}"
glob="${2:-*.png}"
[ -d "$dir" ] || { echo "目录不存在: $dir" >&2; exit 1; }
cd "$dir"
mapfile -t frames < <(ls $glob 2>/dev/null | sort -V)
n=${#frames[@]}
if [ "$n" -lt 2 ]; then echo "帧太少($n)"; exit 1; fi

tmp="$(mktemp -p "$HOME/iso_gen")"
for ((i = 1; i < n; i++)); do
  d=$(compare -metric RMSE "${frames[i - 1]}" "${frames[i]}" null: 2>&1 | sed -E 's/.*\((.*)\)/\1/' || true)
  echo "${d:-0}" >>"$tmp"
done
awk '
{ v=$1+0; a[NR]=v; s+=v; if(v>m){m=v;mi=NR} if(v<0.002)near++ }
END{
  n=NR; if(n==0){print "无有效帧"; exit}
  printf "帧数=%d  平均变化=%.4f  峰值=第%d个间隔(%.4f)  近似静止=%d/%d\n", n+1, s/n, mi, m, near, n;
  printf "运动曲线: ";
  for(i=1;i<=n;i++){ r=(m>0)?a[i]/m:0; idx=int(r*9); if(idx>9)idx=9; printf "%s", substr(".:-=+*#%@", idx+1, 1) }
  print "";
}' "$tmp"
rm -f "$tmp"
