-- lathe.lua —— anatomy/kit/lathe.mjs 的 Lua(LuaJIT) 移植（全量）
-- 原项目：https://github.com/wheresryan22/anatomy (MIT)
local k = require("iso_kit")
local M = {}

local TAU = math.pi * 2
local LIGHT_UP = 1.2
local BANDS = { 0, 0.2, 0.42, 0.62 }

-- 三维向量（数组 {x,y,z}）
local function dot3(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function add3(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function sub3(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function mul3(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
local function len3(a) return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
local function unit3(a)
  local l = len3(a)
  if l == 0 then return { 0, 0, 0 } end
  return { a[1] / l, a[2] / l, a[3] / l }
end
local function cross3(a, b)
  return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function lerp3(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
M.dot3, M.add3, M.sub3, M.mul3, M.len3, M.unit3, M.cross3, M.lerp3 = dot3, add3, sub3, mul3, len3, unit3, cross3, lerp3

function M.viewOf(p)
  local c = k.cameraOf(p)
  return { c.cosA * c.cosE, c.sinA * c.cosE, c.sinE }
end
function M.lightOf(p)
  local c = k.cameraOf(p)
  return unit3({ -c.sinA, c.cosA, LIGHT_UP })
end
function M.scaleOf(p) return k.cameraOf(p).k end
function M.bandOf(score)
  local tone = 0
  while tone < #BANDS and score >= BANDS[tone + 1] do tone = tone + 1 end
  return tone
end
function M.toneOf(normal, p) return M.bandOf(dot3(unit3(normal), M.lightOf(p))) end

function M.frameAlong(o, a)
  local axis = unit3(a)
  local helper = math.abs(axis[3]) > 0.9 and { 1, 0, 0 } or { 0, 0, 1 }
  local u = unit3(cross3(helper, axis))
  local v = cross3(axis, u)
  return { o = o, a = axis, u = u, v = v }
end
function M.frameOf(o, a, u, v) return { o = o, a = a, u = u, v = v } end
function M.pointOf(f, s, r, angle)
  local c, n = math.cos(angle), math.sin(angle)
  return {
    f.o[1] + f.a[1] * s + r * (c * f.u[1] + n * f.v[1]),
    f.o[2] + f.a[2] * s + r * (c * f.u[2] + n * f.v[2]),
    f.o[3] + f.a[3] * s + r * (c * f.u[3] + n * f.v[3]),
  }
end
function M.radialOf(f, angle)
  local c, n = math.cos(angle), math.sin(angle)
  return { c * f.u[1] + n * f.v[1], c * f.u[2] + n * f.v[2], c * f.u[3] + n * f.v[3] }
end
function M.tangentOf(f, angle)
  local c, n = math.cos(angle), math.sin(angle)
  return { -n * f.u[1] + c * f.v[1], -n * f.u[2] + c * f.v[2], -n * f.u[3] + c * f.v[3] }
end
function M.angleToward(f, dir) return math.atan2(dot3(dir, f.v), dot3(dir, f.u)) end

-- 凸包（带标签 ring）
local function hullTagged(points)
  local sorted = {}
  for i = 1, #points do sorted[i] = points[i] end
  table.sort(sorted, function(a, b)
    if a.p[1] ~= b.p[1] then return a.p[1] < b.p[1] end
    return a.p[2] < b.p[2]
  end)
  if #sorted < 3 then return sorted end
  local function cross(o, a, b) return (a.p[1] - o.p[1]) * (b.p[2] - o.p[2]) - (a.p[2] - o.p[2]) * (b.p[1] - o.p[1]) end
  local lower = {}
  for _, pt in ipairs(sorted) do
    while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], pt) <= 1e-9 do table.remove(lower) end
    lower[#lower + 1] = pt
  end
  local upper = {}
  for i = #sorted, 1, -1 do
    local pt = sorted[i]
    while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], pt) <= 1e-9 do table.remove(upper) end
    upper[#upper + 1] = pt
  end
  local out = {}
  for i = 1, #lower - 1 do out[#out + 1] = lower[i] end
  for i = 1, #upper - 1 do out[#out + 1] = upper[i] end
  return out
end
function M.hullOf(points)
  local tagged = {}
  for i = 1, #points do tagged[i] = { p = points[i] } end
  local h = hullTagged(tagged)
  local out = {}
  for i = 1, #h do out[i] = h[i].p end
  return out
end

local function runsTrue(flags)
  local count = #flags
  local start = nil
  for i = 1, count do
    local prev = (i - 2) % count + 1
    if flags[i] ~= flags[prev] then start = i break end
  end
  if not start then
    if flags[1] then
      local run = {}
      for i = 1, count + 1 do run[i] = (i - 1) % count + 1 end
      return { run }
    end
    return {}
  end
  local runs, run = {}, nil
  for step = 0, count - 1 do
    local index = (start - 1 + step) % count + 1
    if flags[index] then
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
M.runsOf = runsTrue

local function groupsOf(keys)
  local count = #keys
  local out = {}
  local start = nil
  for i = 1, count do
    local prev = (i - 2) % count + 1
    if keys[i] ~= keys[prev] then start = i break end
  end
  if not start then
    if keys[1] ~= nil then
      local run = {}
      for i = 1, count + 1 do run[i] = (i - 1) % count + 1 end
      out[1] = { key = keys[1], run = run }
    end
    return out
  end
  local current = nil
  for step = 0, count - 1 do
    local index = (start - 1 + step) % count + 1
    local key = keys[index]
    if current and current.key == key then
      current.run[#current.run + 1] = index % count + 1
    else
      if current and current.key ~= nil then out[#out + 1] = current end
      current = { key = key, run = { index, index % count + 1 } }
    end
  end
  if current and current.key ~= nil then out[#out + 1] = current end
  return out
end
M.groupsOf = groupsOf

function M.stepsFor(radius, least, most, scale)
  least = least or 16
  most = most or 112
  scale = scale or 0
  if scale ~= 0 then return math.max(least, math.min(most, math.ceil((TAU * radius * scale) / 3))) end
  return math.max(least, math.min(most, math.floor((radius * 1.3) / 4 + 0.5) * 4))
end

local function softOf(meridian)
  for i = 1, #meridian do
    if meridian[i][3] and meridian[i][3] ~= 0 then return true end
  end
  return false
end
M.softOf = softOf

-- ── 样条 ──
local function sign(x) if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end end

local function hermiteSlopes(run)
  local n = #run - 1
  local h, delta = {}, {}
  for j = 1, n do
    h[j] = run[j + 1][1] - run[j][1]
    delta[j] = (h[j] == 0) and 0 or (run[j + 1][2] - run[j][2]) / h[j]
  end
  local d = {}
  for k = 0, n do d[k] = 0 end
  local function e(h0, h1, d0, d1)
    local v = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
    if sign(v) ~= sign(d0) then v = 0
    elseif sign(d0) ~= sign(d1) and math.abs(v) > math.abs(3 * d0) then v = 3 * d0 end
    return v
  end
  if n == 1 then d[0], d[1] = delta[1], delta[1]
  else d[0] = e(h[1], h[2], delta[1], delta[2]); d[n] = e(h[n], h[n - 1], delta[n], delta[n - 1]) end
  for kk = 1, n - 1 do
    if delta[kk] * delta[kk + 1] > 0 then
      local w1 = 2 * h[kk + 1] + h[kk]
      local w2 = h[kk + 1] + 2 * h[kk]
      d[kk] = (w1 + w2) / (w1 / delta[kk] + w2 / delta[kk + 1])
    end
  end
  return d
end

local function curveRuns(meridian)
  local m = #meridian
  local segments = {}
  local start = 1
  while start < m do
    local fin = start + 1
    while fin < m and meridian[fin][3] and meridian[fin][3] ~= 0
      and math.abs(meridian[fin + 1][1] - meridian[fin][1]) > 1e-9
      and math.abs(meridian[fin][1] - meridian[fin - 1][1]) > 1e-9 do fin = fin + 1 end
    local run = {}
    for i = start, fin do run[#run + 1] = meridian[i] end
    local n = #run - 1
    local ok = n >= 2
    for j = 2, #run do if math.abs(run[j][1] - run[j - 1][1]) <= 1e-9 then ok = false break end end
    if ok then
      local d = hermiteSlopes(run)
      for j = 1, n do
        local s0, r0 = run[j][1], run[j][2]
        local s1, r1 = run[j + 1][1], run[j + 1][2]
        local hj = s1 - s0
        local d0, d1 = d[j - 1], d[j]
        segments[start + j - 1] = {
          radius = function(s)
            local t = hj == 0 and 0 or (s - s0) / hj
            return (2 * t ^ 3 - 3 * t ^ 2 + 1) * r0 + (t ^ 3 - 2 * t ^ 2 + t) * hj * d0
              + (-2 * t ^ 3 + 3 * t ^ 2) * r1 + (t ^ 3 - t ^ 2) * hj * d1
          end,
          slope = function(s)
            local t = hj == 0 and 0 or (s - s0) / hj
            return ((6 * t ^ 2 - 6 * t) * r0 + (6 * t - 6 * t ^ 2) * r1) / hj
              + (3 * t ^ 2 - 4 * t + 1) * d0 + (3 * t ^ 2 - 2 * t) * d1
          end,
        }
      end
    end
    start = fin
  end
  return segments
end
M.curveRuns = curveRuns

function M.curved(meridian, p, segments, error, depth)
  error = error or 0.2
  depth = depth or 6
  local kk = M.scaleOf(p)
  local out = { meridian[1] }
  for i = 1, #meridian - 1 do
    local curve = segments[i]
    local s0, s1 = meridian[i][1], meridian[i + 1][1]
    if curve then
      local function split(a, b, level)
        local mid = (a + b) / 2
        local chord = (curve.radius(a) + curve.radius(b)) / 2
        if level < depth and math.abs(curve.radius(mid) - chord) * kk > error then
          split(a, mid, level + 1)
          out[#out + 1] = { mid, curve.radius(mid), 1 }
          split(mid, b, level + 1)
        end
      end
      split(s0, s1, 0)
    end
    out[#out + 1] = meridian[i + 1]
  end
  return out
end

-- ── labelledArcs ──
local function labelledArcs(nr, na, view, light, gr, ga)
  gr = gr or nr
  ga = ga or na
  local cuts = {}
  if math.abs(gr) > 1e-9 then
    local vc = -(ga * view.a) / (gr * view.flat)
    if vc > -1 and vc < 1 then
      local dd = math.acos(vc)
      cuts[#cuts + 1] = view.phi - dd
      cuts[#cuts + 1] = view.phi + dd
    end
  end
  if math.abs(nr) > 1e-9 then
    for _, th in ipairs(BANDS) do
      local c = (th - na * light.a) / (nr * light.flat)
      if c > -1 and c < 1 then
        local dd = math.acos(c)
        cuts[#cuts + 1] = light.phi - dd
        cuts[#cuts + 1] = light.phi + dd
      end
    end
  end
  local function wrap(a) return ((a % TAU) + TAU) % TAU end
  local seen, sorted = {}, {}
  for _, a in ipairs(cuts) do
    local r = math.floor(wrap(a) * 1e9 + 0.5) / 1e9
    if not seen[r] then seen[r] = true; sorted[#sorted + 1] = r end
  end
  table.sort(sorted)
  local function label(angle)
    local facing = gr * view.flat * math.cos(angle - view.phi) + ga * view.a
    if facing <= 1e-9 then return -1 end
    return M.bandOf(nr * light.flat * math.cos(angle - light.phi) + na * light.a)
  end
  if #sorted == 0 then
    local tone = label(0)
    if tone < 0 then return {} end
    return { { tone = tone, from = 0, to = TAU, full = true } }
  end
  local arcs = {}
  for index = 1, #sorted do
    local from = sorted[index]
    local to = index < #sorted and sorted[index + 1] or sorted[1] + TAU
    arcs[#arcs + 1] = { tone = label((from + to) / 2), from = from, to = to }
  end
  local merged = {}
  for _, arc in ipairs(arcs) do
    local last = merged[#merged]
    if last and last.tone == arc.tone and math.abs(last.to - arc.from) < 1e-9 then last.to = arc.to
    else merged[#merged + 1] = { tone = arc.tone, from = arc.from, to = arc.to } end
  end
  if #merged > 1 and merged[1].tone == merged[#merged].tone
    and math.abs(merged[#merged].to - TAU - merged[1].from) < 1e-9 then
    local last = table.remove(merged)
    merged[1].from = last.from - TAU
  end
  local out = {}
  for _, a in ipairs(merged) do if a.tone >= 0 then out[#out + 1] = a end end
  return out
end
M.labelledArcs = labelledArcs

-- ── smoothRows（平滑着色）──
local function smoothRows(meridian, f, p, opts)
  opts = opts or {}
  local rows = opts.rows or 6
  local steps = opts.steps or 48
  local error_ = opts.error or 0.35
  local deepest = opts.depth or 8
  local fineness = opts.fineness or 0.1
  local slopeFn, radiusFn = opts.slope, opts.radius
  local v = M.viewOf(p)
  local l = M.lightOf(p)
  local view = { a = dot3(f.a, v), flat = math.sqrt(dot3(f.u, v) ^ 2 + dot3(f.v, v) ^ 2), phi = math.atan2(dot3(f.v, v), dot3(f.u, v)) }
  local light = { a = dot3(f.a, l), flat = math.sqrt(dot3(f.u, l) ^ 2 + dot3(f.v, l) ^ 2), phi = math.atan2(dot3(f.v, l), dot3(f.u, l)) }
  local m = #meridian
  local faces = {}
  for i = 1, m - 1 do
    local ds = meridian[i + 1][1] - meridian[i][1]
    local dr = meridian[i + 1][2] - meridian[i][2]
    local len = math.sqrt(ds * ds + dr * dr)
    if len == 0 then len = 1 end
    faces[i] = { ds / len, -dr / len }
  end
  local splines = slopeFn and nil or curveRuns(meridian)
  local function vertexNormal(kk, own)
    if kk <= 1 or kk >= m or not (meridian[kk][3] and meridian[kk][3] ~= 0) then return own end
    local a, b = faces[kk - 1], faces[kk]
    local x, y = a[1] + b[1], a[2] + b[2]
    local len = math.sqrt(x * x + y * y)
    if len == 0 then len = 1 end
    return { x / len, y / len }
  end
  local function normalAt(i, u)
    local s0, s1 = meridian[i][1], meridian[i + 1][1]
    local s = s0 + (s1 - s0) * u
    local sgn = sign(s1 - s0) == 0 and 1 or sign(s1 - s0)
    local g
    if slopeFn then g = slopeFn(s)
    elseif splines[i] then g = splines[i].slope(s) end
    if g then
      local len = math.sqrt(1 + g * g)
      return { sgn / len, (-sgn * g) / len }
    end
    local a = vertexNormal(i, faces[i])
    local b = vertexNormal(i + 1, faces[i])
    local x, y = a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u
    local len = math.sqrt(x * x + y * y)
    if len == 0 then len = 1 end
    return { x / len, y / len }
  end
  local function pointAt(i, u, angle)
    local s0, r0 = meridian[i][1], meridian[i][2]
    local s1, r1 = meridian[i + 1][1], meridian[i + 1][2]
    local s = s0 + (s1 - s0) * u
    local r
    if radiusFn then r = radiusFn(s)
    elseif splines[i] then r = splines[i].radius(s)
    else r = r0 + (r1 - r0) * u end
    return k.iso(M.pointOf(f, s, r, angle), p)
  end
  local buckets = { {}, {}, {}, {}, {} }
  local fine = TAU / math.max(24, math.min(192, steps * 1.5))
  local function arcPoints(i, u, from, to)
    local count = math.max(1, math.ceil((to - from) / fine))
    local out = {}
    for index = 0, count do out[index + 1] = pointAt(i, u, from + (to - from) * index / count) end
    return out
  end
  local function centreOf(arc, reference)
    local mid = (arc.from + arc.to) / 2 - reference
    return ((mid % TAU) + TAU) % TAU
  end
  local function levelOf(i, u)
    local nl = normalAt(i, u)
    local groups = {}
    for _, arc in ipairs(labelledArcs(nl[1], nl[2], view, light, faces[i][1], faces[i][2])) do
      groups[arc.tone] = groups[arc.tone] or {}
      groups[arc.tone][#groups[arc.tone] + 1] = arc
    end
    for _, list in pairs(groups) do
      table.sort(list, function(x, y) return centreOf(x, light.phi) < centreOf(y, light.phi) end)
    end
    return { i = i, u = u, groups = groups }
  end
  local function same(x, y)
    local nx, ny = 0, 0
    for _ in pairs(x.groups) do nx = nx + 1 end
    for _ in pairs(y.groups) do ny = ny + 1 end
    if nx ~= ny then return false end
    for tone, list in pairs(x.groups) do
      if not y.groups[tone] or #y.groups[tone] ~= #list then return false end
    end
    return true
  end
  local function align(reference, arc)
    local out = { tone = arc.tone, from = arc.from, to = arc.to, full = arc.full }
    local centre = (reference.from + reference.to) / 2
    while (out.from + out.to) / 2 - centre > math.pi do out.from = out.from - TAU; out.to = out.to - TAU end
    while centre - (out.from + out.to) / 2 > math.pi do out.from = out.from + TAU; out.to = out.to + TAU end
    return out
  end
  local function strayOf(i, a, mid, b)
    local worst = 0
    for tone, list in pairs(mid.groups) do
      for index, arc in ipairs(list) do
        local lo = align(arc, a.groups[tone][index])
        local hi = align(arc, b.groups[tone][index])
        for _, key in ipairs({ "from", "to" }) do
          local pa = pointAt(i, mid.u, arc[key])
          local p0 = pointAt(i, a.u, lo[key])
          local p1 = pointAt(i, b.u, hi[key])
          worst = math.max(worst, math.sqrt((pa[1] - (p0[1] + p1[1]) / 2) ^ 2 + (pa[2] - (p0[2] + p1[2]) / 2) ^ 2))
        end
      end
    end
    return worst
  end
  local function sheet(tone, levels)
    for index, arc in ipairs(levels[1].groups[tone]) do
      local chain = { arc }
      for kk = 2, #levels do chain[#chain + 1] = align(chain[#chain], levels[kk].groups[tone][index]) end
      local last = #levels
      local points = {}
      for _, pt in ipairs(arcPoints(levels[1].i, levels[1].u, chain[1].from, chain[1].to)) do points[#points + 1] = pt end
      for kk = 2, last - 1 do points[#points + 1] = pointAt(levels[kk].i, levels[kk].u, chain[kk].to) end
      local tail = arcPoints(levels[last].i, levels[last].u, chain[last].from, chain[last].to)
      for i2 = #tail, 1, -1 do points[#points + 1] = tail[i2] end
      for kk = last - 1, 2, -1 do points[#points + 1] = pointAt(levels[kk].i, levels[kk].u, chain[kk].from) end
      buckets[tone + 1][#buckets[tone + 1] + 1] = k.pathOf(k.oriented(points), true)
    end
  end
  local function strip(tone, a, b)
    local below = a.groups[tone] or {}
    local above = {}
    for _, arc in ipairs(b.groups[tone] or {}) do above[#above + 1] = { arc = arc, used = false } end
    local function quad(f0, t0, f1, t1)
      local points = {}
      for _, pt in ipairs(arcPoints(a.i, a.u, f0, t0)) do points[#points + 1] = pt end
      local bp = arcPoints(b.i, b.u, f1, t1)
      for i2 = #bp, 1, -1 do points[#points + 1] = bp[i2] end
      buckets[tone + 1][#buckets[tone + 1] + 1] = k.pathOf(k.oriented(points), true)
    end
    for _, arc in ipairs(below) do
      local best, score = nil, -math.huge
      for _, entry in ipairs(above) do
        if not entry.used then
          local al = align(arc, entry.arc)
          local value = math.min(arc.to, al.to) - math.max(arc.from, al.from)
          if value > score then score = value; best = entry end
        end
      end
      if best and score > -0.05 then
        best.used = true
        local al = align(arc, best.arc)
        quad(arc.from, arc.to, al.from, al.to)
      else
        local centre = (arc.from + arc.to) / 2
        quad(arc.from, arc.to, centre, centre)
      end
    end
    for _, entry in ipairs(above) do
      if not entry.used then
        local centre = (entry.arc.from + entry.arc.to) / 2
        quad(centre, centre, entry.arc.from, entry.arc.to)
      end
    end
  end
  local kk = M.scaleOf(p)
  local run = {}
  local function flush()
    local toneSet = {}
    for _, level in ipairs(run) do for tone in pairs(level.groups) do toneSet[tone] = true end end
    local tones = {}
    for tone in pairs(toneSet) do tones[#tones + 1] = tone end
    table.sort(tones)
    for _, tone in ipairs(tones) do
      local function countOf(level) return #(level.groups[tone] or {}) end
      local startAt = 1
      for at = 2, #run + 1 do
        if at <= #run and countOf(run[at - 1]) == countOf(run[at]) then
          -- continue
        else
          if at - 1 > startAt and countOf(run[startAt]) > 0 then
            local levels = {}
            for i2 = startAt, at - 1 do levels[#levels + 1] = run[i2] end
            sheet(tone, levels)
          end
          if at <= #run then strip(tone, run[at - 1], run[at]) end
          startAt = at
        end
      end
    end
    run = {}
  end
  for i = 1, m - 1 do
    local ds = meridian[i + 1][1] - meridian[i][1]
    if math.abs(ds) < 1e-9 then
      flush()
    else
      local count = math.max(1, rows)
      local reach = math.sqrt(ds * ds + (meridian[i + 1][2] - meridian[i][2]) ^ 2) * kk / count
      local limit = math.max(1, math.min(deepest, math.ceil(math.log(math.max(2, reach / fineness)) / math.log(2))))
      local coarse = {}
      for index = 0, count do coarse[index + 1] = levelOf(i, index / count) end
      run[#run + 1] = coarse[1]
      local function refine(a, b, depth)
        local mid = levelOf(i, (a.u + b.u) / 2)
        local split = depth < limit and (not same(a, b) or not same(a, mid) or (depth < 6 and strayOf(i, a, mid, b) > error_))
        if not split then run[#run + 1] = b return end
        refine(a, mid, depth + 1)
        refine(mid, b, depth + 1)
      end
      for index = 2, count + 1 do refine(coarse[index - 1], coarse[index], 0) end
    end
  end
  flush()
  return buckets
end
M.smoothRows = smoothRows

-- ── sideOf / silhouettePoints / surfaceOf ──
local function sideOf(meridian)
  local m = #meridian
  local first, last = 1, m
  if meridian[1][2] <= 1e-9 then first = 2 end
  if meridian[m][2] <= 1e-9 then last = m - 1 end
  local side = {}
  for i = first, last do side[#side + 1] = meridian[i] end
  for i = 2, #side do if side[i][1] - side[i - 1][1] <= 1e-9 then return nil end end
  if #side >= 3 then return side end
  return nil
end
M.sideOf = sideOf

function M.silhouettePoints(profile, f, p, opts)
  opts = opts or {}
  local samples = opts.samples or 72
  local slopeFn, radiusFn = opts.slope, opts.radius
  local v = M.viewOf(p)
  local aV, uV, vV = dot3(f.a, v), dot3(f.u, v), dot3(f.v, v)
  local facing = math.atan2(vV, uV)
  local flat = math.sqrt(uV * uV + vV * vV)
  if flat == 0 then flat = 1e-9 end
  local s0, s1 = profile[1][1], profile[#profile][1]
  local function radiusAt(s)
    if radiusFn then return radiusFn(s) end
    local index = 2
    while index < #profile and profile[index][1] < s do index = index + 1 end
    local sa, ra = profile[index - 1][1], profile[index - 1][2]
    local sb, rb = profile[index][1], profile[index][2]
    local d = sb - sa
    if d == 0 then d = 1 end
    return ra + (rb - ra) * (s - sa) / d
  end
  local function side(sgn)
    local points = {}
    for step = 0, samples do
      local s = s0 + (s1 - s0) * step / samples
      local h = (s1 - s0) / samples / 2
      local sv
      if slopeFn then sv = slopeFn(s)
      else
        local den = math.min(s1, s + h) - math.max(s0, s - h)
        if den == 0 then den = 1 end
        sv = (radiusAt(math.min(s1, s + h)) - radiusAt(math.max(s0, s - h))) / den
      end
      local c = sv * aV / flat
      if math.abs(c) <= 1 then
        points[#points + 1] = M.pointOf(f, s, radiusAt(s), facing + sgn * math.acos(c))
      end
    end
    return points
  end
  return { side(1), side(-1) }
end

function M.silhouetteOf(profile, f, p, opts)
  local pts = M.silhouettePoints(profile, f, p, opts)
  local out = {}
  for _, list in ipairs(pts) do
    local flat = {}
    for i = 1, #list do flat[i] = k.iso(list[i], p) end
    out[#out + 1] = k.pathOf(flat)
  end
  return table.concat(out)
end

function M.surfaceOf(side, f, p, rims, opts)
  opts = opts or {}
  local samples = opts.samples or 96
  local v = M.viewOf(p)
  local aV = dot3(f.a, v)
  local facing = math.atan2(dot3(f.v, v), dot3(f.u, v))
  local sil = M.silhouettePoints(side, f, p, { samples = samples, slope = opts.slope })
  local left, right = sil[1], sil[2]
  if #left <= samples or #right <= samples then return nil end
  local s0, s1 = side[1][1], side[#side][1]
  local function angleOf(point)
    local proj = add3(f.o, mul3(f.a, dot3(sub3(point, f.o), f.a)))
    return M.angleToward(f, sub3(point, proj))
  end
  local function wrap(a) return ((a % TAU) + TAU) % TAU end
  local function arc(s, r, from, to, through)
    local sweep = wrap(to - from)
    if wrap(through - from) > sweep then sweep = sweep - TAU end
    local count = math.max(4, math.ceil(math.abs(sweep) / (TAU / 96)), math.ceil(math.abs(sweep) * r * M.scaleOf(p) / 1.5))
    local out = {}
    for index = 0, count do out[index + 1] = k.iso(M.pointOf(f, s, r, from + sweep * index / count), p) end
    return out
  end
  local r0, r1 = side[1][2], side[#side][2]
  local bottom = -aV > 0 and facing + math.pi or facing
  local top = aV > 0 and facing + math.pi or facing
  local L, R = {}, {}
  for i = 1, #left do L[i] = k.iso(left[i], p) end
  for i = 1, #right do R[i] = k.iso(right[i], p) end
  local topArc = arc(s1, r1, angleOf(left[#left]), angleOf(right[#right]), top)
  local bottomArc = arc(s0, r0, angleOf(right[1]), angleOf(left[1]), bottom)
  local keepFirst = rims == "all" or rims == "first" or rims == "ends"
  local keepLast = rims == "all" or rims == "last" or rims == "ends"
  local fillPts = {}
  for _, pt in ipairs(L) do fillPts[#fillPts + 1] = pt end
  for _, pt in ipairs(topArc) do fillPts[#fillPts + 1] = pt end
  for i = #R, 1, -1 do fillPts[#fillPts + 1] = R[i] end
  for _, pt in ipairs(bottomArc) do fillPts[#fillPts + 1] = pt end
  local fill = k.pathOf(fillPts, true)
  local outline = k.pathOf(L) .. k.pathOf(R) .. (keepLast and k.pathOf(topArc) or "") .. (keepFirst and k.pathOf(bottomArc) or "")
  local hullIn = {}
  for _, pt in ipairs(arc(s0, r0, 0, TAU - 1e-6, math.pi)) do hullIn[#hullIn + 1] = pt end
  for _, pt in ipairs(arc(s1, r1, 0, TAU - 1e-6, math.pi)) do hullIn[#hullIn + 1] = pt end
  for _, pt in ipairs(L) do hullIn[#hullIn + 1] = pt end
  for _, pt in ipairs(R) do hullIn[#hullIn + 1] = pt end
  local hull = k.convexHull(hullIn)
  local gap = 0
  for _, pt in ipairs(L) do
    local best = math.huge
    for index = 1, #hull do
      local a = hull[index]
      local b = hull[index % #hull + 1]
      local dx, dy = b[1] - a[1], b[2] - a[2]
      local den = dx * dx + dy * dy
      if den == 0 then den = 1 end
      local t = math.max(0, math.min(1, ((pt[1] - a[1]) * dx + (pt[2] - a[2]) * dy) / den))
      best = math.min(best, math.sqrt((pt[1] - a[1] - dx * t) ^ 2 + (pt[2] - a[2] - dy * t) ^ 2))
    end
    gap = math.max(gap, best)
  end
  for _, pt in ipairs(R) do
    local best = math.huge
    for index = 1, #hull do
      local a = hull[index]
      local b = hull[index % #hull + 1]
      local dx, dy = b[1] - a[1], b[2] - a[2]
      local den = dx * dx + dy * dy
      if den == 0 then den = 1 end
      local t = math.max(0, math.min(1, ((pt[1] - a[1]) * dx + (pt[2] - a[2]) * dy) / den))
      best = math.min(best, math.sqrt((pt[1] - a[1] - dx * t) ^ 2 + (pt[2] - a[2] - dy * t) ^ 2))
    end
    gap = math.max(gap, best)
  end
  return { fill = fill, outline = outline, gap = gap }
end

local function chains(edges)
  local out, current = {}, nil
  for _, e in ipairs(edges) do
    if not e[3] then
      if current then out[#out + 1] = current end
      current = nil
    else
      if not current then current = { e[1] } end
      current[#current + 1] = e[2]
    end
  end
  if current then out[#out + 1] = current end
  if #out > 1 and edges[1][3] and edges[#edges][3] then
    local last = table.remove(out)
    local merged = {}
    for _, pt in ipairs(last) do merged[#merged + 1] = pt end
    for i = 2, #out[1] do merged[#merged + 1] = out[1][i] end
    out[1] = merged
  end
  return out
end

-- shapeOf / outlineOf
local function shapeOf(meridian, p, smooth, slopeFn, radiusFn)
  if smooth and radiusFn then
    local segments = {}
    for index = 1, #meridian - 1 do
      if math.abs(meridian[index + 1][1] - meridian[index][1]) > 1e-9 then
        segments[index] = { radius = radiusFn, slope = slopeFn or function() return 0 end }
      end
    end
    return M.curved(meridian, p, segments)
  end
  local curves = (smooth and not slopeFn) and curveRuns(meridian) or nil
  if curves then
    local any = false
    for _, c in pairs(curves) do if c then any = true break end end
    if any then return M.curved(meridian, p, curves) end
  end
  return meridian
end

function M.outlineOf(meridian, f, p, opts)
  opts = opts or {}
  local smooth = opts.smooth
  if smooth == nil then smooth = softOf(meridian) end
  local fillMode = opts.fill or "auto"
  local rims = opts.rims or "all"
  local waist = opts.waist or 0.5
  local hole = opts.hole
  local maxR = 0
  for i = 1, #meridian do if meridian[i][2] > maxR then maxR = meridian[i][2] end end
  local n = opts.steps or M.stepsFor(maxR, 32, 160, M.scaleOf(p))
  local shape = shapeOf(meridian, p, smooth, opts.slope, opts.radius)
  local side = (fillMode == "auto" or fillMode == "surface") and sideOf(shape) or nil
  local surface = (side and not hole) and M.surfaceOf(side, f, p, rims, { slope = opts.slope }) or nil
  if surface and (fillMode == "surface" or surface.gap > waist) then
    return { fill = surface.fill, outline = surface.outline }
  end
  if fillMode == "hull" or fillMode == "auto" or fillMode == "surface" then
    local most = 0
    for i = 1, #shape do if shape[i][2] > most then most = shape[i][2] end end
    local around = math.min(320, math.max(n, math.ceil(TAU * most * M.scaleOf(p) / 1.5)))
    local tagged = {}
    for index = 1, #shape do
      local s, r = shape[index][1], shape[index][2]
      for j = 0, around - 1 do
        tagged[#tagged + 1] = { p = k.iso(M.pointOf(f, s, r, (j / around) * TAU), p), ring = index }
      end
    end
    local hull = hullTagged(tagged)
    local hullPath = {}
    for i = 1, #hull do hullPath[i] = hull[i].p end
    local holePath = ""
    if hole then
      local hp = {}
      for j = 0, around - 1 do hp[#hp + 1] = k.iso(M.pointOf(f, hole[1], hole[2], (j / around) * TAU), p) end
      holePath = k.pathOf(hp, true)
    end
    local fillPath = k.pathOf(hullPath, true) .. holePath
    if rims == "all" then return { fill = fillPath, outline = fillPath } end
    local keepFirst = rims == "first" or rims == "ends"
    local keepLast = rims == "last" or rims == "ends"
    local edges = {}
    for index = 1, #hull do
      local a = hull[index]
      local b = hull[index % #hull + 1]
      local same = a.ring == b.ring
      local keep = (not same) or (a.ring ~= 1 and a.ring ~= #shape) or (keepFirst and a.ring == 1) or (keepLast and a.ring == #shape)
      edges[#edges + 1] = { a.p, b.p, keep }
    end
    local parts = {}
    for _, pts in ipairs(chains(edges)) do parts[#parts + 1] = k.pathOf(pts) end
    return { fill = fillPath, outline = table.concat(parts) .. holePath }
  end
  return { fill = "", outline = "" }
end

-- lathe
function M.lathe(meridian, f, p, opts)
  opts = opts or {}
  local smooth = opts.smooth
  if smooth == nil then smooth = softOf(meridian) end
  local view, light = M.viewOf(p), M.lightOf(p)
  local aV, uV, vV = dot3(f.a, view), dot3(f.u, view), dot3(f.v, view)
  local aL, uL, vL = dot3(f.a, light), dot3(f.u, light), dot3(f.v, light)
  local maxR = 0
  for i = 1, #meridian do if meridian[i][2] > maxR then maxR = meridian[i][2] end end
  local n = opts.steps or M.stepsFor(maxR, 32, 160, M.scaleOf(p))
  local m = #meridian
  local rings = {}
  for i = 1, m do
    rings[i] = {}
    for j = 1, n do rings[i][j] = k.iso(M.pointOf(f, meridian[i][1], meridian[i][2], (j - 1) / n * TAU), p) end
  end
  local midC, midS = {}, {}
  for j = 1, n do
    local t = ((j - 0.5) / n) * TAU
    midC[j], midS[j] = math.cos(t), math.sin(t)
  end
  local seen, tones = {}, {}
  for i = 1, m - 1 do
    local ds, dr = meridian[i + 1][1] - meridian[i][1], meridian[i + 1][2] - meridian[i][2]
    local len = math.sqrt(ds * ds + dr * dr)
    seen[i], tones[i] = {}, {}
    for j = 1, n do
      if len < 1e-9 then seen[i][j] = false; tones[i][j] = 0
      else
        local facing = ds * (midC[j] * uV + midS[j] * vV) - dr * aV
        local lit = (ds * (midC[j] * uL + midS[j] * vL) - dr * aL) / len
        seen[i][j] = facing > 1e-6 * len
        tones[i][j] = M.bandOf(lit)
      end
    end
  end
  local buckets = { {}, {}, {}, {}, {} }
  if smooth then
    local smoothed = smoothRows(meridian, f, p, { steps = n })
    for tone = 0, 4 do
      for _, d in ipairs(smoothed[tone + 1]) do buckets[tone + 1][#buckets[tone + 1] + 1] = d end
    end
  end
  for i = 1, m - 1 do
    if not (smooth and math.abs(meridian[i + 1][1] - meridian[i][1]) > 1e-9) then
      local keys = {}
      for j = 1, n do keys[j] = seen[i][j] and tones[i][j] or nil end
      for _, g in ipairs(groupsOf(keys)) do
        local pts = {}
        for _, j in ipairs(g.run) do pts[#pts + 1] = rings[i][j] end
        for k2 = #g.run, 1, -1 do pts[#pts + 1] = rings[i + 1][g.run[k2]] end
        local d = k.pathOf(k.oriented(pts), true)
        buckets[g.key + 1][#buckets[g.key + 1] + 1] = d
      end
    end
  end
  -- creases + bevel
  local phi = math.atan2(vV, uV)
  local flatV = math.sqrt(uV * uV + vV * vV)
  local function rangeOf(i)
    local ds, dr = meridian[i + 1][1] - meridian[i][1], meridian[i + 1][2] - meridian[i][2]
    if math.sqrt(ds * ds + dr * dr) < 1e-9 then return nil end
    if math.abs(ds) < 1e-9 or flatV < 1e-9 then
      if -dr * aV > 1e-9 then return { -1, 1 } else return nil end
    end
    local c = (dr * aV) / (ds * flatV)
    if ds > 0 then return { math.max(-1, c), 1 } else return { -1, math.min(1, c) } end
  end
  local function arcsOf(ranges)
    for _, r in ipairs(ranges) do if not r then return {} end end
    local lo, hi = -math.huge, math.huge
    for _, r in ipairs(ranges) do lo = math.max(lo, r[1]); hi = math.min(hi, r[2]) end
    if lo >= hi - 1e-9 then return {} end
    local near = math.acos(math.min(1, hi))
    local far = math.acos(math.max(-1, lo))
    if hi >= 1 and lo <= -1 then return { { phi, phi + TAU } } end
    if hi >= 1 then return { { phi - far, phi + far } } end
    if lo <= -1 then return { { phi + near, phi + TAU - near } } end
    return { { phi + near, phi + far }, { phi - far, phi - near } }
  end
  local function along(s, r, span)
    local count = math.max(2, math.ceil((span[2] - span[1]) * math.max(r, 1e-6) * M.scaleOf(p) / 1.5))
    local out = {}
    for j = 0, count do out[j + 1] = k.iso(M.pointOf(f, s, r, span[1] + (span[2] - span[1]) * j / count), p) end
    return out
  end
  local crease = {}
  for i = 2, m - 1 do
    if not (meridian[i][3] and meridian[i][3] ~= 0) and meridian[i][2] > 1e-9 then
      for _, arc in ipairs(arcsOf({ rangeOf(i - 1), rangeOf(i) })) do
        crease[#crease + 1] = k.pathOf(along(meridian[i][1], meridian[i][2], arc))
      end
    end
  end
  local bevel = {}
  if (opts.bevel or 0) > 0 and m > 2 then
    local ends = {}
    if meridian[1][2] <= 1e-9 then ends[#ends + 1] = { 1, 2, 2 } end
    if meridian[m][2] <= 1e-9 then ends[#ends + 1] = { m - 1, m - 1, m - 2 } end
    for _, e in ipairs(ends) do
      local s, r = meridian[e[2]][1], meridian[e[2]][2]
      for _, arc in ipairs(arcsOf({ rangeOf(e[1]), rangeOf(e[3]) })) do
        local inset = along(s, math.max(0, r - opts.bevel), arc)
        local edge = along(s, r, arc)
        local pts = { edge[1] }
        for k2 = 2, #inset - 1 do pts[#pts + 1] = inset[k2] end
        pts[#pts + 1] = edge[#edge]
        bevel[#bevel + 1] = k.pathOf(pts)
      end
    end
  end
  local out = M.outlineOf(meridian, f, p, { steps = n, fill = opts.fill, hole = opts.hole, rims = opts.rims, smooth = smooth, waist = opts.waist })
  return {
    fill = out.fill,
    outline = out.outline,
    crease = table.concat(crease),
    top = table.concat(buckets[5]),
    shades = { table.concat(buckets[1]), table.concat(buckets[2]), table.concat(buckets[3]), table.concat(buckets[4]) },
    bevel = #bevel > 0 and table.concat(bevel) or nil,
  }
end

-- arcOf / circleOf
function M.arcOf(f, s, r, p, opts)
  opts = opts or {}
  local slope = opts.slope or 0
  local least = opts.least or 0.02
  local v = M.viewOf(p)
  local aV, uV, vV = dot3(f.a, v), dot3(f.u, v), dot3(f.v, v)
  local flat = math.sqrt(uV * uV + vV * vV)
  local phi = math.atan2(vV, uV)
  local norm = math.sqrt(1 + slope * slope)
  local visible
  if flat < 1e-9 then
    visible = (-slope * aV / norm > least) and { { phi, phi + TAU } } or {}
  else
    local c = (least * norm + slope * aV) / flat
    if c >= 1 then visible = {}
    elseif c <= -1 then visible = { { phi, phi + TAU } }
    else visible = { { phi - math.acos(c), phi + math.acos(c) } } end
  end
  local parts = {}
  for _, ab in ipairs(visible) do
    local count = math.max(2, math.ceil((ab[2] - ab[1]) / (TAU / (opts.steps or M.stepsFor(r, 24, 112)))))
    local pts = {}
    for j = 0, count do pts[j + 1] = k.iso(M.pointOf(f, s, r, ab[1] + (ab[2] - ab[1]) * j / count), p) end
    parts[#parts + 1] = k.pathOf(pts)
  end
  return table.concat(parts)
end

function M.circleOf(f, s, r, p, steps)
  local count = (steps and steps > 0) and steps or M.stepsFor(r, 24, 112)
  local pts = {}
  for j = 0, count - 1 do pts[j + 1] = k.iso(M.pointOf(f, s, r, j / count * TAU), p) end
  return k.pathOf(pts, true)
end

-- 常用封装
function M.sphereOf(centre, r, p, opts)
  opts = opts or {}
  local steps = opts.steps or 48
  local view, light = M.viewOf(p), M.lightOf(p)
  local f = M.frameAlong(centre, view)
  local rim = {}
  for i = 0, steps - 1 do rim[i + 1] = M.pointOf(f, 0, r, i / steps * TAU) end
  local function capOf(threshold)
    local points = {}
    for _, pt in ipairs(rim) do
      if dot3(sub3(pt, centre), light) / r >= threshold then points[#points + 1] = k.iso(pt, p) end
    end
    local lf = M.frameAlong(add3(centre, mul3(light, r * threshold)), light)
    local radius = r * math.sqrt(math.max(0, 1 - threshold * threshold))
    for i = 0, steps - 1 do
      local pt = M.pointOf(lf, 0, radius, i / steps * TAU)
      if dot3(sub3(pt, centre), view) >= -1e-9 then points[#points + 1] = k.iso(pt, p) end
    end
    if #points > 2 then return k.pathOf(k.convexHull(points), true) end
    return ""
  end
  local rimPts = {}
  for i = 1, #rim do rimPts[i] = k.iso(rim[i], p) end
  local outline = k.pathOf(rimPts, true)
  return { fill = outline, outline = outline, crease = "", top = "", shades = { outline, capOf(BANDS[2]), capOf(BANDS[3]), capOf(BANDS[4]) } }
end

function M.disc(s0, s1, r, f, p, opts)
  return M.lathe({ { s0, 0 }, { s0, r }, { s1, r }, { s1, 0 } }, f, p, opts)
end
function M.ringBand(s0, s1, rIn, rOut, f, p, opts)
  return M.lathe({ { s0, rIn }, { s0, rOut }, { s1, rOut }, { s1, rIn } }, f, p, opts)
end
function M.solidOf(profile, f, p, opts)
  local meridian = { { profile[1][1], 0 } }
  for i = 1, #profile do meridian[#meridian + 1] = profile[i] end
  meridian[#meridian + 1] = { profile[#profile][1], 0 }
  return M.lathe(meridian, f, p, opts)
end
function M.bandOfProfile(profile, f, p, opts) return M.lathe(profile, f, p, opts) end

-- prismOf / stadium / rodOut
function M.prismOf(f, polygon, s0, s1, p)
  local v, l = M.viewOf(p), M.lightOf(p)
  local ring = k.oriented(polygon)
  local n = #ring
  local function at(s, pt)
    return {
      f.o[1] + f.a[1] * s + f.u[1] * pt[1] + f.v[1] * pt[2],
      f.o[2] + f.a[2] * s + f.u[2] * pt[1] + f.v[2] * pt[2],
      f.o[3] + f.a[3] * s + f.u[3] * pt[1] + f.v[3] * pt[2],
    }
  end
  local low, high = {}, {}
  for i = 1, n do low[i] = k.iso(at(s0, ring[i]), p); high[i] = k.iso(at(s1, ring[i]), p) end
  local buckets = { {}, {}, {}, {}, {} }
  local seen = {}
  for j = 1, n do
    local x0, y0 = ring[j][1], ring[j][2]
    local x1, y1 = ring[j % n + 1][1], ring[j % n + 1][2]
    local normal = unit3(add3(mul3(f.u, y1 - y0), mul3(f.v, -(x1 - x0))))
    local visible = dot3(normal, v) > 1e-6
    seen[j] = visible
    if visible then
      local nx = j % n + 1
      buckets[M.bandOf(dot3(normal, l)) + 1][#buckets[M.bandOf(dot3(normal, l)) + 1] + 1] =
        k.pathOf({ low[j], low[nx], high[nx], high[j] }, true)
    end
  end
  local ends = { { s0, low, mul3(f.a, -1) }, { s1, high, f.a } }
  for _, e in ipairs(ends) do
    if dot3(e[3], v) > 1e-6 then
      buckets[M.bandOf(dot3(e[3], l)) + 1][#buckets[M.bandOf(dot3(e[3], l)) + 1] + 1] = k.pathOf(e[2], true)
    end
  end
  local both = {}
  for i = 1, #low do both[#both + 1] = low[i] end
  for i = 1, #high do both[#both + 1] = high[i] end
  local hull = k.convexHull(both)
  local crease = {}
  for j = 1, n do
    local prev = (j - 2) % n + 1
    local a = { ring[j][1] - ring[prev][1], ring[j][2] - ring[prev][2] }
    local b = { ring[j % n + 1][1] - ring[j][1], ring[j % n + 1][2] - ring[j][2] }
    local den = math.sqrt(a[1] * a[1] + a[2] * a[2]) * math.sqrt(b[1] * b[1] + b[2] * b[2])
    if den == 0 then den = 1 end
    if (a[1] * b[1] + a[2] * b[2]) / den < math.cos(0.35) and seen[j] and seen[prev] then
      crease[#crease + 1] = k.pathOf({ low[j], high[j] })
    end
  end
  local poly = k.pathOf(hull, true)
  return { fill = poly, outline = poly, crease = table.concat(crease), top = table.concat(buckets[5]),
    shades = { table.concat(buckets[1]), table.concat(buckets[2]), table.concat(buckets[3]), table.concat(buckets[4]) } }
end

function M.stadium(r0, r1, offset, steps)
  steps = steps or 32
  local pts = {}
  for i = 0, steps - 1 do
    local a = i / steps * TAU
    pts[#pts + 1] = { r0 * math.cos(a), r0 * math.sin(a) }
  end
  for i = 0, steps - 1 do
    local a = i / steps * TAU
    pts[#pts + 1] = { offset + r1 * math.cos(a), r1 * math.sin(a) }
  end
  return k.convexHull(pts)
end

function M.rodOut(f, from, to, r, p, opts)
  opts = opts or {}
  local stroke = opts.stroke or 0
  local pad = 0.35 / M.scaleOf(p)
  local function ringPts(s)
    local out = {}
    for i = 0, 47 do out[i + 1] = k.iso(M.pointOf(f, s, r + pad, i / 48 * TAU), p) end
    return out
  end
  local r1, r2 = ringPts(from), ringPts(to + stroke)
  local both = {}
  for i = 1, #r1 do both[#both + 1] = r1[i] end
  for i = 1, #r2 do both[#both + 1] = r2[i] end
  return { paths = M.disc(from - stroke, to, r, f, p, opts), clip = k.pathOf(k.convexHull(both), true),
    from = from, to = to, stroke = stroke, reach = to + stroke }
end

-- saddle
function M.saddleStart(r, a, angle) return math.sqrt(math.max(0, r * r - a * a * math.cos(angle) ^ 2)) end
function M.saddleOf(f, a, start, s1, p, opts)
  opts = opts or {}
  local v, l = M.viewOf(p), M.lightOf(p)
  local n = opts.steps or M.stepsFor(a, 24)
  local function ang(j) return (j / n) * TAU end
  local from
  if type(start) == "function" then from = start else from = function(t) return M.saddleStart(start, a, t) end end
  local low, high = {}, {}
  for j = 0, n - 1 do low[j + 1] = k.iso(M.pointOf(f, from(ang(j)), a, ang(j)), p) end
  for j = 0, n - 1 do high[j + 1] = k.iso(M.pointOf(f, s1, a, ang(j)), p) end
  local seen, tones = {}, {}
  for j = 0, n - 1 do
    local normal = M.radialOf(f, ang(j) + TAU / n / 2)
    seen[j + 1] = dot3(normal, v) > 1e-6
    tones[j + 1] = M.bandOf(dot3(normal, l))
  end
  local buckets = { {}, {}, {}, {}, {} }
  local fills = {}
  local keys = {}
  for j = 1, n do keys[j] = seen[j] and tones[j] or nil end
  for _, g in ipairs(groupsOf(keys)) do
    local pts = {}
    for _, j in ipairs(g.run) do pts[#pts + 1] = low[j] end
    for k2 = #g.run, 1, -1 do pts[#pts + 1] = high[g.run[k2]] end
    local d = k.pathOf(k.oriented(pts), true)
    buckets[g.key + 1][#buckets[g.key + 1] + 1] = d
    fills[#fills + 1] = d
  end
  local capSeen = dot3(f.a, v) > 1e-6
  if capSeen then
    local d = k.pathOf(k.oriented(high), true)
    buckets[M.bandOf(dot3(f.a, l)) + 1][#buckets[M.bandOf(dot3(f.a, l)) + 1] + 1] = d
    fills[#fills + 1] = d
  end
  local front = runsTrue(seen)
  local back = runsTrue((function() local o = {} for i = 1, #seen do o[i] = not seen[i] end return o end)())
  local edges = {}
  for _, run in ipairs(front) do
    local pts = {}
    for k2, j in ipairs(run) do pts[k2] = low[j] end
    edges[#edges + 1] = k.pathOf(pts)
    edges[#edges + 1] = k.pathOf({ low[run[1]], high[run[1]] })
    edges[#edges + 1] = k.pathOf({ low[run[#run]], high[run[#run]] })
  end
  for _, run in ipairs(capSeen and back or front) do
    local pts = {}
    for k2, j in ipairs(run) do pts[k2] = high[j] end
    edges[#edges + 1] = k.pathOf(pts)
  end
  local crease = {}
  if capSeen then
    for _, run in ipairs(front) do
      local pts = {}
      for k2, j in ipairs(run) do pts[k2] = high[j] end
      crease[#crease + 1] = k.pathOf(pts)
    end
  end
  return { fill = table.concat(fills), outline = table.concat(edges), crease = table.concat(crease),
    top = table.concat(buckets[5]),
    shades = { table.concat(buckets[1]), table.concat(buckets[2]), table.concat(buckets[3]), table.concat(buckets[4]) } }
end

-- ── profileCurve / bandsOf ──
function M.profileCurve(profile, opts)
  opts = opts or {}
  local slopeFn, radiusFn = opts.slope, opts.radius
  for index = 2, #profile do
    if profile[index][1] - profile[index - 1][1] <= 1e-9 then error("profileCurve: s must rise") end
  end
  local segments = curveRuns(profile)
  local s0, s1 = profile[1][1], profile[#profile][1]
  local function find(s)
    local lo, hi = 1, #profile - 1
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if profile[mid][1] <= s then lo = mid else hi = mid - 1 end
    end
    return lo
  end
  local function linear(index, s)
    local sa, ra = profile[index][1], profile[index][2]
    local sb, rb = profile[index + 1][1], profile[index + 1][2]
    return { ra + (rb - ra) * (s - sa) / (sb - sa), (rb - ra) / (sb - sa) }
  end
  local function radiusAt(s)
    if radiusFn then return radiusFn(s) end
    local at = math.max(s0, math.min(s1, s))
    local index = find(at)
    if segments[index] then return segments[index].radius(at) end
    return linear(index, at)[1]
  end
  local function slopeAt(s)
    if slopeFn then return slopeFn(s) end
    local at = math.max(s0, math.min(s1, s))
    local index = find(at)
    if segments[index] then return segments[index].slope(at) end
    return linear(index, at)[2]
  end
  return { s0 = s0, s1 = s1, radius = radiusAt, slope = slopeAt, analytic = (slopeFn ~= nil and radiusFn ~= nil) }
end

function M.bandsOf(profile, cuts, f, p, opts)
  opts = opts or {}
  local rows = opts.rows or 6
  local rims = opts.rims or "none"
  local fillMode = opts.fill or "auto"
  local curve = M.profileCurve(profile, { slope = opts.slope, radius = opts.radius })
  local s0, s1 = curve.s0, curve.s1
  local stopSet = {}
  local cuts2 = {}
  for _, s in ipairs(cuts) do if s > s0 + 1e-6 and s < s1 - 1e-6 and not stopSet[s] then stopSet[s] = true; cuts2[#cuts2 + 1] = s end end
  table.sort(cuts2)
  local stops = { s0 }
  for _, s in ipairs(cuts2) do stops[#stops + 1] = s end
  stops[#stops + 1] = s1
  local most = 0
  for i = 1, #profile do if profile[i][2] > most then most = profile[i][2] end end
  for _, s in ipairs(stops) do local r = curve.radius(s); if r > most then most = r end end
  local n = opts.steps or M.stepsFor(most, 32, 160, M.scaleOf(p))
  local function knot(s, soft) if soft then return { s, curve.radius(s), 1 } else return { s, curve.radius(s) } end end
  local function meridianOf(a, b)
    local mer = { knot(a) }
    for i = 1, #profile do
      local pt = profile[i]
      if pt[1] > a + 1e-9 and pt[1] < b - 1e-9 then mer[#mer + 1] = knot(pt[1], pt[3] and pt[3] ~= 0) end
    end
    mer[#mer + 1] = knot(b)
    return mer
  end
  local bands = {}
  for index = 1, #stops - 1 do
    local a, b = stops[index], stops[index + 1]
    local meridian = meridianOf(a, b)
    local paths = M.lathe(meridian, f, p, { steps = n, rims = rims, fill = fillMode, smooth = true })
    local seam = index < #stops - 1 and M.arcOf(f, b, curve.radius(b), p, { slope = curve.slope(b) }) or ""
    bands[#bands + 1] = { s0 = a, s1 = b, profile = meridian, paths = paths, outline = paths.outline, seam = seam }
  end
  return { bands = bands, radius = curve.radius, slope = curve.slope, steps = n, s0 = s0, s1 = s1 }
end

-- ── 路径工具 ──
function M.pathLength(points)
  local total = 0
  for i = 2, #points do total = total + len3(sub3(points[i], points[i - 1])) end
  return total
end
function M.resample(points, spacing)
  local lengths = { 0 }
  for i = 2, #points do lengths[i] = lengths[i - 1] + len3(sub3(points[i], points[i - 1])) end
  local total = lengths[#lengths]
  local count = math.max(1, math.floor(total / spacing + 0.5))
  local out, segment = {}, 2
  for step = 0, count do
    local at = total * step / count
    while segment < #points and lengths[segment] < at do segment = segment + 1 end
    local a, b = points[segment - 1], points[segment]
    local span = lengths[segment] - lengths[segment - 1]
    if span == 0 then span = 1 end
    out[#out + 1] = lerp3(a, b, math.max(0, math.min(1, (at - lengths[segment - 1]) / span)))
  end
  return out
end
function M.cut(points, from, to)
  local out, walked = {}, 0
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local length = len3(sub3(b, a))
    local start, fin = walked, walked + length
    if fin >= from and start <= to then
      local d = length == 0 and 1 or length
      local t0 = math.max(0, (from - start) / d)
      local t1 = math.min(1, (to - start) / d)
      if #out == 0 then out[#out + 1] = lerp3(a, b, t0) end
      out[#out + 1] = lerp3(a, b, t1)
    end
    walked = fin
  end
  return out
end
function M.pointAlong(points, at)
  local piece = M.cut(points, at, at + 0.01)
  return piece[1] or points[#points]
end
function M.tangentAlong(points, at)
  local total = M.pathLength(points)
  local a = M.pointAlong(points, math.max(0, at - 0.6))
  local b = M.pointAlong(points, math.min(total, at + 0.6))
  return unit3(sub3(b, a))
end
function M.fadeOf(value, range)
  local span = (range[2] - range[1]) == 0 and 1e-9 or (range[2] - range[1])
  local t = math.max(0, math.min(1, (value - range[1]) / span))
  return t * t * (3 - 2 * t)
end
function M.facingOf(f, angle, p, slope)
  slope = slope or 0
  local radial = M.radialOf(f, angle)
  return dot3(unit3({ radial[1] - slope * f.a[1], radial[2] - slope * f.a[2], radial[3] - slope * f.a[3] }), M.viewOf(p))
end

-- ribsOf / fillet / spiral / dots / spokes
function M.ribsOf(f, s0, s1, r, count, p, opts)
  opts = opts or {}
  local phase = opts.phase or 0
  local twist = opts.twist or 0
  local least = opts.least or 0.12
  local r1 = opts.r1 or r
  local fade = opts.fade
  local seams = opts.seams
  local v = M.viewOf(p)
  local lines = {}
  local slope = (r1 - r) / ((s1 - s0) == 0 and 1 or (s1 - s0))
  for index = 0, count - 1 do
    local t = phase + (index / count) * TAU
    local radial = M.radialOf(f, t + twist / 2)
    local normal = unit3({ radial[1] - slope * f.a[1], radial[2] - slope * f.a[2], radial[3] - slope * f.a[3] })
    local facing = dot3(normal, v)
    local d = k.pathOf({ k.iso(M.pointOf(f, s0, r, t), p), k.iso(M.pointOf(f, s1, r1, t + twist), p) })
    if fade then
      local alpha = M.fadeOf(facing, fade)
      if alpha > 0.02 then lines[#lines + 1] = { d = d, alpha = alpha } end
    elseif facing >= least then
      lines[#lines + 1] = d
    end
  end
  if seams then
    lines[#lines + 1] = M.arcOf(f, s0, r, p, { slope = slope })
    lines[#lines + 1] = M.arcOf(f, s1, r1, p, { slope = slope })
  end
  return lines
end

function M.fillet(points, radius, perArc, p, tube, margin)
  perArc = perArc or 7
  tube = tube or 0
  margin = margin or 1.3
  if #points < 3 then
    local out = {}
    for i = 1, #points do out[i] = { points[i][1], points[i][2], points[i][3] } end
    return out
  end
  local v = (p and tube > 0) and M.viewOf(p) or nil
  local out = { { points[1][1], points[1][2], points[1][3] } }
  for index = 2, #points - 1 do
    local prev, here, nxt = points[index - 1], points[index], points[index + 1]
    local into = unit3(sub3(here, prev))
    local outOf = unit3(sub3(nxt, here))
    local cosTurn = math.max(-1, math.min(1, dot3(into, outOf)))
    local turn = math.acos(cosTurn)
    if turn < 1e-3 then
      out[#out + 1] = { here[1], here[2], here[3] }
    else
      local room = math.min(len3(sub3(here, prev)), len3(sub3(nxt, here))) * 0.48
      local facing = v and math.abs(dot3(unit3(cross3(into, outOf)), v)) or 1
      local bend = v and math.max(radius, (margin * tube) / (0.7 * math.max(0.05, facing) ^ 2)) or radius
      local cutV = math.min(bend * math.tan(turn / 2), room)
      local a = sub3(here, mul3(into, cutV))
      local b = add3(here, mul3(outOf, cutV))
      local count = math.max(2, math.ceil(perArc * turn / (math.pi / 2)))
      for step = 0, count do
        local t = step / count
        out[#out + 1] = lerp3(lerp3(a, here, t), lerp3(here, b, t), t)
      end
    end
  end
  out[#out + 1] = { points[#points][1], points[#points][2], points[#points][3] }
  return out
end

function M.spiral(f, s, r0, r1, a0, a1, steps)
  steps = steps or 28
  local out = {}
  for index = 0, steps do
    local t = index / steps
    out[#out + 1] = M.pointOf(f, s, r0 + (r1 - r0) * t, a0 + (a1 - a0) * t)
  end
  return out
end

function M.dotsOf(f, s, r, count, p, opts)
  opts = opts or {}
  local phase = opts.phase or 0
  local slope = opts.slope or 0
  local least = opts.least or 0.08
  local all = opts.all
  local v = M.viewOf(p)
  local out = {}
  for index = 0, count - 1 do
    local t = phase + (index / count) * TAU
    if all then
      out[#out + 1] = k.iso(M.pointOf(f, s, r, t), p)
    else
      local radial = M.radialOf(f, t)
      local normal = unit3({ radial[1] - slope * f.a[1], radial[2] - slope * f.a[2], radial[3] - slope * f.a[3] })
      if dot3(normal, v) >= least then out[#out + 1] = k.iso(M.pointOf(f, s, r, t), p) end
    end
  end
  return out
end

function M.spokesOf(f, s, r0, r1, count, p, opts)
  opts = opts or {}
  local phase = opts.phase or 0
  local sweep = opts.sweep or 0
  local from = opts.from or 0
  local to = opts.to or TAU
  local lines = {}
  for index = 0, count - 1 do
    local t = phase + from + (index / count) * (to - from)
    lines[#lines + 1] = k.pathOf({ k.iso(M.pointOf(f, s, r0, t), p), k.iso(M.pointOf(f, s, r1, t + sweep), p) })
  end
  return table.concat(lines)
end

return M
