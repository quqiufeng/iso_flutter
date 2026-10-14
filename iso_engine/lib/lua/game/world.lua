-- world.lua —— 对推世界内核（纯 Lua，确定性，headless）
-- 职责：持有状态 + 提供**唯一交互 API**（查询 / 推进 / 交战 / 结算 / 发事件）。
-- 逻辑只在这里；行为/武器/技能经由此 API 生效；**不碰 love.\***。
local C = require("config")
local Entity = require("entity")
local Behaviors = require("behaviors")
local Weapons = require("weapons")
local Abilities = require("abilities")
local json = require("json")

local W = {}
W.__index = W

function W.new(opts)
  opts = opts or {}
  return setmetatable({
    rows = opts.rows or C.rows, cols = opts.cols or C.cols, tick = 0,
    bases = { left = { hp = C.baseHp, max = C.baseHp }, right = { hp = C.baseHp, max = C.baseHp } },
    resource = opts.resource or C.resourceStart,
    units = {}, spawnTimer = 2.0, wave = 0,
    over = false, winner = nil,
    ultCd = 0, whirlCd = 0,
    events = {},                      -- 本帧事件流（渲染层消费）
    log = {},
  }, W)
end

-- ===== 查询 API =====
function W:nearestEnemy(u, maxd)
  local best, bd = nil, math.huge
  for _, o in ipairs(self.units) do
    if o.side ~= u.side and o.lane == u.lane and o.hp > 0 then
      local d = math.abs(o.x - u.x)
      if d <= maxd and d < bd then bd, best = d, o end
    end
  end
  return best, bd
end

-- 与 p 同侧、在半径 r 内的单位（用于溅射等），lane 可选过滤
function W:alliesNear(p, r, lane)
  local out = {}
  for _, o in ipairs(self.units) do
    if o ~= p and o.side == p.side and o.hp > 0
      and (lane == nil or o.lane == lane) and math.abs(o.x - p.x) < r then
      out[#out + 1] = o
    end
  end
  return out
end

-- ===== 推进 / 交战 / 结算 API =====
function W:advance(u, dt)
  local dir = u.side == "left" and 1 or -1
  u.x = u.x + dir * u.stats.speed * dt
  u.moving = true
  u.state = "advance"
end

function W:engage(u, e, dt)
  u.attacking = true
  u.state = "engage"
  if u.cd <= 0 then
    u.cd = u.stats.rate
    ;(Weapons[u.stats.weapon] or Weapons.melee)(u, e, self)
  end
end

function W:hit(t, amt, src)
  if not t or t.hp <= 0 then return end
  t.hp = t.hp - amt
  self:emit{ type = "hit", target = t, amt = amt, src = src }
end

function W:emit(ev) self.events[#self.events + 1] = ev end

-- ===== 布兵 / 技能 =====
function W:deploy(lane, type)
  local s = C.units[type]
  if not s or s.side ~= "left" then return false, "非我方单位" end
  if lane < 0 or lane >= self.rows then return false, "越界" end
  if self.resource < s.cost then return false, "资源不足" end
  self.resource = self.resource - s.cost
  self.units[#self.units + 1] = Entity.new("left", type, lane, 0.5)
  self.log[#self.log + 1] = { tick = self.tick, deploy = { lane = lane, type = type } }
  return true
end

function W:ultimate()
  if (self.ultCd or 0) > 0 then return false end
  if not Abilities.ult(self) then return false end
  self.ultCd = C.abilities.ult.cd
  return true
end

function W:whirlwind()
  if (self.whirlCd or 0) > 0 then return nil end
  if not Abilities.whirl(self) then return nil end
  self.whirlCd = C.abilities.whirl.cd
  return true
end

-- ===== 系统 =====
function W:spawnTick(dt)
  self.spawnTimer = self.spawnTimer - dt
  if self.spawnTimer <= 0 then self:spawnWave() end
end

function W:spawnWave()
  self.wave = self.wave + 1
  for _, sp in ipairs(C.enemyWave(self.wave, self.rows)) do
    self.units[#self.units + 1] = Entity.new("right", sp.type, sp.lane, self.cols - 0.5)
  end
  self:emit{ type = "wave", n = self.wave }
  self.spawnTimer = C.waveInterval(self.wave)
end

function W:settle()
  local alive = {}
  for _, u in ipairs(self.units) do
    if u.hp <= 0 then
      if u.side == "right" then self.resource = math.min(C.resourceCap, self.resource + C.killReward) end
      self:emit{ type = "death", unit = u }
    elseif (u.side == "left" and u.x >= self.cols - 0.5) or (u.side == "right" and u.x <= 0.5) then
      local foe = u.side == "left" and "right" or "left"
      self.bases[foe].hp = self.bases[foe].hp - math.max(4, u.stats.atk)
      u.hp = 0
      self:emit{ type = "base", side = foe }
    else
      alive[#alive + 1] = u
    end
  end
  self.units = alive
  if self.bases.right.hp <= 0 then self.over, self.winner = true, "left"
  elseif self.bases.left.hp <= 0 then self.over, self.winner = true, "right" end
end

function W:step(dt)
  if self.over then return end
  self.tick = self.tick + 1
  self.events = {}
  self.resource = math.min(C.resourceCap, self.resource + C.resourceRegen * dt)
  self.ultCd = math.max(0, (self.ultCd or 0) - dt)
  self.whirlCd = math.max(0, (self.whirlCd or 0) - dt)
  self:spawnTick(dt)
  for _, u in ipairs(self.units) do
    u.moving = false; u.attacking = false
    if u.hp > 0 then
      u.cd = math.max(0, u.cd - dt)
      ;(Behaviors[u.stats.ai] or Behaviors.rush)(u, self, dt)
    end
  end
  self:settle()
end

function W:tickN(n, dt) for _ = 1, n do self:step(dt or 1 / 60) end end

-- ===== 导出 =====
function W:state()
  local units = {}
  for i, u in ipairs(self.units) do
    local s = u.stats
    units[i] = { side = u.side, type = u.type, lane = u.lane, x = u.x, hp = u.hp, max = u.max,
      hue = s.hue, range = s.range, moving = u.moving == true, attacking = u.attacking == true, cd = u.cd, rate = s.rate }
  end
  return {
    tick = self.tick, rows = self.rows, cols = self.cols, wave = self.wave,
    resource = self.resource, over = self.over, winner = self.winner,
    bases = self.bases, units = units,
  }
end

function W:json() return json.encode(self:state()) end

return W
