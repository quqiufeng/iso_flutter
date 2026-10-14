-- tube.lua —— anatomy/kit/tube.mjs 的 Lua(LuaJIT) 移植（核心）
-- 原项目：https://github.com/wheresryan22/anatomy (MIT)
local k = require("iso_kit")
local G = require("lathe")
local M = {}

local LIGHT = (function()
  local l = math.sqrt(0.55 * 0.55 + 0.835 * 0.835)
  return { -0.55 / l, -0.835 / l }
end)()

local function poly(points, closed) return k.pathOf(points, closed == nil and true or closed) end
local function area(points)
  local sum = 0
  local n = #points
  for i = 1, n do
    local nx, ny = points[i % n + 1][1], points[i % n + 1][2]
    sum = sum + points[i][1] * ny - nx * points[i][2]
  end
  return sum
end
local function sign(x) if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end end

local function sideOf(frames)
  local out = { left = {}, right = {}, shineA = {}, shineB = {}, shadeA = {}, shadeB = {} }
  for i = 1, #frames do
    local fr = frames[i]
    local p, nx, ny, half = fr.p, fr.nx, fr.ny, fr.half
    out.left[#out.left + 1] = { p[1] + nx * half, p[2] + ny * half }
    out.right[#out.right + 1] = { p[1] - nx * half, p[2] - ny * half }
    local toward = nx * LIGHT[1] + ny * LIGHT[2]
    local shineAt, shineHalf = half * 0.44 * toward, half * 0.24
    out.shineA[#out.shineA + 1] = { p[1] + nx * (shineAt + shineHalf), p[2] + ny * (shineAt + shineHalf) }
    out.shineB[#out.shineB + 1] = { p[1] + nx * (shineAt - shineHalf), p[2] + ny * (shineAt - shineHalf) }
    local shadeAt, shadeHalf = -half * 0.62 * toward, half * 0.2
    out.shadeA[#out.shadeA + 1] = { p[1] + nx * (shadeAt + shadeHalf), p[2] + ny * (shadeAt + shadeHalf) }
    out.shadeB[#out.shadeB + 1] = { p[1] + nx * (shadeAt - shadeHalf), p[2] + ny * (shadeAt - shadeHalf) }
  end
  return out
end

local function capOf(centre, tangent, radius, inward, p)
  local v = G.viewOf(p)
  local n1 = G.cross3(tangent, v)
  if G.len3(n1) < 1e-6 then n1 = G.frameAlong({ 0, 0, 0 }, tangent).u end
  n1 = G.unit3(n1)
  local n2 = G.unit3(G.cross3(tangent, n1))
  local steps = 28
  local ring = {}
  for index = 0, steps - 1 do
    local a = (index / steps) * math.pi * 2
    ring[#ring + 1] = k.iso(G.add3(centre, G.add3(G.mul3(n1, radius * math.cos(a)), G.mul3(n2, radius * math.sin(a)))), p)
  end
  local c = k.iso(centre, p)
  local probe = k.iso(G.add3(centre, n2), p)
  local along = (probe[1] - c[1]) * inward[1] + (probe[2] - c[2]) * inward[2]
  local from = along > 0 and steps / 2 or 0
  local function half(start)
    local o = {}
    for index = 0, steps / 2 do o[#o + 1] = ring[(start + index) % steps + 1] end
    return o
  end
  return { ring = ring, arc = half(from), inner = half((from + steps / 2) % steps) }
end

local function stripeEnd(half, centre, nx, ny, from, to)
  local function offset(pt) return (pt[1] - centre[1]) * nx + (pt[2] - centre[2]) * ny end
  local values = {}
  for i = 1, #half do values[i] = offset(half[i]) end
  local lo, hi = math.min(from, to), math.max(from, to)
  local points = {}
  for kk = 1, #half do
    if values[kk] >= lo and values[kk] <= hi then points[#points + 1] = half[kk] end
    if kk < #half then
      for _, level in ipairs({ lo, hi }) do
        if (values[kk] - level) * (values[kk + 1] - level) < 0 then
          local den = values[kk + 1] - values[kk]
          if den == 0 then den = 1e-9 end
          local t = (level - values[kk]) / den
          points[#points + 1] = { half[kk][1] + (half[kk + 1][1] - half[kk][1]) * t, half[kk][2] + (half[kk + 1][2] - half[kk][2]) * t }
        end
      end
    end
  end
  local pairs2 = {}
  for i = 1, #points do pairs2[i] = { points[i][1], points[i][2], offset(points[i]) } end
  table.sort(pairs2, function(x, y) if from > to then return y[3] < x[3] end return x[3] < y[3] end)
  local out = {}
  for i = 1, #pairs2 do out[i] = { pairs2[i][1], pairs2[i][2] } end
  return out
end

local function spansOf(total, gaps, breaks, maxLength, closed)
  local cuts = {}
  for _, ab in ipairs(gaps) do
    local a, b = math.max(0, math.min(ab[1], ab[2])), math.min(total, math.max(ab[1], ab[2]))
    if b - a > 1e-6 then cuts[#cuts + 1] = { a, b } end
  end
  table.sort(cuts, function(x, y) return x[1] < y[1] end)
  local runs, at = {}, 0
  for _, ab in ipairs(cuts) do
    if ab[1] > at + 1e-6 then runs[#runs + 1] = { at, ab[1], at > 0, true } end
    at = math.max(at, ab[2])
  end
  if total > at + 1e-6 then
    runs[#runs + 1] = { at, total, at > 0, (#cuts > 0 and cuts[#cuts][2] >= total - 1e-6) }
  end
  local pieces = {}
  for _, run in ipairs(runs) do
    local from0, to0, gapStart, gapEnd = run[1], run[2], run[3], run[4]
    local stops = { from0 }
    local brk = {}
    for _, b in ipairs(breaks) do if b > from0 + 1e-6 and b < to0 - 1e-6 then brk[#brk + 1] = b end end
    table.sort(brk)
    for _, b in ipairs(brk) do stops[#stops + 1] = b end
    stops[#stops + 1] = to0
    for index = 1, #stops - 1 do
      local a, b = stops[index], stops[index + 1]
      local count = math.max(1, math.ceil((b - a) / maxLength - 1e-9))
      for c = 0, count - 1 do
        pieces[#pieces + 1] = {
          from = a + (b - a) * c / count,
          to = a + (b - a) * (c + 1) / count,
          open0 = not (index == 1 and c == 0),
          open1 = not (index == #stops - 1 and c == count - 1),
          gap0 = index == 1 and c == 0 and gapStart,
          gap1 = index == #stops - 1 and c == count - 1 and gapEnd,
        }
      end
    end
  end
  if closed and #cuts == 0 and #pieces > 0 then
    pieces[1].open0 = true
    pieces[#pieces].open1 = true
  end
  return pieces
end

local function ringsOf(dense, total, radiusAt, p, span, opts)
  opts = opts or {}
  local pitch = opts.pitch or 3
  local twist = opts.twist or 0
  local fade = opts.fade or { 0.1, 0.55 }
  local steps = opts.steps or 16
  local v = G.viewOf(p)
  local lo, hi = span[1], span[2]
  local margin = twist ~= 0 and 0 or math.min(pitch * 0.35, (hi - lo) / 2)
  local from = math.max(lo, margin)
  local to = math.min(hi, margin ~= 0 and hi - margin or hi)
  if to <= from then return {} end
  local out = {}
  local hands = twist ~= 0 and { 1 } or { 0 }
  local maxr = 0
  for _, t in ipairs({ 0, 0.5, 1 }) do local r = radiusAt(t); if r > maxr then maxr = r end end
  local reach = math.abs(twist) * maxr
  local first = math.ceil((from - reach) / pitch)
  local last = math.floor((to + reach) / pitch)
  local function surface(t, theta)
    local at = math.max(0, math.min(total, t))
    local c = G.pointAlong(dense, at)
    local T = G.tangentAlong(dense, at)
    local n1 = G.cross3(T, v)
    if G.len3(n1) < 1e-6 then return nil end
    n1 = G.unit3(n1)
    local n2 = G.unit3(G.cross3(T, n1))
    if G.dot3(n2, v) < 0 then n2 = G.mul3(n2, -1) end
    local r = radiusAt(at / (total == 0 and 1 or total))
    local normal = G.add3(G.mul3(n1, math.cos(theta)), G.mul3(n2, math.sin(theta)))
    return { p = k.iso(G.add3(c, G.mul3(normal, r)), p), facing = G.dot3(normal, v), r = r }
  end
  for index = first, last do
    local station = index * pitch
    for _, hand in ipairs(hands) do
      local samples = {}
      for step = 0, steps do
        local theta = (step / steps) * math.pi
        local t = station + hand * twist * radiusAt(math.max(0, math.min(1, station / (total == 0 and 1 or total)))) * (step / steps - 0.5)
        samples[#samples + 1] = { t, theta }
      end
      for step = 1, steps do
        local a, b = samples[step], samples[step + 1]
        if not ((a[1] < from and b[1] < from) or (a[1] > to and b[1] > to)) then
          local function clipTo(x, y, edge)
            local den = y[1] - x[1]
            if den == 0 then den = 1e-9 end
            return { edge, x[2] + ((y[2] - x[2]) * (edge - x[1])) / den }
          end
          if a[1] < from then a = clipTo(a, b, from) end
          if b[1] < from then b = clipTo(b, a, from) end
          if a[1] > to then a = clipTo(a, b, to) end
          if b[1] > to then b = clipTo(b, a, to) end
          local pa, pb = surface(a[1], a[2]), surface(b[1], b[2])
          if pa and pb then
            local alpha = fade and G.fadeOf((pa.facing + pb.facing) / 2, fade) or 1
            if alpha > 0.02 then out[#out + 1] = { d = k.pathOf({ pa.p, pb.p }), alpha = alpha } end
          end
        end
      end
    end
  end
  return out
end

function M.tubePieces(points3, radiusAt, p, opts)
  opts = opts or {}
  local maxLength = opts.maxLength or 30
  local spacing = opts.spacing or 2.2
  local closed = opts.closed or false
  local breaks = opts.breaks or {}
  local gaps = opts.gaps or {}
  local caps = opts.caps
  if caps == nil then caps = true end
  local stripes = opts.stripes
  if stripes == nil then stripes = "auto" end
  local rings = opts.rings
  local pitch = opts.pitch or 3
  local twist = opts.twist or 0
  local fade = opts.fade or { 0.1, 0.55 }
  local ringTone = opts.ringTone or "lo"
  if type(radiusAt) == "number" then local r = radiusAt; radiusAt = function() return r end end

  local dense = G.resample(points3, spacing)
  local total = G.pathLength(dense)
  local kk = G.scaleOf(p)
  local wide
  if stripes == "auto" then
    local m = 0
    for i = 0, 32 do local r = radiusAt(i / 32); if r > m then m = r end end
    wide = m * kk > 1.3
  else
    wide = stripes and true or false
  end
  local lead = 0.5
  local out = {}
  local looped = closed and #gaps == 0
  local function wrap(at)
    if looped then return ((at % total) + total) % total end
    return math.max(0, math.min(total, at))
  end
  local step = math.max(0.05, math.min(spacing, total / 4) * 0.5)
  local function frameAt(at, pt, width)
    local a = k.iso(G.pointAlong(dense, wrap(at - step)), p)
    local b = k.iso(G.pointAlong(dense, wrap(at + step)), p)
    local tx, ty = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(tx * tx + ty * ty)
    if len == 0 then tx, ty = 0, 0 else tx, ty = tx / len, ty / len end
    return { p = pt, nx = -ty, ny = tx, half = width }
  end
  local function partOf(start, fin)
    local points = G.cut(dense, math.max(0, start), math.min(total, fin))
    if looped and start < 0 then
      local head = G.cut(dense, total + start, total)
      local merged = {}
      for _, pt in ipairs(head) do merged[#merged + 1] = pt end
      for i = 2, #points do merged[#merged + 1] = points[i] end
      points = merged
    end
    if looped and fin > total then
      local tail = G.cut(dense, 0, fin - total)
      for i = 2, #tail do points[#points + 1] = tail[i] end
    end
    local walked = looped and start or math.max(0, start)
    local along = {}
    for index = 1, #points do
      if index > 1 then walked = walked + G.len3(G.sub3(points[index], points[index - 1])) end
      along[index] = walked
    end
    local flat, widths, frames = {}, {}, {}
    for index = 1, #points do
      flat[index] = k.iso(points[index], p)
      local t = looped and wrap(along[index]) / total or math.min(1, math.max(0, along[index] / total))
      widths[index] = radiusAt(t) * kk
      frames[index] = frameAt(along[index], flat[index], widths[index])
    end
    return { points = points, flat = flat, widths = widths, frames = frames }
  end
  for _, piece in ipairs(spansOf(total, gaps, breaks, maxLength, closed)) do
    local openStart = piece.open0 and (piece.from > 0 or looped)
    local openEnd = piece.open1 and (piece.to < total or looped)
    local body = partOf(openStart and piece.from - lead or piece.from, openEnd and piece.to + lead or piece.to)
    if #body.points >= 2 then
      local stripe = (openStart or openEnd)
        and partOf(openStart and piece.from - 2 * lead or piece.from, openEnd and piece.to + 2 * lead or piece.to)
        or body
      local sides = sideOf(body.frames)
      local bands = (stripe == body) and sides or sideOf(stripe.frames)
      local bodyPts = {}
      for _, pt in ipairs(sides.left) do bodyPts[#bodyPts + 1] = pt end
      for i = #sides.right, 1, -1 do bodyPts[#bodyPts + 1] = sides.right[i] end
      local bodyPath = poly(bodyPts)
      local edges = k.pathOf(sides.left) .. k.pathOf(sides.right)
      local ends = {
        not piece.open0 and not looped and (piece.from <= 1e-6 or piece.gap0),
        not piece.open1 and not looped and (piece.to >= total - 1e-6 or piece.gap1),
      }
      local capped = { ends[1] and (piece.gap0 or caps), ends[2] and (piece.gap1 or caps) }
      local sgn = sign(area(bodyPts))
      local tips = { nil, nil }
      for side = 0, 1 do
        if capped[side + 1] then
          local at = side == 1 and #body.points or 1
          local other = side == 1 and #body.points - 1 or 2
          local tangent = G.unit3(G.sub3(body.points[side == 1 and at or other], body.points[side == 1 and other or at]))
          local outward = side == 1 and tangent or G.mul3(tangent, -1)
          local inward = { body.flat[other][1] - body.flat[at][1], body.flat[other][2] - body.flat[at][2] }
          local cap = capOf(body.points[at], tangent, body.widths[at] / kk, inward, p)
          local orientedRing = sign(area(cap.ring)) == sgn and cap.ring or (function() local r = {} for i = #cap.ring, 1, -1 do r[#r + 1] = cap.ring[i] end return r end)()
          bodyPath = bodyPath .. poly(orientedRing)
          edges = edges .. k.pathOf(cap.arc)
          local open = G.dot3(outward, G.viewOf(p)) > 0
          if open then edges = edges .. k.pathOf(cap.inner) end
          tips[side + 1] = { open and cap.inner or cap.arc, body.frames[at] }
        end
      end
      local function bandF(a, b, offsets)
        local head, tail = {}, {}
        if tips[2] then
          local fr = tips[2][2]
          local off = offsets(fr)
          head = stripeEnd(tips[2][1], fr.p, fr.nx, fr.ny, off[1], off[2])
        end
        if tips[1] then
          local fr = tips[1][2]
          local off = offsets(fr)
          tail = stripeEnd(tips[1][1], fr.p, fr.nx, fr.ny, off[2], off[1])
        end
        local pts = {}
        for _, pt in ipairs(a) do pts[#pts + 1] = pt end
        for _, pt in ipairs(head) do pts[#pts + 1] = pt end
        for i = #b, 1, -1 do pts[#pts + 1] = b[i] end
        for _, pt in ipairs(tail) do pts[#pts + 1] = pt end
        return poly(pts)
      end
      local function toward(fr) return fr.nx * LIGHT[1] + fr.ny * LIGHT[2] end
      local function shineOffsets(fr) return { fr.half * 0.44 * toward(fr) + fr.half * 0.24, fr.half * 0.44 * toward(fr) - fr.half * 0.24 } end
      local function shadeOffsets(fr) return { -fr.half * 0.62 * toward(fr) + fr.half * 0.2, -fr.half * 0.62 * toward(fr) - fr.half * 0.2 } end
      out[#out + 1] = {
        rings = rings and ringsOf(dense, total, radiusAt, p, { piece.from, piece.to }, { pitch = pitch, twist = twist, fade = fade }) or {},
        ringTone = ringTone,
        mid = G.pointAlong(dense, (piece.from + piece.to) / 2),
        body = bodyPath,
        shine = bandF(bands.shineA, bands.shineB, shineOffsets),
        shade = bandF(bands.shadeA, bands.shadeB, shadeOffsets),
        edges = edges,
        wide = wide,
        points = body.points,
        radii = (function() local o = {} for i = 1, #body.widths do o[i] = body.widths[i] / kk end return o end)(),
        ends = ends,
        from = piece.from,
        to = piece.to,
      }
    end
  end
  return out
end

return M
