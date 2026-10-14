# game/tetris —— 「水晶方块」(Tetris)，逻辑/渲染分离

**纯 Lua 仿真 + LÖVE 渲染**：逻辑在 `sim.lua`（确定性 / headless / 可回放 / **记忆每次落下的形状**），
`main.lua` 只消费 `state()` / `events` 做渲染、输入、特效。agent 用 `luajit` 即可直接玩/断言，**与游戏同处一个 Lua 世界**。

## 运行
```bash
love ~/iso_flutter/game/tetris          # 窗口版（触屏按钮 ← → ↻ ⇓ · 暂停 · 重开）
```

## Sim API（`sim.lua`）
```lua
package.path = "game/tetris/?.lua;" .. package.path
local sim = require("sim")

local g = sim.new({ seed = 123 })       -- 种子决定方块序列（确定性）
g:act("left")   -- 动作：left / right / rotate / soft / hard / pause（一次性）
g:step(1/60)    -- 推进一帧（重力；推不动则落子）
g:tickN(60)     -- 推进 60 帧

local s = g:state()          -- 世界状态（table）
print(sim.encode(s))         -- → JSON
print(g.history[1].type)     -- 落子记忆
local g2 = sim.replay(g.log, { seed = 123 })   -- 用动作记录重放 → 同结果（确定性）
```

**`state()` 字段**：`tick/seed/cols/rows/over/paused/score/lines/level`、`board`（已落方块）、
`cur`（当前块 `{t,x,y,m}`）、`next`、`queue`（随机预告队列）、`locks`、`history`。

**落子记忆 `g.history[i]`**（★ 每次落下的形状）：
```lua
{ n, tick, type, x, y, m = {{..}}, cells = {{x,y},..}, cleared, score }
```
`m` = 落定时的朝向矩阵，`x,y` = 左上角格坐标，`cells` = 占用的格单元，`cleared`/`score` = 该步消行数与分数。

**事件流 `g.events`**（渲染层每帧消费后 `g:clearEvents()`）：
`spawn` / `lock`（带 `rec`）/ `harddrop` / `clear`（`lines,rows,types`）/ `gameover`。

## agent 直接玩（headless，无窗口）
```bash
# CLI：--script 用 ; 分隔；left/right/rotate/soft/hard 可跟 :N 重复；wait:N 推 N 帧
luajit game/tetris/run.lua --seed 7 --script "rotate;left:2;hard;wait:40;right:3;hard" --history --replay

# 或进程内直接断言
luajit -e '
package.path = "game/tetris/?.lua;" .. package.path
local sim = require("sim")
local g = sim.new({ seed = 1 })
for i = 1, 8 do g:act("rotate"); g:act("hard") end
assert(g.history[1], "应当有落子记忆")
print("locks="..#g.history.."  score="..g.score.."  over="..tostring(g.over))
'
```
→ **agent 跑一段 Lua = 玩一局 + 断言 + 复现**（这就是"AI 自己玩游戏"）。

## 文件桥（手机/远程「接口驱动」，不靠截图）
LÖVE 端每帧把状态写成 JSON、并读取指令文件；agent 只要读写这两个文件即可**看牌 + 操作**：
```bash
# 默认目录（Android app 私有外部目录，adb 可读写）；可用环境变量 BRIDGE_DIR 覆盖
DIR=/sdcard/Android/data/org.love2d.android/files

# ① 看：当前块 + 后续方块序列 + 棋盘 + 分数（接口拿到，不用截图）
adb shell cat $DIR/tetris_state.json
#  {"cur":{"t":"s","x":4,"y":7,"m":[[..]]},"next":"s","queue":["s","l","s"],
#   "board":["..........", ...], "score":0,"lines":0,"locks":0,"over":false}

# ② 玩：写指令（每行一条；内容变了才执行；# 行是注释）
printf 'act:rotate\nact:left\nact:hard\n' | adb shell "cat > $DIR/tetris_cmd.txt"
```
指令：`act:left|right|rotate|soft|hard|pause`、`restart`、`hold`（冻结重力）/`release`（恢复）。
> 用网络/文件桥驱动时，因读写有延迟，方块会被重力提前锁死 → **先发 `hold` 冻结重力**，由 agent 用 `hard` 完全掌控落子。

**闭环**：`读 state → 决策 → 写 cmd → (游戏执行) → 再读`。示例 agent 见 `~/iso_gen/tetris/drive_phone.py`
（读 `queue` 做 1 步前瞻落子；实测 **130 块 · 消 38 行 · 11200 分**）。
headless 同款 AI：`~/iso_gen/tetris/ai.lua`（145 块 · 43 行 · 12400 分，可回放）。

## 在 Android 上运行
**LÖVE 就是个「载入器」**：官方 normal APK 不含游戏，把 `.love` 交给它即可。
```bash
# 1) 装运行时（只需一次）：官方 normal APK（无内嵌游戏）
adb install love-11.5-android.apk        # 包名 org.love2d.android
# 2) 打包游戏
cd game/tetris && zip -q -9 -r /tmp/tetris.love main.lua sim.lua conf.lua assets
# 3) 推到 app 私有外部目录（scoped storage 下本应用可读；/sdcard/lovegame 那条官方 fallback 已不可用）
adb push /tmp/tetris.love /sdcard/Android/data/org.love2d.android/files/tetris.love
# 4) 用 intent 启动
adb shell am start -n org.love2d.android/.GameActivity -a android.intent.action.VIEW \
  -d "file:///sdcard/Android/data/org.love2d.android/files/tetris.love" -t application/octet-stream
```
> 官方载入器找游戏的顺序：① intent 传入 → ② APK assets 里 `game.love`（embed 版）→ ③ `/sdcard/lovegame/main.lua`。
> 我们走 ①；`-embed` APK 是把它做成「自带游戏的独立 App」时才用。

### 打「真 App」（自带图标、点开即玩）
要正式发布就用 **love-android 源码 + embed**（需 Android **SDK + NDK + JDK**）：
1. `git clone https://github.com/love2d/love-android`；
2. 游戏放进 `app/src/main/assets/game.love`；
3. 改 `AndroidManifest.xml`（应用名/图标/竖屏锁定）与 `build.gradle`（applicationId/版本/签名）；
4. `./gradlew assembleNormalRelease` → APK（上架再出 `.aab`）；
5. `adb install` 装机。
> 首次要下 ~1–2GB SDK/NDK 并编 LÖVE 本体（几十分钟）；之后改游戏只需重打包（快）。

## 文件
| 文件 | 说明 |
|---|---|
| `sim.lua`  | 纯 Lua 仿真：`new/act/step/tickN/ghostY/state/json/clearEvents/replay` + 落子记忆 + 事件流（确定性） |
| `main.lua` | LÖVE 渲染/输入/特效：只消费 `state()`/`events`；触屏控制条 + 截图钩子（`CAPTURE_DIR`/`AUTO`） |
| `run.lua`  | headless CLI（脚本驱动 / trace / JSON / 落子记忆 / 回放校验） |

> 关键：换渲染宿主（LÖVE↔其它）**Sim 一行不改**；逻辑改动只动 `sim.lua`。
