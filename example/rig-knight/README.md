# rig-knight —— Nano Banana 生成 → 抠图 → 切件 → 骨骼动画

流水线（角色母图来自 apimart.ai 的 `gemini-nano-banana-2.1`，**参考图保证同一角色**）：
1. 生成 3/4 视手绘卡通骑士母图（`bin/img_nano.sh`，3:4 / 2K，浅灰底）
2. 抠图：`/opt/static_comfyui/cpp/sd/bgremove.sh`（BiRefNet）→ 透明 PNG
3. 切件：`bin/cutparts.sh <cut.png> <out> POSE=apose NECK=… SHO_Y=… HIP_Y=… ARM_OUT=…`
4. 绑骨：`main.lua`（坐标取自 parts.json）+ `iso_engine/lib/lua/rig.lua`
5. 运行：`love example/rig-knight`（1=idle 2=walk 3=attack）；出图 `RIG_EXPORT=out.png love …`
