-- sim.lua —— 纯 Lua 游戏仿真（确定性、headless、可回放）。
-- 供 agent 用 `luajit -e` 直接驱动/试玩/断言；渲染宿主（Flutter/LÖVE）只消费 state()。
--
-- 用法（进程外，无需任何协议）：
--   package.path = "game/sim/?.lua;" .. package.path
--   local sim = require("sim")
--   local g = sim.new()
--   g:key("right", true)          -- 按键（持续）
--   for i = 1, 60 do g:step(1/60) end
--   g:key("right", false)
--   print(g:json())               -- 当前世界状态（JSON）
local world = require("world")

local M = {}

-- 确定性：固定步长 + 无随机（world 固定）。若要用随机，用自带种子 RNG。
local function jsonEscape(s) return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end
local function json(v)
  local t = type(v)
  if t == "string" then return jsonEscape(v)
  elseif t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.4f", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    if #v > 0 then
      local p = {}
      for i = 1, #v do p[i] = json(v[i]) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local p = {}
    for _, k in ipairs(keys) do p[#p + 1] = jsonEscape(tostring(k)) .. ":" .. json(v[k]) end
    return "{" .. table.concat(p, ",") .. "}"
  end
  return "null"
end
M.encode = json

function M.new(opts)
  opts = opts or {}
  local w = world.new()
  local npcs = {}
  for i, n in ipairs(w.npcs or {}) do
    local wp = {}
    for j, q in ipairs(n.wp) do wp[j] = { x = q.x, y = q.y } end
    npcs[i] = { x = n.x, y = n.y, r = n.r, kind = n.kind, speed = n.speed, wp = wp, wi = 1, paused = false }
  end
  -- opts.npcs = N：生成 N 个 NPC（网格铺开）——用于"多角色场景"压力/效果测试
  if opts.npcs then
    npcs = {}
    local side = math.max(1, math.ceil(math.sqrt(opts.npcs)))
    for i = 1, opts.npcs do
      local gx = ((i - 1) % side + 0.5) / side * 2 - 1
      local gy = (math.floor((i - 1) / side) + 0.5) / side * 2 - 1
      local x, y = gx * (w.size - 3), gy * (w.size - 3)
      npcs[i] = {
        x = x, y = y, r = 1.6, kind = "npc", speed = 3 + (i % 4),
        wp = { { x = x - 3, y = y }, { x = x + 3, y = y } }, wi = 1, paused = false,
      }
    end
  end
  return setmetatable({
    opts = opts,
    world = w,
    tick = 0,
    player = { x = w.player.x, y = w.player.y, r = w.player.r },
    npcs = npcs,         -- 其他动态角色（可暂停；主角除外）
    keys = {},           -- 持续按键
    selected = nil,      -- 最近一次 pick 的物件索引
    won = false,
    score = 0,
    log = {},            -- 输入记录（用于回放）
  }, { __index = M })
end

-- 暂停"其他动态角色"（主角除外）。filter 可为 {kind="guard"} 只停某类；省略=全部。
function M:pauseNpcs(paused, filter)
  paused = paused and true or false
  for _, n in ipairs(self.npcs) do
    if not filter or (filter.kind == nil or n.kind == filter.kind) then n.paused = paused end
  end
  self.log[#self.log + 1] = { tick = self.tick, pauseNpcs = paused, kind = filter and filter.kind or nil }
end

-- 暂停单个 NPC（1-based 下标）
function M:pauseNpc(i, paused)
  local n = self.npcs[i]
  if not n then return end
  n.paused = paused and true or false
  self.log[#self.log + 1] = { tick = self.tick, pauseNpc = { i = i, paused = n.paused } }
end

-- 按键（up/down/left/right）
function M:key(name, down)
  self.keys[name] = down and true or nil
  self.log[#self.log + 1] = { tick = self.tick, key = name, down = down and true or false }
end

-- 一次性动作：pick（选中最近物件）/ wait
function M:act(cmd)
  if cmd == "pick" then
    local best, bd = nil, math.huge
    for i, p in ipairs(self.world.props) do
      local dx, dy = p.x - self.player.x, p.y - self.player.y
      local d = dx * dx + dy * dy
      if d < bd then bd, best = d, i end
    end
    self.selected = best
  end
  self.log[#self.log + 1] = { tick = self.tick, act = cmd }
end

-- 推进一帧（固定 dt）；确定性
function M:step(dt)
  local p, w = self.player, self.world

  -- 其他动态角色：巡游（**暂停则冻结**；主角不受影响）
  for _, n in ipairs(self.npcs) do
    if not n.paused then
      local t = n.wp[n.wi]
      local dx, dy = t.x - n.x, t.y - n.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 0.2 then
        n.wi = n.wi % #n.wp + 1
      else
        n.x = n.x + dx / d * n.speed * dt
        n.y = n.y + dy / d * n.speed * dt
      end
    end
  end

  local vx, vy = 0, 0
  if self.keys.right then vx = vx + 1 end
  if self.keys.left then vx = vx - 1 end
  if self.keys.down then vy = vy + 1 end
  if self.keys.up then vy = vy - 1 end
  if vx ~= 0 or vy ~= 0 then
    local l = math.sqrt(vx * vx + vy * vy)
    vx, vy = vx / l * w.speed, vy / l * w.speed
  end
  p.x = p.x + vx * dt
  p.y = p.y + vy * dt

  -- 碰撞：圆 vs 圆（推出去）+ 地面边界（物件 + **未暂停**的 NPC；暂停的 NPC = 幽灵不挡路）
  local obstacles = {}
  for _, o in ipairs(w.props) do obstacles[#obstacles + 1] = o end
  for _, n in ipairs(self.npcs) do
    if not n.paused then obstacles[#obstacles + 1] = n end
  end
  for _, o in ipairs(obstacles) do
    local dx, dy = p.x - o.x, p.y - o.y
    local d = math.sqrt(dx * dx + dy * dy)
    local min = p.r + o.r
    if d < min and d > 1e-6 then
      p.x = o.x + dx / d * min
      p.y = o.y + dy / d * min
    end
  end
  p.x = math.max(-w.size, math.min(w.size, p.x))
  p.y = math.max(-w.size, math.min(w.size, p.y))

  -- 目标
  local gdx, gdy = p.x - w.goal.x, p.y - w.goal.y
  if not self.won and math.sqrt(gdx * gdx + gdy * gdy) <= w.goal.r then
    self.won = true
  end

  self.tick = self.tick + 1
end

-- 批量推进
function M:tickN(n, dt) for _ = 1, n do self:step(dt or 1 / 60) end end

-- 自动走到 (x,y)（简单控制器：朝目标按方向键直到到点）；记录为一条 goto 事件（可回放）
function M:goto(x, y, dt, maxTicks)
  dt = dt or 1 / 60
  maxTicks = maxTicks or 100000
  self.log[#self.log + 1] = { tick = self.tick, goto = { x = x, y = y } }
  return self:_walk(x, y, dt, maxTicks)
end

function M:_walk(x, y, dt, maxTicks)
  dt = dt or 1 / 60
  maxTicks = maxTicks or 100000
  local n = 0
  while n < maxTicks do
    local dx, dy = x - self.player.x, y - self.player.y
    if dx * dx + dy * dy < 0.25 then break end
    self.keys.right = dx > 0 and true or nil
    self.keys.left = dx < 0 and true or nil
    self.keys.down = dy > 0 and true or nil
    self.keys.up = dy < 0 and true or nil
    self:step(dt)
    n = n + 1
  end
  for k in pairs(self.keys) do self.keys[k] = nil end
  return n
end

function M:state()
  local props = {}
  for i, o in ipairs(self.world.props) do
    props[i] = { x = o.x, y = o.y, r = o.r, kind = o.kind }
  end
  local npcs = {}
  for i, n in ipairs(self.npcs) do
    npcs[i] = { x = n.x, y = n.y, r = n.r, kind = n.kind, paused = n.paused }
  end
  return {
    tick = self.tick,
    player = { x = self.player.x, y = self.player.y, r = self.player.r },
    npcs = npcs,
    selected = self.selected,
    won = self.won,
    goal = { x = self.world.goal.x, y = self.world.goal.y, r = self.world.goal.r },
    props = props,
  }
end

function M:json() return json(self:state()) end -- 注：模块级编码器是 sim.json(value)

-- 回放：给定记录（key/act 序列），从新局跑一遍 → 同结果（确定性）
function M.replay(log, dt, opts)
  local g = M.new(opts)
  local i = 1
  dt = dt or 1 / 60
  -- 记录按 tick 排（已天然有序）
  while i <= #log do
    local e = log[i]
    -- 推进到该事件的 tick
    while g.tick < e.tick do g:step(dt) end
    if e.key ~= nil then
      g.keys[e.key] = e.down and true or nil
      g.log[#g.log + 1] = e
    elseif e.act ~= nil then
      -- 直接施加（不重复记 log 的副作用）
      if e.act == "pick" then
        local best, bd = nil, math.huge
        for idx, p in ipairs(g.world.props) do
          local dx, dy = p.x - g.player.x, p.y - g.player.y
          local d = dx * dx + dy * dy
          if d < bd then bd, best = d, idx end
        end
        g.selected = best
      end
      g.log[#g.log + 1] = e
    elseif e.goto ~= nil then
      g.log[#g.log + 1] = e
      g:_walk(e.goto.x, e.goto.y, dt)
    elseif e.pauseNpcs ~= nil then
      g.log[#g.log + 1] = e
      for _, n in ipairs(g.npcs) do
        if e.kind == nil or n.kind == e.kind then n.paused = e.pauseNpcs end
      end
    elseif e.pauseNpc ~= nil then
      g.log[#g.log + 1] = e
      local n = g.npcs[e.pauseNpc.i]
      if n then n.paused = e.pauseNpc.paused end
    end
    i = i + 1
  end
  return g
end

return M
