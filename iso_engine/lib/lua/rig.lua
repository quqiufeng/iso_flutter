-- rig.lua —— 极简 2D 骨骼动画系统（LÖVE 运行时 / headless 通用）
--
-- 设计（数据/代码定义，agent 可直接写、可 headless 测试、可回放）：
--   bones  骨骼层级：{ name, parent, x, y, rot, sx, sy }        —— 局部(setup)变换
--   slots  插槽：    { name, bone, order, att={name,img,w,h,pivotX,pivotY,scale}, color, x,y,rot,sx,sy }
--                    —— 挂在某骨骼上，有绘制顺序；att 是附件(图)；color 染色；atts=多附件(换武器)
--   clips  动画：    { name={ duration, loop, bones={bone={keys}}, slots={slot={keys}} } }
--                    —— keys = { {t=, x=,y=,rot=,sx=,sy=, att="武器名", color={r,g,b,a}, ease="inout"}, ... }
--
-- 用法：
--   local rig = require("rig")
--   local R = rig.new(def)
--   R:setClip("walk"); R:update(dt)
--   R:draw(x, y, scale, flip)          -- LÖVE
--   local list = R:drawList()          -- headless/自定义渲染（含世界矩阵）

local rig = {}
rig.__index = rig

-- ---------- 仿射矩阵 {a,b,c,d,e,f}：(px,py) -> (a*px+c*py+e, b*px+d*py+f) ----------
local IDENT = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }
local function matMul(m1, m2)  -- 先 m2 后 m1
  return {
    a = m1.a * m2.a + m1.c * m2.b,
    b = m1.b * m2.a + m1.d * m2.b,
    c = m1.a * m2.c + m1.c * m2.d,
    d = m1.b * m2.c + m1.d * m2.d,
    e = m1.a * m2.e + m1.c * m2.f + m1.e,
    f = m1.b * m2.e + m1.d * m2.f + m1.f,
  }
end
local function matTRS(x, y, rot, sx, sy)
  local co, si = math.cos(rot or 0), math.sin(rot or 0)
  sx, sy = sx or 1, sy or 1
  return { a = co * sx, b = si * sx, c = -si * sy, d = co * sy, e = x or 0, f = y or 0 }
end
rig.matMul, rig.matTRS, rig.IDENT = matMul, matTRS, IDENT

-- ---------- 缓动（遵循 docs/references/motion.md） ----------
local function clamp01(t) return t < 0 and 0 or (t > 1 and 1 or t) end
local EASE = {
  linear = function(t) return t end,
  step   = function() return 0 end,
  in_    = function(t) return t * t end,
  out    = function(t) return 1 - (1 - t) * (1 - t) end,
  inout  = function(t) return t * t * (3 - 2 * t) end,
  back   = function(t) local c = 1.70158; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end,
  bounce = function(t)
    if t < 1 / 2.75 then return 7.5625 * t * t end
    if t < 2 / 2.75 then t = t - 1.5 / 2.75; return 7.5625 * t * t + 0.75 end
    if t < 2.5 / 2.75 then t = t - 2.25 / 2.75; return 7.5625 * t * t + 0.9375 end
    t = t - 2.625 / 2.75; return 7.5625 * t * t + 0.984375
  end,
  elastic = function(t)
    if t == 0 or t == 1 then return t end
    return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * math.pi / 3))
  end,
}
rig.EASE = EASE

local PROPS = { "x", "y", "rot", "sx", "sy", "alpha" }
local SCALE_PROPS = { sx = true, sy = true, alpha = true }

-- 用 rest 补全数值属性（避免"只写了 rot 的 key"丢掉 x/y）
local function fillProps(k, rest)
  local out = {}
  for kk, vv in pairs(k) do out[kk] = vv end
  for _, p in ipairs(PROPS) do
    if out[p] == nil then
      local d = rest and rest[p]
      if d == nil then d = SCALE_PROPS[p] and 1 or 0 end
      out[p] = d
    end
  end
  return out
end

-- 时间轴求值：插值 PROPS，其余属性(att/color/ease…)沿用 k0
local function evalKeys(keys, t, rest)
  if not keys or #keys == 0 then return rest end
  if t <= keys[1].t then return fillProps(keys[1], rest) end
  if t >= keys[#keys].t then return fillProps(keys[#keys], rest) end
  local i = 1
  while i < #keys and keys[i + 1].t <= t do i = i + 1 end
  local k0, k1 = keys[i], keys[i + 1]
  local span = k1.t - k0.t
  local u = span > 1e-9 and (t - k0.t) / span or 0
  u = (EASE[k1.ease or "inout"] or EASE.inout)(clamp01(u))
  local out = fillProps(k0, rest)
  for _, p in ipairs(PROPS) do
    local v1 = k1[p]; if v1 == nil then v1 = out[p] end
    out[p] = out[p] + (v1 - out[p]) * u
  end
  out.t = t
  return out
end

-- ---------- 构造 ----------
function rig.new(def)
  local self = setmetatable({}, rig)
  self.def = def
  self.boneDef, self.boneOrder = {}, {}
  for _, b in ipairs(def.bones or {}) do self.boneDef[b.name] = b; self.boneOrder[#self.boneOrder + 1] = b.name end
  self.slotDef, self.order = {}, {}
  for _, s in ipairs(def.slots or {}) do self.slotDef[s.name] = s; self.order[#self.order + 1] = s end
  table.sort(self.order, function(a, b) return (a.order or 0) < (b.order or 0) end)
  self.clips = def.clips or {}
  self.state, self.slotState = {}, {}
  for _, b in ipairs(def.bones or {}) do
    self.state[b.name] = { x = b.x or 0, y = b.y or 0, rot = b.rot or 0, sx = b.sx or 1, sy = b.sy or 1 }
  end
  self.clip, self.time, self.speed, self.loop, self.onEnd = nil, 0, 1, true, nil
  return self
end

function rig:setClip(name, opt)
  opt = opt or {}
  self.clip = self.clips[name] and name or nil
  self.time = opt.time or 0
  self.speed = opt.speed or 1
  self.loop = opt.loop ~= false
  self.onEnd = opt.onEnd
  self:_apply()
end

function rig:update(dt)
  if not self.clip then return end
  local c = self.clips[self.clip]
  self.time = self.time + dt * self.speed
  if c.duration and self.time >= c.duration then
    if self.loop then self.time = self.time % c.duration
    else self.time = c.duration; if self.onEnd then local f = self.onEnd; self.onEnd = nil; f() end end
  end
  self:_apply()
end

function rig:_apply()
  -- 骨骼先回 rest
  for _, b in ipairs(self.def.bones or {}) do
    local s = self.state[b.name]
    s.x, s.y, s.rot, s.sx, s.sy = b.x or 0, b.y or 0, b.rot or 0, b.sx or 1, b.sy or 1
  end
  -- 插槽回 rest
  for _, s in ipairs(self.def.slots or {}) do
    self.slotState[s.name] = { x = s.x, y = s.y, rot = s.rot, sx = s.sx, sy = s.sy, color = s.color, att = s.att and s.att.name }
  end
  local c = self.clip and self.clips[self.clip]
  if c then
    for name, keys in pairs(c.bones or {}) do
      local b = self.boneDef[name]
      if b then
        local v = evalKeys(keys, self.time, b)
        local s = self.state[name]
        s.x, s.y, s.rot, s.sx, s.sy = v.x, v.y, v.rot, v.sx, v.sy
      end
    end
    for name, keys in pairs(c.slots or {}) do
      local sd = self.slotDef[name]
      if sd then
        local v = evalKeys(keys, self.time, sd)
        self.slotState[name] = { x = v.x, y = v.y, rot = v.rot, sx = v.sx, sy = v.sy, color = v.color or sd.color, att = v.att or (sd.att and sd.att.name) }
      end
    end
  end
end

function rig:worldMatrices()
  local out = {}
  for _, name in ipairs(self.boneOrder) do
    local b = self.boneDef[name]; local s = self.state[name]
    local pm = b.parent and out[b.parent] or IDENT
    out[name] = matMul(pm, matTRS(s.x, s.y, s.rot, s.sx, s.sy))
  end
  return out
end

-- 附件实例列表：{ att, m(世界矩阵), color, z }
function rig:drawList()
  local wm = self:worldMatrices()
  local out = {}
  for _, slot in ipairs(self.order) do
    local ss = self.slotState[slot.name] or {}
    local att = slot.att
    if ss.att and slot.atts then att = slot.atts[ss.att] or att end
    if att and att.img then
      local pm = wm[slot.bone] or IDENT
      local am = matMul(pm, matTRS(ss.x or 0, ss.y or 0, ss.rot or 0, ss.sx or 1, ss.sy or 1))
      out[#out + 1] = { slot = slot, att = att, m = am, color = ss.color or slot.color, z = slot.order or 0 }
    end
  end
  return out
end

-- LÖVE 绘制（从世界矩阵分解出 T/R/S；不用 applyTransform——其构造不是矩阵重载）
local function decompose(m)
  -- 假设无剪切：rot=atan2(b,a); sx=|col1|; sy=|col2|
  local rot = math.atan2(m.b, m.a)
  local sx = math.sqrt(m.a * m.a + m.b * m.b)
  local sy = math.sqrt(m.c * m.c + m.d * m.d)
  if (m.a * m.d - m.b * m.c) < 0 then sy = -sy end
  return m.e, m.f, rot, sx, sy
end
rig.decompose = decompose

function rig:draw(x, y, scale, flip)
  local g = love.graphics
  g.push()
  g.translate(x or 0, y or 0)
  g.scale((scale or 1) * (flip and -1 or 1), scale or 1)
  for _, d in ipairs(self:drawList()) do
    local m, att = d.m, d.att
    local tx, ty, rot, sx, sy = decompose(m)
    g.push()
    g.translate(tx, ty)
    g.rotate(rot)
    g.scale(sx, sy)
    if d.color then g.setColor(d.color[1], d.color[2], d.color[3], d.color[4] or 1) else g.setColor(1, 1, 1) end
    local iw, ih = att.img:getDimensions()
    local dw = (att.w or iw) * (att.scale or 1)
    local dh = (att.h or ih) * (att.scale or 1)
    g.draw(att.img, -(att.pivotX or dw / 2), -(att.pivotY or dh), 0, dw / iw, dh / ih)
    g.pop()
  end
  g.pop()
  g.setColor(1, 1, 1)
end

return rig
