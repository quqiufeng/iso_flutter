-- run.lua —— 跑一局「水晶方块」(纯 Lua, headless)。用 luajit game/tetris/run.lua [...]
-- 选项：
--   --seed N            随机种子（确定性；默认 1）
--   --script "a;b;c"    指令序列（; 分隔）：
--                         left / right / rotate / soft / hard     一次性动作
--                         left:N / right:N / rotate:N …          重复 N 次
--                         wait:N                                  推进 N 帧（重力，可能落子）
--                         pause                                   暂停/继续
--   --steps N           无输入直推 N 帧
--   --trace             每 --every 帧打印一行
--   --every N           trace 间隔（默认 30）
--   --json              最后打印完整 state JSON
--   --history           打印落子记忆（每次落下的形状）
--   --replay            回放校验（确定性）
package.path = (arg[0]:gsub("[^/]*$", "")) .. "?.lua;" .. package.path
local sim = require("sim")

local opts = { steps = 0, script = "", trace = false, every = 30, json = false, history = false, replay = false, seed = 1 }
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--steps" then i = i + 1; opts.steps = tonumber(arg[i]) or 0
    elseif a == "--script" then i = i + 1; opts.script = arg[i] or ""
    elseif a == "--trace" then opts.trace = true
    elseif a == "--every" then i = i + 1; opts.every = tonumber(arg[i]) or 30
    elseif a == "--json" then opts.json = true
    elseif a == "--history" then opts.history = true
    elseif a == "--replay" then opts.replay = true
    elseif a == "--seed" then i = i + 1; opts.seed = tonumber(arg[i]) or 1
    end
    i = i + 1
  end
end

local g = sim.new({ seed = opts.seed })
local dt = 1 / 60

local function traceLine()
  local s = g:state()
  print(string.format("t=%d  score=%d  lines=%d  lv=%d  locks=%d  cur=%s@(%d,%d)  next=%s  over=%s",
    s.tick, s.score, s.lines, s.level, s.locks,
    s.cur and s.cur.t or "-", s.cur and s.cur.x or 0, s.cur and s.cur.y or 0,
    tostring(s.next), tostring(s.over)))
end

-- 指令序列
for cmd in opts.script:gmatch("[^;]+") do
  cmd = cmd:gsub("^%s+", ""):gsub("%s+$", "")
  if cmd ~= "" then
    local name, val = cmd:match("^(%a+):(.+)$")
    local low = (name or cmd):lower()
    if low == "left" or low == "right" or low == "rotate" or low == "soft" or low == "hard" then
      for _ = 1, (tonumber(val) or 1) do g:act(low) end
    elseif low == "wait" then g:tickN(tonumber(val) or 0, dt)
    elseif low == "pause" then g:act("pause")
    end
    if opts.trace then traceLine() end
  end
end

if opts.steps > 0 then
  for _ = 1, opts.steps do
    g:step(dt)
    if opts.trace and g.tick % opts.every == 0 then traceLine() end
  end
end

local s = g:state()
print(string.format("== 结束  score=%d  lines=%d  lv=%d  locks=%d  over=%s  tick=%d",
  s.score, s.lines, s.level, s.locks, tostring(s.over), g.tick))

if opts.history then
  print("-- 落子记忆（每次落下的形状）--")
  for _, h in ipairs(s.history) do
    local cells = {}
    for _, c in ipairs(h.cells) do cells[#cells + 1] = string.format("(%d,%d)", c.x, c.y) end
    print(string.format("  #%d %s  pos=(%d,%d)  cleared=%d  单元格 %s",
      h.n, h.type, h.x, h.y, h.cleared, table.concat(cells, " ")))
  end
end

if opts.replay then
  local g2 = sim.replay(g.log, { seed = opts.seed })
  local s2 = g2:state()
  local same = (s2.score == s.score) and (s2.lines == s.lines)
    and (#g2.history == #g.history) and (s2.over == s.over)
  print("replay: " .. (same and "一致 ✅" or "不一致 ❌")
    .. string.format("  (score=%d lines=%d locks=%d over=%s)", s2.score, s2.lines, s2.locks, tostring(s2.over)))
end

if opts.json then print(sim.encode(s)) end
