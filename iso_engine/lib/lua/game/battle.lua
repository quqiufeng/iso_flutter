-- battle.lua —— 方格**兵线对推**（left=我方防守 / right=敌方进攻），纯 Lua、确定性、headless。
-- 单位沿"行(兵线)"向对方推进；射程内即停下互攻；摧毁对方基地即胜。
-- 双方单位**武器不同**（melee/ranged/splash/heavy…），进攻方成波刷多个角色。
local M = {}

-- JSON 编码（供 app 读 state）
local function esc(s) return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end
local function json(v)
  local t = type(v)
  if t == "string" then return esc(v)
  elseif t == "number" then return v == math.floor(v) and string.format("%d", v) or string.format("%.4f", v)
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
    for _, k in ipairs(keys) do p[#p + 1] = esc(tostring(k)) .. ":" .. json(v[k]) end
    return "{" .. table.concat(p, ",") .. "}"
  end
  return "null"
end
M.encode = json
function M:json() return json(self:state()) end

-- 单位类型：hp/atk/range(格)/speed(格/秒)/cost/rate(攻击间隔秒)；hue 供前端上色（Q版）
M.TYPES = {
  -- 我方（左，防守/布防）
  sword  = { name = "剑士", side = "left",  hp = 70,  atk = 12, range = 1.2, speed = 1.7, cost = 30, rate = 0.8, weapon = "melee",  hue = 200 },
  archer = { name = "弓手", side = "left",  hp = 40,  atk = 10, range = 4.5, speed = 1.2, cost = 45, rate = 1.0, weapon = "ranged", hue = 140 },
  mage   = { name = "法师", side = "left",  hp = 45,  atk = 18, range = 3.5, speed = 1.1, cost = 70, rate = 1.4, weapon = "splash", hue = 280 },
  -- 敌方（右，进攻）
  goblin = { name = "哥布林", side = "right", hp = 55, atk = 10, range = 1.0, speed = 1.9, cost = 0, rate = 0.7, weapon = "melee",  hue = 20 },
  shooter= { name = "弩手",   side = "right", hp = 38, atk = 11, range = 4.0, speed = 1.3, cost = 0, rate = 1.1, weapon = "ranged", hue = 340 },
  ogre   = { name = "食人魔", side = "right", hp = 160, atk = 18, range = 1.3, speed = 1.3, cost = 0, rate = 1.0, weapon = "heavy",  hue = 0 },
}

function M.new(opts)
  opts = opts or {}
  local rows = opts.rows or 5
  local cols = opts.cols or 10
  return setmetatable({
    rows = rows, cols = cols, tick = 0,
    bases = { left = { hp = 100, max = 100 }, right = { hp = 100, max = 100 } },
    resource = opts.resource or 120,      -- 我方资源（随时间增长）
    units = {},                            -- {side,type,lane,x,hp,max,cd}
    spawnTimer = 2.0,                      -- 敌方下次刷兵倒计时
    wave = 0,
    over = false, winner = nil,
    log = {},
  }, { __index = M })
end

-- 我方布兵：在 lane 行（0-based）放一个 type（扣资源）
function M:deploy(lane, type)
  local t = M.TYPES[type]
  if not t or t.side ~= "left" then return false, "非我方单位" end
  if lane < 0 or lane >= self.rows then return false, "越界" end
  if self.resource < t.cost then return false, "资源不足" end
  self.resource = self.resource - t.cost
  self.units[#self.units + 1] = {
    side = "left", type = type, lane = lane, x = 0.5, hp = t.hp, max = t.hp, cd = 0,
  }
  self.log[#self.log + 1] = { tick = self.tick, deploy = { lane = lane, type = type } }
  return true
end

-- 敌方按波次刷兵（越晚越强）
function M:_spawnEnemy()
  self.wave = self.wave + 1
  local pool = { "goblin", "goblin", "shooter" }
  if self.wave > 2 then pool[#pool + 1] = "ogre" end
  local n = 1 + math.floor(self.wave / 4)
  for i = 1, n do
    local type = pool[((self.wave + i) % #pool) + 1]
    local lane = (self.wave + i) % self.rows
    self.units[#self.units + 1] = {
      side = "right", type = type, lane = lane, x = self.cols - 0.5,
      hp = M.TYPES[type].hp, max = M.TYPES[type].hp, cd = 0,
    }
  end
  self.spawnTimer = math.max(2.4, 4.2 - self.wave * 0.08)
end

-- 找同一行里、射程内最近的敌人
function M:_target(u)
  local t = M.TYPES[u.type]
  local best, bd = nil, math.huge
  for _, o in ipairs(self.units) do
    if o.side ~= u.side and o.lane == u.lane and o.hp > 0 then
      local d = math.abs(o.x - u.x)
      if d <= t.range and d < bd then bd, best = d, o end
    end
  end
  return best, bd
end

function M:step(dt)
  if self.over then return end
  self.tick = self.tick + 1
  self.resource = math.min(300, self.resource + 13 * dt)

  -- 敌方刷兵
  self.spawnTimer = self.spawnTimer - dt
  if self.spawnTimer <= 0 then self:_spawnEnemy() end

  -- 单位：有目标→停下攻击；否则推进
  for _, u in ipairs(self.units) do
    u.moving = false
    if u.hp > 0 then
      local t = M.TYPES[u.type]
      u.cd = math.max(0, u.cd - dt)
      local enemy = self:_target(u)
      if enemy then
        if u.cd <= 0 then
          enemy.hp = enemy.hp - t.atk
          u.cd = t.rate
          -- splash：同行相邻也受伤
          if t.weapon == "splash" then
            for _, o in ipairs(self.units) do
              if o.side ~= u.side and o ~= enemy and o.hp > 0 and math.abs(o.x - enemy.x) < 1.5 and o.lane == u.lane then
                o.hp = o.hp - t.atk * 0.5
              end
            end
          end
        end
      else
        local dir = u.side == "left" and 1 or -1
        u.x = u.x + dir * t.speed * dt
        u.moving = true
      end
    end
  end

  -- 结算：死亡 + 到达对方基地
  local alive = {}
  for _, u in ipairs(self.units) do
    if u.hp <= 0 then
      if u.side == "right" then self.resource = math.min(300, self.resource + 12) end -- 击杀奖励
    elseif (u.side == "left" and u.x >= self.cols - 0.5) or (u.side == "right" and u.x <= 0.5) then
      local foe = u.side == "left" and "right" or "left"
      self.bases[foe].hp = self.bases[foe].hp - math.max(4, M.TYPES[u.type].atk)
      u.hp = 0
    else
      alive[#alive + 1] = u
    end
  end
  self.units = alive

  -- 胜负
  if self.bases.right.hp <= 0 then self.over, self.winner = true, "left"
  elseif self.bases.left.hp <= 0 then self.over, self.winner = true, "right" end
end

function M:tickN(n, dt) for _ = 1, n do self:step(dt or 1 / 60) end end

function M:state()
  local units = {}
  for i, u in ipairs(self.units) do
    local tp = M.TYPES[u.type]
    units[i] = { side = u.side, type = u.type, lane = u.lane, x = u.x, hp = u.hp, max = u.max, hue = tp.hue, range = tp.range,
      moving = u.moving == true, cd = u.cd, rate = tp.rate }
  end
  return {
    tick = self.tick, rows = self.rows, cols = self.cols, wave = self.wave,
    resource = self.resource, over = self.over, winner = self.winner,
    bases = self.bases, units = units,
  }
end

return M
