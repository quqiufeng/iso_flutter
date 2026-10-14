-- sim.lua —— 「水晶方块」(Tetris) 纯 Lua 仿真：确定性 / headless / 可回放 / 带落子记忆。
-- 逻辑与表现解耦：渲染宿主（LÖVE）只消费 state()/events；agent 用 luajit 直接驱动、试玩、断言。
--
-- 用法（进程外，无需任何协议）：
--   package.path = "game/tetris/?.lua;" .. package.path
--   local sim = require("sim")
--   local g = sim.new({ seed = 123 })
--   g:act("rotate"); g:act("left"); g:act("hard")
--   g:step(1/60)
--   print(g:json())                     -- 世界状态（JSON）
--   print(#g.history)                   -- 已落子次数 = 每次落下的形状记忆
--   local g2 = sim.replay(g.log, { seed = 123 })   -- 确定性回放 → 同结果

local M = {}

M.COLS, M.ROWS = 10, 20
M.TYPES = { "i", "o", "t", "s", "z", "j", "l" }
M.SHAPES = {
  i = { { 0, 0, 0, 0 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
  o = { { 1, 1 }, { 1, 1 } },
  t = { { 0, 1, 0 }, { 1, 1, 1 }, { 0, 0, 0 } },
  s = { { 0, 1, 1 }, { 1, 1, 0 }, { 0, 0, 0 } },
  z = { { 1, 1, 0 }, { 0, 1, 1 }, { 0, 0, 0 } },
  j = { { 1, 0, 0 }, { 1, 1, 1 }, { 0, 0, 0 } },
  l = { { 0, 0, 1 }, { 1, 1, 1 }, { 0, 0, 0 } },
}
M.SCORE = { 100, 300, 500, 800 }      -- 消 1..4 行基础分
M.PREVIEW = 3                         -- 预告块数

-- 确定性 RNG（Lehmer LCG）—— 不依赖 love.math，headless 与宿主一致
local function makeRng(seed)
  local s = math.floor(seed or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(n)
    s = (s * 16807) % 2147483647
    return (s % n) + 1
  end
end

-- JSON 编码
local function esc(s) return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end
local function json(v)
  local t = type(v)
  if t == "string" then return esc(v)
  elseif t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.4f", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    if v[1] ~= nil then
      local p = {}
      for i = 1, #v do p[i] = json(v[i]) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local p = {}
    for _, k in ipairs(keys) do p[#p + 1] = esc(tostring(k)) .. ":" .. json(v[k]) end
    return "{" .. table.concat(p, ",") .. "}"
  end
  return "null"
end
M.encode = json

local function cloneM(m)
  local o = {}
  for i = 1, #m do o[i] = {}; for j = 1, #m[i] do o[i][j] = m[i][j] end end
  return o
end
local function rotCW(m)
  local n = #m; local o = {}
  for r = 1, n do o[r] = {}; for c = 1, n do o[r][c] = m[n - c + 1][r] end end
  return o
end
M.rotCW = rotCW

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, { __index = M })
  self.cols = opts.cols or M.COLS
  self.rows = opts.rows or M.ROWS
  self.seed = opts.seed or 1
  self.rand = makeRng(self.seed)
  self.log = {}                 -- 输入/动作记录（可回放）
  self.tick = 0
  self:reset()
  return self
end

-- 出块：纯随机（每块独立从 7 种里随机；允许重复，**不受 7-bag 限制**）
function M:randomType() return M.TYPES[self.rand(#M.TYPES)] end
function M:fillQueue()
  while #self.queue < M.PREVIEW do self.queue[#self.queue + 1] = self:randomType() end
end
function M:nextFromQueue()
  self:fillQueue()
  local t = table.remove(self.queue, 1)
  self:fillQueue()
  return t
end

function M:reset()
  self.board = {}
  for r = 1, self.rows do self.board[r] = {} end
  self.queue = {}; self:fillQueue(); self.nextType = self.queue[1]
  self.score, self.lines, self.level = 0, 0, 1
  self.over, self.paused = false, false
  self.fallT, self.fallInterval = 0, 0.8
  self.history = {}             -- ★ 每次落下的形状记忆
  self.lockCount = 0
  self.events = {}              -- 本帧事件流（渲染层消费）
  self:spawn()
end

function M:collide(m, ox, oy)
  for r = 1, #m do for c = 1, #m[r] do
    if m[r][c] == 1 then
      local x, y = ox + c - 1, oy + r - 1
      if x < 1 or x > self.cols or y > self.rows then return true end
      if y >= 1 and self.board[y][x] then return true end
    end
  end end
  return false
end

function M:spawn()
  local t = self:nextFromQueue()
  self.nextType = self.queue[1]
  local src = M.SHAPES[t]
  local m = cloneM(src)
  self.cur = { t = t, m = m, x = math.floor((self.cols - #m[1]) / 2) + 1, y = 1 }
  self.events[#self.events + 1] = { type = "spawn", piece = t }
  if self:collide(self.cur.m, self.cur.x, self.cur.y) then
    self.over = true
    self.events[#self.events + 1] = { type = "gameover" }
  end
end

function M:ghostY()
  if not self.cur then return 1 end
  local y = self.cur.y
  while not self:collide(self.cur.m, self.cur.x, y + 1) do y = y + 1 end
  return y
end

-- ===== 动作（一次性；记入 log 供回放）=====
function M:act(cmd)
  if self.over then return false end
  local ok = true
  if cmd == "left" then self:_move(-1)
  elseif cmd == "right" then self:_move(1)
  elseif cmd == "soft" then self:_soft()
  elseif cmd == "rotate" then self:_rotate()
  elseif cmd == "hard" then self:_hard()
  elseif cmd == "pause" then self.paused = not self.paused
  else ok = false end
  if ok then self.log[#self.log + 1] = { tick = self.tick, act = cmd } end
  return ok
end

function M:_move(dx)
  if not self.cur then return end
  if not self:collide(self.cur.m, self.cur.x + dx, self.cur.y) then self.cur.x = self.cur.x + dx end
end
function M:_soft()
  if not self.cur then return end
  if not self:collide(self.cur.m, self.cur.x, self.cur.y + 1) then
    self.cur.y = self.cur.y + 1; self.score = self.score + 1
  end
end
function M:_rotate()
  if not self.cur then return end
  local m = rotCW(self.cur.m)
  for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
    if not self:collide(m, self.cur.x + dx, self.cur.y) then
      self.cur.m = m; self.cur.x = self.cur.x + dx; return
    end
  end
end
function M:_hard()
  if not self.cur then return end
  local fromY = self.cur.y
  local gy = self:ghostY()
  self.cur.y = gy
  self.events[#self.events + 1] = {
    type = "harddrop", dist = gy - fromY, fromY = fromY, toY = gy,
    x = self.cur.x, t = self.cur.t, m = cloneM(self.cur.m),
  }
  self:_lock()
end

function M:_lock()
  local cur = self.cur
  local cells = {}
  for r = 1, #cur.m do for c = 1, #cur.m[r] do
    if cur.m[r][c] == 1 then
      local x, y = cur.x + c - 1, cur.y + r - 1
      if y >= 1 then self.board[y][x] = cur.t; cells[#cells + 1] = { x = x, y = y } end
    end
  end end
  -- 消行
  local cleared = {}
  for y = 1, self.rows do
    local full = true
    for x = 1, self.cols do if not self.board[y][x] then full = false; break end end
    if full then cleared[#cleared + 1] = y end
  end
  if #cleared > 0 then
    table.sort(cleared)
    local types = {}
    for _, y in ipairs(cleared) do
      local row = {}
      for x = 1, self.cols do row[x] = self.board[y][x] end
      types[#types + 1] = row
    end
    for i = #cleared, 1, -1 do table.remove(self.board, cleared[i]) end
    for _ = 1, #cleared do table.insert(self.board, 1, {}) end
    local n = #cleared
    self.score = self.score + M.SCORE[n] * self.level
    self.lines = self.lines + n
    self.level = 1 + math.floor(self.lines / 10)
    self.fallInterval = math.max(0.06, 0.8 - (self.level - 1) * 0.07)
    self.events[#self.events + 1] = { type = "clear", lines = n, rows = cleared, types = types }
  end
  -- ★ 落子记忆：记下这块的形状（类型/朝向矩阵/落点/格单元）
  self.lockCount = self.lockCount + 1
  local rec = {
    n = self.lockCount, tick = self.tick, type = cur.t,
    x = cur.x, y = cur.y, m = cloneM(cur.m), cells = cells,
    cleared = #cleared, score = self.score,
  }
  self.history[#self.history + 1] = rec
  self.events[#self.events + 1] = { type = "lock", rec = rec }
  self:spawn()
end

function M:step(dt)
  dt = dt or 1 / 60
  self.tick = self.tick + 1
  if self.over or self.paused then return end
  self.fallT = self.fallT + dt
  if self.fallT >= self.fallInterval then
    self.fallT = self.fallT - self.fallInterval
    if not self:collide(self.cur.m, self.cur.x, self.cur.y + 1) then
      self.cur.y = self.cur.y + 1
    else
      self:_lock()
    end
  end
end
function M:tickN(n, dt) for _ = 1, n do self:step(dt) end end

function M:clearEvents() self.events = {} end

function M:state()
  local board = {}
  for r = 1, self.rows do
    board[r] = {}
    for c = 1, self.cols do board[r][c] = self.board[r][c] or false end
  end
  local queue = {}
  for i = 1, #self.queue do queue[i] = self.queue[i] end
  local hist = {}
  for i = 1, #self.history do
    local h = self.history[i]
    hist[i] = { n = h.n, type = h.type, x = h.x, y = h.y, cleared = h.cleared, score = h.score,
                cells = h.cells, m = h.m }
  end
  return {
    tick = self.tick, seed = self.seed, cols = self.cols, rows = self.rows,
    over = self.over, paused = self.paused,
    score = self.score, lines = self.lines, level = self.level,
    board = board,
    cur = self.cur and { t = self.cur.t, x = self.cur.x, y = self.cur.y, m = self.cur.m } or nil,
    next = self.nextType, queue = queue,
    history = hist, locks = self.lockCount,
  }
end
function M:json() return json(self:state()) end

-- 回放：给定动作记录，从同种子新局跑一遍 → 同结果（确定性）
function M.replay(log, opts)
  local g = M.new(opts)
  local i = 1
  while i <= #log do
    local e = log[i]
    while g.tick < (e.tick or 0) do g:step(1 / 60) end
    if e.act then
      if e.act == "left" then g:_move(-1)
      elseif e.act == "right" then g:_move(1)
      elseif e.act == "soft" then g:_soft()
      elseif e.act == "rotate" then g:_rotate()
      elseif e.act == "hard" then g:_hard()
      elseif e.act == "pause" then g.paused = not g.paused end
      g.log[#g.log + 1] = e
    end
    i = i + 1
  end
  return g
end

return M
