-- skin.lua —— 单图 2D 网格蒙皮（LBS, Linear Blend Skinning）
-- 思路（不切图、无拼缝）：整张角色图铺一张网格，每个顶点按"到骨段距离"自动算权重，
--   每帧按骨骼变换把顶点形变后再绘制。阶段1：CPU 形变（验证正确性）；阶段2：换 GLSL 顶点着色器（GPU）。
--
-- 依赖：rig.lua（复用其骨骼层级 + 关键帧求值 + 矩阵工具）
--
-- 用法：
--   local skin = require("skin")
--   local S = skin.new({ image=img, bones={...}, clips={...}, segs={...}, grid={nx,ny} })
--   S:setClip("walk"); S:update(dt); S:draw(x, y, scale, flip)

local rig = require("rig")
local skin = {}
skin.__index = skin

local matMul, matTRS, IDENT = rig.matMul, rig.matTRS, rig.IDENT

-- 2x3 仿射求逆
local function matInv(m)
  local det = m.a * m.d - m.b * m.c
  if math.abs(det) < 1e-12 then return IDENT end
  local id = 1 / det
  return {
    a = m.d * id, b = -m.b * id,
    c = -m.c * id, d = m.a * id,
    e = (m.c * m.f - m.d * m.e) * id,
    f = (m.b * m.e - m.a * m.f) * id,
  }
end
skin.matInv = matInv

-- 点到线段 [p1,p2] 的最短距离
local function distSeg(px, py, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local l2 = dx * dx + dy * dy
  local t = l2 > 1e-9 and ((px - x1) * dx + (py - y1) * dy) / l2 or 0
  t = t < 0 and 0 or (t > 1 and 1 or t)
  local qx, qy = x1 + t * dx, y1 + t * dy
  return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end
skin.distSeg = distSeg

-- ---------- 构造 ----------
-- def: { image, bones={name,parent,x,y}, clips, segs={ [bone]={x1,y1,x2,y2} }, grid={nx,ny},
--        bbox={x,y,w,h}（可选，默认整图）, radius=R, power=P, maxInfl=4 }
function skin.new(def)
  local self = setmetatable({}, skin)
  self.def = def
  self.image = def.image
  local iw, ih = def.image:getDimensions()
  local b = def.bbox or { x = 0, y = 0, w = iw, h = ih }
  self.bbox = b

  -- 内部 rig（只借它的骨骼层级 + 关键帧求值）
  self.rig = rig.new({ bones = def.bones, clips = def.clips or {} })
  -- rest 世界矩阵 + 逆（bind pose）
  self.rig:setClip(nil); self.rig:_apply()
  local rest = self.rig:worldMatrices()
  local restSeg = {}  -- 解析骨段（用 segs 覆盖，否则用 parent->self）
  for _, bn in ipairs(def.bones) do
    local s = def.segs and def.segs[bn.name]
    if s then restSeg[bn.name] = s end
  end
  self.restWorld = rest
  self.invRest = {}
  for name, m in pairs(rest) do self.invRest[name] = matInv(m) end
  self.segs = restSeg

  -- 网格：规则网格覆盖 bbox（透明区无所谓，纹理为空）
  local nx, ny = (def.grid and def.grid[1]) or 24, (def.grid and def.grid[2]) or 36
  self.nx, self.ny = nx, ny
  local verts = {}
  self.vertBone = {}   -- 每顶点的 (idx[4], w[4])
  local RAD, POW, K = def.radius or 70, def.power or 2, def.maxInfl or 4
  local names = {}
  for i, bn in ipairs(def.bones) do names[i] = bn.name end
  self.boneNames = names
  for j = 0, ny do
    for i = 0, nx do
      local x = b.x + b.w * i / nx
      local y = b.y + b.h * j / ny
      -- 权重
      local raw, sum = {}, 0
      for bi, nm in ipairs(names) do
        local sg = self.segs[nm]
        if sg then
          local d = distSeg(x, y, sg[1], sg[2], sg[3], sg[4])
          local w = math.max(0, 1 - d / RAD)
          w = w ^ POW
          if w > 0 then raw[bi] = w; sum = sum + w end
        end
      end
      local idx, wts = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
      if sum > 0 then
        -- 取 top-K
        local arr = {}
        for bi, w in pairs(raw) do arr[#arr + 1] = { bi, w } end
        table.sort(arr, function(p, q) return p[2] > q[2] end)
        local ksum = 0
        for t = 1, math.min(K, #arr) do ksum = ksum + arr[t][2] end
        for t = 1, math.min(K, #arr) do
          idx[t] = arr[t][1] - 1        -- 0-based（给 shader）
          wts[t] = arr[t][2] / ksum
        end
      end
      verts[#verts + 1] = { x = x, y = y, u = x / iw, v = y / ih, idx = idx, w = wts, ox = x, oy = y }
    end
  end
  -- 三角形索引（规则网格两三角）
  local tris = {}
  local function vid(i, j) return j * (nx + 1) + i + 1 end
  for j = 0, ny - 1 do
    for i = 0, nx - 1 do
      tris[#tris + 1] = { vid(i, j), vid(i + 1, j), vid(i, j + 1) }
      tris[#tris + 1] = { vid(i + 1, j), vid(i + 1, j + 1), vid(i, j + 1) }
    end
  end
  self.verts, self.tris = verts, tris
  -- 展开：mesh 顶点按三角形顺序排列（LÖVE 不用索引列表，是按连续 3 顶点组三角形）
  local vorder = {}
  for _, t in ipairs(tris) do vorder[#vorder + 1] = t[1]; vorder[#vorder + 1] = t[2]; vorder[#vorder + 1] = t[3] end
  self.vorder = vorder

  -- LÖVE Mesh
  local fmt = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "float", 4 },
    { "BoneIndices", "float", 4 },
    { "BoneWeights", "float", 4 },
  }
  local vdata = {}
  if def.std then  -- 调试：默认格式（无自定义属性）
    fmt = nil
    for _, vi in ipairs(vorder) do local v = verts[vi]; vdata[#vdata + 1] = { v.x, v.y, v.u, v.v, 1, 1, 1, 1 } end
  else
    for _, vi in ipairs(vorder) do
      local v = verts[vi]
      vdata[#vdata + 1] = {
        v.x, v.y, v.u, v.v,
        1, 1, 1, 1,
        v.idx[1], v.idx[2], v.idx[3], v.idx[4],
        v.w[1], v.w[2], v.w[3], v.w[4],
      }
    end
  end
  if def.std then
    self.mesh = love.graphics.newMesh(vdata, "triangles", "dynamic")
  else
    self.mesh = love.graphics.newMesh(fmt, vdata, "triangles", "dynamic")
  end
  self.mesh:setTexture(def.image)
  return self
end

function skin:setClip(name, opt)
  self.clip, self.time, self.dur, self.loop = name, (opt and opt.time) or 0, nil, true
  local c = self.def.clips[name]
  if c then self.dur = c.duration; self.loop = c.loop ~= false end
end

function skin:update(dt)
  if self.dur then
    self.time = self.time + dt
    if self.time >= self.dur then
      if self.loop then self.time = self.time % self.dur
      else self.time = self.dur end
    end
  end
  self:deform()
end

-- 计算 skin 矩阵（animated world × invRest）
function skin:boneMatrices()
  self.rig:setClip(self.clip, { time = self.time }); self.rig:_apply()
  local world = self.rig:worldMatrices()
  local out = {}
  for _, nm in ipairs(self.boneNames) do
    out[nm] = matMul(world[nm], self.invRest[nm])
  end
  return out
end

-- CPU 形变：更新 mesh 顶点
function skin:deform()
  if not self.clip then return end
  local M = self:boneMatrices()
  local upd = {}
  for i, vi in ipairs(self.vorder) do
    local v = self.verts[vi]
    local x, y = 0, 0
    local tw = v.w[1] + v.w[2] + v.w[3] + v.w[4]
    if tw > 1e-6 then
      for t = 1, 4 do
        local w = v.w[t]
        if w > 0 then
          local m = M[self.boneNames[v.idx[t] + 1]]
          x = x + w * (m.a * v.ox + m.c * v.oy + m.e)
          y = y + w * (m.b * v.ox + m.d * v.oy + m.f)
        end
      end
    else
      x, y = v.ox, v.oy
    end
    upd[#upd + 1] = { x, y, v.u, v.v, 1, 1, 1, 1, v.idx[1], v.idx[2], v.idx[3], v.idx[4], v.w[1], v.w[2], v.w[3], v.w[4] }
  end
  for i, d in ipairs(upd) do self.mesh:setVertex(i, d) end
end

function skin:draw(x, y, scale, flip)
  love.graphics.draw(self.mesh, x or 0, y or 0, 0, (scale or 1) * (flip and -1 or 1), scale or 1)
end

return skin
