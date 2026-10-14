# game/love —— LÖVE 集成（开源 Lua 2D 引擎）

把开源的 **LÖVE**（`love`，LuaJIT + SDL/OpenGL 的 2D 引擎）**集成进本项目**当游戏运行时，
**复用我们已有的 Lua 与素材**：

| 复用 | 来自 |
|---|---|
| 游戏逻辑（纯 Lua Sim） | `iso_engine/lib/lua/game/battle.lua` |
| 精灵素材（SD 生成） | `app/assets/sprites/*.png`（`bin/img.sh`） |
| 中文字体 | 仓耳今楷 |

**运行**（需 `love` 11.x，`apt install love`）：
```bash
love ~/iso_flutter/game/love
# 1/2/3 选兵 · 点左半场布兵 · R 重开
```

**说明**
- 逻辑仍是**纯 Lua**（`battle.lua`），**同一份**被 `luajit`（headless 测试/agent 驱动）与 LÖVE（渲染）共用。
- 渲染用 LÖVE（OpenGL）：地面网格 + 精灵（`love.graphics.draw`）+ HUD（`love.graphics.print`）。
- LÖVE 的沙箱：`love.graphics.newImage/newFont` 只读游戏目录 → 本项目用 `io.open` 读字节 + `love.filesystem.newFileData` 载入外部素材/字体。
- **角色动画**按 LÖVE 标准做法重做（精灵帧 / 分件骨骼），见后续。
