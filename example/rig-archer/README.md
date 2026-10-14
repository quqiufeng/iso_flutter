# rig-archer —— AI 生成角色 → 切件 → 骨骼动画（端到端样例）

这是"**手绘卡通骨骼角色**"流水线的完整样例（LÖVE 运行时）：

```
① AI 生成（ComfyUI，手绘卡通·正面·A/T-pose）
      bin/img.sh "full body 2D game character, …, hand drawn cartoon, A-pose, plain white background" \
                 --size 768x1152 --bg transparent --out /tmp/hero
② 切件（按人体比例几何切割 → head/torso/armL/armR/legL/legR + parts.json）
      bin/cutparts.sh /tmp/hero/xxx.png /tmp/cut        # 比例不对就调 NECK/SHO_Y/HIP_Y/… 覆盖
③ 绑骨 + 动画（本引擎，数据/代码定义）
      iso_engine/lib/lua/rig.lua
④ 渲染/集成
      love example/rig-archer          # 窗口 demo（1=idle 2=walk）
      RIG_EXPORT=out.png love example/rig-archer   # 离屏出图
```

- 分件在 `parts/`；坐标（pivot/bone）来自 `cutparts.sh` 的 `parts.json`，已写进 `main.lua`。
- 换武器/换色：给 slot 加 `atts`（多附件）或 `color`，用 clip 的 slot 时间轴切换。
- **注意**：本例是**正面**角色——正面视角下"走路"只能靠摆臂+起伏逼近；游戏里若要多方向移动，**应生成侧视/3-4 视角色**。
