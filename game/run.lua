-- run.lua —— 跑一局等距 Sim（纯 Lua，headless）。用 luajit game/run.lua [...]
-- 选项：
--   --steps N          无输入直推 N 帧
--   --script "a,b,c"   指令序列：
--                        right:N / left:N / up:N / down:N   （按住 N 帧）
--                        pick                                （选中最近物件）
--                        goto:X,Y                            （自动走到地面点）
--   --trace            每 N 帧（--every）打印一行状态
--   --every N          trace 间隔（默认 30）
--   --json             最后打印完整 state JSON
--   --replay           跑完后用输入记录重放一遍，校验一致性（确定性）
package.path = (arg[0]:gsub("[^/]*$", "")) .. "sim/?.lua;" .. package.path
local sim = require("sim")

local opts = { steps = 0, script = "", trace = false, every = 30, json = false, replay = false }
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--steps" then i = i + 1; opts.steps = tonumber(arg[i]) or 0
    elseif a == "--script" then i = i + 1; opts.script = arg[i] or ""
    elseif a == "--trace" then opts.trace = true
    elseif a == "--every" then i = i + 1; opts.every = tonumber(arg[i]) or 30
    elseif a == "--json" then opts.json = true
    elseif a == "--replay" then opts.replay = true
    end
    i = i + 1
  end
end

local g = sim.new()
local dt = 1 / 60

local function traceLine()
  local s = g:state()
  print(string.format("t=%d  player=(%.1f,%.1f)  sel=%s  won=%s",
    s.tick, s.player.x, s.player.y, tostring(s.selected), tostring(s.won)))
end

-- 指令序列
for cmd in opts.script:gmatch("[^;]+") do
  cmd = cmd:gsub("^%s+", ""):gsub("%s+$", "")
  if cmd ~= "" then
    local name, val = cmd:match("^(%a+):(.+)$")
    local dir = name and name:lower() or cmd:lower()
    if name and (dir == "right" or dir == "left" or dir == "up" or dir == "down") then
      g:key(dir, true)
      g:tickN(tonumber(val) or 0, dt)
      g:key(dir, false)
    elseif name and dir == "goto" then
      local x, y = val:match("^([%-%d%.]+),([%-%d%.]+)")
      if x then g:goto(tonumber(x), tonumber(y), dt) end
    elseif cmd:lower() == "pick" then
      g:act("pick")
    elseif name and dir == "wait" then
      g:tickN(tonumber(val) or 0, dt)
    end
    if opts.trace then traceLine() end
  end
end

-- 无输入直推
if opts.steps > 0 then
  for _ = 1, opts.steps do
    g:step(dt)
    if opts.trace and g.tick % opts.every == 0 then traceLine() end
  end
end

-- 总结
local s = g:state()
print(string.format("== 结束 t=%d  player=(%.2f,%.2f)  selected=%s  won=%s  ticks=%d",
  s.tick, s.player.x, s.player.y, tostring(s.selected), tostring(s.won), g.tick))

-- 回放一致性校验（确定性）
if opts.replay then
  local g2 = sim.replay(g.log, dt)
  local s2 = g2:state()
  local same = (math.abs(s2.player.x - s.player.x) < 1e-9)
    and (math.abs(s2.player.y - s.player.y) < 1e-9)
    and (s2.won == s.won) and (tostring(s2.selected) == tostring(s.selected))
  print("replay: " .. (same and "一致 ✅" or "不一致 ❌") .. string.format("  (replay player=(%.2f,%.2f) won=%s)",
    s2.player.x, s2.player.y, tostring(s2.won)))
end

if opts.json then print(sim.encode(s)) end
