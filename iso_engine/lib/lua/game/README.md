# game/sim —— 纯 Lua 游戏仿真（AI 可驱动核心）

**headless · 确定性 · 可回放 · 零协议**。agent 用 `luajit -e` 就能直接驱动/调试/试玩——
因为游戏与 agent **同处一个 LuaJIT 世界**。渲染宿主（Flutter / LÖVE）只**消费 `state()`**。

## API
```lua
local sim = require("sim")            -- 需 package.path 含 game/sim/
local g = sim.new()                    -- 新一局

g:key("right", true)                   -- 按键（持续）：up/down/left/right
g:key("right", false)
g:act("pick")                          -- 一次性动作：选中最近物件
g:step(1/60)                           -- 推进一帧（固定步长）
g:tickN(60)                            -- 推进 60 帧
g:goto(14, 14)                         -- 自动走到地面点（简单控制器，可回放）

local s = g:state()                    -- 世界状态（table）
print(sim.encode(s))                   -- 状态 → JSON
local g2 = sim.replay(g.log)           -- 用输入记录重放 → 同结果（确定性）
```

## CLI
```bash
luajit game/run.lua --script "goto:14,14;pick" --json --replay   # 指令用 ; 分隔
luajit game/run.lua --script "right:30;down:30" --trace --every 30
luajit game/run.lua --steps 120                                   # 无输入直推
#  指令： right:N / left:N / up:N / down:N / pick / goto:X,Y / wait:N
```

## agent 直接玩（无需任何协议）
```bash
luajit -e '
package.path = "game/sim/?.lua;" .. package.path
local sim = require("sim")
local g = sim.new()
g:key("right", true); g:key("down", true); g:tickN(30)
g:key("right", false); g:key("down", false)
g:goto(14, 14); g:act("pick")
assert(g.won, "应当到达目标")
print("won="..tostring(g.won).." tick="..g.tick)
'
```
→ **agent 跑一段 Lua = 玩一局 + 断言 + 可复现**（这就是"AI 自己玩游戏"）。

## 为什么这样做
- **Sim 纯 Lua** → 不依赖 Flutter/显示 → **headless 极快**（十万帧/秒级），适合 AI 大量试玩；
- **确定性 + 输入记录** → 一键复现 bug（`sim.replay`）；
- **状态内省**（`state()`/JSON）→ agent 读结构化世界，不必"猜像素"；
- **渲染解耦** → 换渲染宿主（Flutter↔LÖVE）**Sim 一行不改**。

## 文件
| 文件 | 说明 |
|---|---|
| `sim/world.lua` | 地图（地面范围/物件/目标）——纯数据 |
| `sim/sim.lua`   | 仿真：`new/key/act/step/tickN/goto/state/json/replay`（确定性）|
| `run.lua`       | CLI（脚本/直推/trace/回放校验）|

> 形状/时间线也可用 `iso_engine`（Dart/Lua）画；渲染端读 `state()`：`player/props/goal/tick/won`。
