-- iso-kit.lua —— anatomy/kit/iso-kit.mjs 的 Lua(LuaJIT) 移植
-- 只算几何、输出 {fill,outline,crease,top,shades,bevel} 记录（JSON），渲染交给 Flutter(Dart)。
-- 原项目：https://github.com/wheresryan22/anatomy (MIT)
local M = {}

M.AZIMUTH = 45
M.ELEVATION = 30
M.SHADES = 4
local RAD = math.pi / 180
local UNIT = math.sqrt(1.6)

function M.cameraOf(p)
  local a = (p.azimuth or M.AZIMUTH) * RAD
  local e = (p.elevation or M.ELEVATION) * RAD
  return { sinA = math.sin(a), cosA = math.cos(a), sinE = math.sin(e), cosE = math.cos(e), k = p.scale * UNIT }
end

function M.iso(v, p)
  local c = M.cameraOf(p)
  local o = p.origin
  return {
    o[1] + (v[1] * c.sinA - v[2] * c.cosA) * c.k,
    o[2] + ((v[1] * c.cosA + v[2] * c.sinA) * c.sinE - v[3] * c.cosE) * c.k,
  }
end

function M.towardViewer(p)
  local c = M.cameraOf(p)
  return { c.cosA, c.sinA }
end

function M.depthOf(v, p)
  local c = M.cameraOf(p)
  return (v[1] * c.cosA + v[2] * c.sinA) * c.cosE + v[3] * c.sinE
end

local function tenth(value)
  local r = math.floor(value * 10 + 0.5) / 10
  if r == 0 then r = 0 end
  local s = string.format("%.1f", r)
  s = s:gsub("%.0$", "")
  if s == "-0" then s = "0" end
  return s
end

function M.pathOf(points, closed)
  if #points == 0 then return "" end
  local out = {}
  for i = 1, #points do
    out[#out + 1] = (i == 1 and "M" or "L") .. tenth(points[i][1]) .. " " .. tenth(points[i][2])
  end
  if closed then out[#out + 1] = "Z" end
  return table.concat(out)
end

function M.joinPaths(paths)
  local out = {}
  for i = 1, #paths do
    if paths[i] and paths[i] ~= "" then out[#out + 1] = paths[i] end
  end
  return table.concat(out)
end

-- plan = {x,y,w,d,r}
function M.roundedPlan(plan, steps)
  steps = steps or 8
  local x, y, w, d, r0 = plan[1], plan[2], plan[3], plan[4], plan[5] or 0
  local radius = math.max(0, math.min(r0, math.min(w / 2, d / 2)))
  local corners = {
    { x + w - radius, y + radius, -90 },
    { x + w - radius, y + d - radius, 0 },
    { x + radius, y + d - radius, 90 },
    { x + radius, y + radius, 180 },
  }
  local out = {}
  for _, co in ipairs(corners) do
    local cx, cy, start = co[1], co[2], co[3]
    local count = radius > 0 and steps or 0
    for step = 0, count do
      local angle = (start + (count > 0 and (90 * step) / count or 45)) * RAD
      out[#out + 1] = { cx + radius * math.cos(angle), cy + radius * math.sin(angle) }
    end
  end
  return out
end

local function signedArea(points)
  local area = 0
  local n = #points
  for i = 1, n do
    local a = points[i]
    local b = points[i % n + 1]
    area = area + a[1] * b[2] - b[1] * a[2]
  end
  return area / 2
end

function M.oriented(points)
  if signedArea(points) < 0 then
    local r = {}
    for i = #points, 1, -1 do r[#r + 1] = points[i] end
    return r
  end
  return points
end

function M.convexHull(points)
  local sorted = {}
  for i = 1, #points do sorted[i] = points[i] end
  table.sort(sorted, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  if #sorted < 3 then return sorted end
  local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
  local lower = {}
  for _, p in ipairs(sorted) do
    while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do table.remove(lower) end
    lower[#lower + 1] = p
  end
  local upper = {}
  for i = #sorted, 1, -1 do
    local p = sorted[i]
    while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do table.remove(upper) end
    upper[#upper + 1] = p
  end
  local out = {}
  for i = 1, #lower - 1 do out[#out + 1] = lower[i] end
  for i = 1, #upper - 1 do out[#out + 1] = upper[i] end
  return out
end

local function runsOf(flags, want)
  local count = #flags
  local runs = {}
  local start = nil
  for i = 1, count do
    local prev = (i - 2) % count + 1
    if flags[i] ~= flags[prev] then start = i break end
  end
  if not start then
    if flags[1] == want then
      local run = {}
      for i = 1, count + 1 do run[i] = (i - 1) % count + 1 end
      return { run }
    end
    return {}
  end
  local run = nil
  for step = 0, count - 1 do
    local index = (start - 1 + step) % count + 1
    if flags[index] == want then
      run = run or { index }
      run[#run + 1] = index % count + 1
    elseif run then
      runs[#runs + 1] = run
      run = nil
    end
  end
  if run then runs[#runs + 1] = run end
  return runs
end

-- ring = 点数组；返回 {fill, outline, crease, top, shades={s0..s3}, bevel}
function M.extrude(ring, z, height, p, convex, bevel)
  if convex == nil then convex = true end
  bevel = bevel or 0
  local count = #ring
  local counter = signedArea(ring) > 0
  local v = M.towardViewer(p)
  local c = M.cameraOf(p)
  local normals = {}
  for i = 1, count do
    local a = ring[i]
    local b = ring[i % count + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then len = 1 end
    if counter then normals[i] = { dy / len, -dx / len } else normals[i] = { -dy / len, dx / len } end
  end
  local facing = {}
  for i = 1, count do facing[i] = normals[i][1] * v[1] + normals[i][2] * v[2] > 1e-9 end
  local top, bottom = {}, {}
  for i = 1, count do
    top[i] = M.iso({ ring[i][1], ring[i][2], z + height }, p)
    bottom[i] = M.iso({ ring[i][1], ring[i][2], z }, p)
  end
  local outline, crease = {}, {}
  for _, run in ipairs(runsOf(facing, false)) do
    local pts = {}
    for k, i in ipairs(run) do pts[k] = top[i] end
    outline[#outline + 1] = M.pathOf(pts)
  end
  for _, run in ipairs(runsOf(facing, true)) do
    local pts = {}
    for k, i in ipairs(run) do pts[k] = top[i] end
    crease[#crease + 1] = M.pathOf(pts)
    if height > 0 then
      local pts2 = {}
      for k, i in ipairs(run) do pts2[k] = bottom[i] end
      outline[#outline + 1] = M.pathOf(pts2)
    end
  end
  if height > 0 then
    for i = 1, count do
      local prev = (i - 2) % count + 1
      if facing[prev] ~= facing[i] then outline[#outline + 1] = M.pathOf({ top[i], bottom[i] }) end
    end
  end
  local fill
  if convex then
    local both = {}
    for i = 1, #top do both[#both + 1] = top[i] end
    for i = 1, #bottom do both[#both + 1] = bottom[i] end
    fill = M.pathOf(M.convexHull(both), true)
  else
    local parts = { M.pathOf(M.oriented(top), true), M.pathOf(M.oriented(bottom), true) }
    for i = 1, count do
      if facing[i] then
        local nx = i % count + 1
        parts[#parts + 1] = M.pathOf(M.oriented({ top[i], top[nx], bottom[nx], bottom[i] }), true)
      end
    end
    fill = table.concat(parts)
  end
  local buckets = { {}, {}, {}, {} }
  if height > 0 then
    local lx, ly = -c.sinA, c.cosA
    for i = 1, count do
      if facing[i] then
        local n = normals[i]
        local lit = (n[1] * lx + n[2] * ly + 1) / 2
        local shade = math.min(M.SHADES - 1, math.max(0, math.floor(lit * M.SHADES))) + 1
        local nx = i % count + 1
        buckets[shade][#buckets[shade] + 1] = M.pathOf(M.oriented({ top[i], top[nx], bottom[nx], bottom[i] }), true)
      end
    end
  end
  local bevelPath
  if bevel > 0 then
    local inset = {}
    for i = 1, count do
      local a = normals[(i - 2) % count + 1]
      local b = normals[i]
      local mx, my = a[1] + b[1], a[2] + b[2]
      local len = math.sqrt(mx * mx + my * my)
      if len == 0 then len = 1 end
      inset[i] = { ring[i][1] - (mx / len) * bevel, ring[i][2] - (my / len) * bevel }
    end
    local insetTop = {}
    for i = 1, count do insetTop[i] = M.iso({ inset[i][1], inset[i][2], z + height }, p) end
    local parts = {}
    for _, run in ipairs(runsOf(facing, true)) do
      local pts = { top[run[1]] }
      for k = 2, #run - 1 do pts[#pts + 1] = insetTop[run[k]] end
      pts[#pts + 1] = top[run[#run]]
      parts[#parts + 1] = M.pathOf(pts)
    end
    bevelPath = table.concat(parts)
  end
  return {
    fill = fill,
    outline = table.concat(outline),
    crease = table.concat(crease),
    top = M.pathOf(M.oriented(top), true),
    shades = { table.concat(buckets[1]), table.concat(buckets[2]), table.concat(buckets[3]), table.concat(buckets[4]) },
    bevel = bevelPath,
  }
end

function M.ringOf(plan, steps) return M.roundedPlan(plan, steps or 8) end

function M.slabOf(plan, z, height, p, steps, bevel)
  return M.extrude(M.ringOf(plan, steps or 8), z, height, p, true, bevel or 0)
end

function M.circleRing(cx, cy, radius, steps)
  steps = steps or 40
  local out = {}
  for s = 0, steps - 1 do
    local a = (s / steps) * math.pi * 2
    out[#out + 1] = { cx + radius * math.cos(a), cy + radius * math.sin(a) }
  end
  return out
end

function M.cylinder(cx, cy, radius, z, height, p, steps, bevel)
  return M.extrude(M.circleRing(cx, cy, radius, steps or 32), z, height, p, true, bevel or 0)
end

function M.insetPlan(plan, by)
  return { plan[1] + by, plan[2] + by, plan[3] - by * 2, plan[4] - by * 2, math.max(0, (plan[5] or 0) - by) }
end

function M.onTop(points, z, p, closed)
  local out = {}
  for i = 1, #points do out[i] = M.iso({ points[i][1], points[i][2], z }, p) end
  return M.pathOf(out, closed)
end

function M.planOutline(plan, z, p, steps) return M.onTop(M.ringOf(plan, steps or 8), z, p, true) end
function M.lineOnTop(from, to, z, p) return M.onTop({ from, to }, z, p) end
function M.segment(from, to, p) return M.pathOf({ M.iso(from, p), M.iso(to, p) }) end
function M.rise(at, from, to, p) return M.segment({ at[1], at[2], from }, { at[1], at[2], to }, p) end
function M.ring(cx, cy, radius, z, p, steps) return M.onTop(M.circleRing(cx, cy, radius, steps or 40), z, p, true) end

function M.pointsAt(points, p)
  local out = {}
  for i = 1, #points do out[i] = M.iso(points[i], p) end
  return out
end

function M.dotGrid(x, y, columns, rows, gap, z, p)
  local dots = {}
  for row = 0, rows - 1 do
    for col = 0, columns - 1 do dots[#dots + 1] = M.iso({ x + col * gap, y + row * gap, z }, p) end
  end
  return dots
end

function M.corners(box, inset)
  inset = inset or 0
  return {
    { box[1] + inset, box[2] + inset },
    { box[1] + box[3] - inset, box[2] + inset },
    { box[1] + inset, box[2] + box[4] - inset },
    { box[1] + box[3] - inset, box[2] + box[4] - inset },
  }
end

function M.boxCorners(box, z0, z1)
  local out = {}
  for _, px in ipairs({ box[1], box[1] + box[3] }) do
    for _, py in ipairs({ box[2], box[2] + box[4] }) do
      for _, z in ipairs({ z0, z1 }) do out[#out + 1] = { px, py, z } end
    end
  end
  return out
end

function M.knurl(cx, cy, radius, z0, z1, count, p, inset)
  inset = inset or 0.4
  local v = M.towardViewer(p)
  local lines = {}
  for i = 0, count - 1 do
    local a = (i / count) * math.pi * 2
    local nx, ny = math.cos(a), math.sin(a)
    if nx * v[1] + ny * v[2] >= 0.15 then
      lines[#lines + 1] = M.segment({ cx + radius * nx, cy + radius * ny, z0 + inset }, { cx + radius * nx, cy + radius * ny, z1 - inset }, p)
    end
  end
  return table.concat(lines)
end

function M.sideArc(cx, cy, radius, z, p, steps)
  steps = steps or 24
  local v = M.towardViewer(p)
  local facing = math.atan2(v[2], v[1])
  local points = {}
  for step = 0, steps do
    local a = facing - math.pi / 2 + (step / steps) * math.pi
    points[#points + 1] = M.iso({ cx + radius * math.cos(a), cy + radius * math.sin(a), z }, p)
  end
  return M.pathOf(points)
end

function M.haloOf(plan, z, height, p) return M.slabOf(plan, z, height, p).fill end

function M.fitProjection(points, width, height, opts)
  opts = opts or {}
  local pad = opts.pad or 24
  local headroom = opts.headroom or 0
  local az = opts.azimuth or M.AZIMUTH
  local el = opts.elevation or M.ELEVATION
  local unit = { origin = { 0, 0 }, scale = 1, azimuth = az, elevation = el }
  local left, right, up, down
  for i = 1, #points do
    local f = M.iso(points[i], unit)
    if not left or f[1] < left then left = f[1] end
    if not right or f[1] > right then right = f[1] end
    if not up or f[2] < up then up = f[2] end
    if not down or f[2] > down then down = f[2] end
  end
  local scale = math.min((width - pad * 2) / (right - left), (height - pad * 2 - headroom) / (down - up))
  return {
    origin = { width / 2 - ((left + right) / 2) * scale, headroom + (height - headroom) / 2 - ((up + down) / 2) * scale },
    scale = scale,
    azimuth = az,
    elevation = el,
  }
end

return M
