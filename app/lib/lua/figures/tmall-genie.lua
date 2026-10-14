-- 天猫精灵 X1（Lua 版图定义）——返回 function(lift, time) -> 绘制指令 JSON
-- 用 iso_kit.lua 造零件；绘制交给 Flutter(Dart)。与 Dart 版 main.dart 的 genie 对应。
local k = require("iso_kit")

local W, H, FIGH = 560, 660, 560
local R, RB, BODY_TOP, TOP_Z, MAX_LIFT = 42, 46, 118, 124, 44

local function json(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
  elseif t == "number" then
    return string.format("%.6g", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    if #v > 0 then
      local parts = {}
      for i = 1, #v do parts[#parts + 1] = json(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for kk in pairs(v) do keys[#keys + 1] = kk end
    table.sort(keys)
    local parts = {}
    for _, kk in ipairs(keys) do parts[#parts + 1] = json(kk) .. ":" .. json(v[kk]) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function burst(age, attack, decay)
  if age < 0 then return 0 end
  if age < attack then return age / attack end
  return math.exp(-(age - attack) / decay)
end

return function(lift, time)
  local ly = MAX_LIFT * lift
  local function z(v) return v + ly end
  local ops = {}
  local function add(t) ops[#ops + 1] = t end
  local function solid(tone, s)
    add({ k = "solid", tone = tone, fill = s.fill, outline = s.outline, crease = s.crease, top = s.top, shades = s.shades, bevel = s.bevel })
  end
  local function line(tone, d, alpha) add({ k = "line", tone = tone, d = d, alpha = alpha or 1 }) end

  local P = k.fitProjection(k.boxCorners({ -RB, -RB, 2 * RB, 2 * RB, 0 }, -12, TOP_Z + MAX_LIFT + 6), W, FIGH, { pad = 36, azimuth = 45 })
  local flash = burst(math.max(0, time - 0.42), 0.08, 0.22) * 0.7 + lift * 0.5

  -- 光晕（软投影）
  add({ k = "halo", d = k.haloOf({ -RB, -RB, 2 * RB, 2 * RB, RB }, -12, 10, P), dy = 3 + 3 * lift, blur = 9 + 5 * lift, alpha = 1 - 0.3 * lift })
  -- 脚 / 机身
  solid("lo", k.cylinder(0, 0, RB, -10, 6, P, 56))
  solid("mid", k.cylinder(0, 0, RB - 3, -4, 6, P, 56))
  solid("hi", k.cylinder(0, 0, R, 0, BODY_TOP, P, 64, 1.0))
  line("lo", k.knurl(0, 0, R, 14, 76, 140, P, 0.25))
  line("lo", k.sideArc(0, 0, R, 14, P, 48))
  line("lo", k.sideArc(0, 0, R, 76, P, 48))
  line("faint", k.sideArc(0, 0, R, 92, P, 48))
  -- 顶部组件（随 lift 抬升 + 倾斜）
  local topC = k.iso({ 0, 0, z(TOP_Z) }, P)
  add({ k = "rotate", cx = topC[1], cy = topC[2], a = 0.11 * lift + 0.02 * math.sin(time * math.pi * 4) })
  solid("mid", k.cylinder(0, 0, R, z(BODY_TOP), 6, P, 64, 0.6))
  line("lo", k.ring(0, 0, R - 4, z(TOP_Z), P, 64))
  line((flash > 0.3 or lift > 0.5) and "lit" or "hi", k.ring(0, 0, 26, z(TOP_Z), P, 64))
  for kk = 0, 1 do
    local wv = (time * 0.9 + kk * 0.5) % 1
    line("faint", k.ring(0, 0, 14 + 34 * wv, z(TOP_Z), P, 64), (1 - wv) * (0.35 + 0.65 * lift))
  end
  for i = 0, 5 do
    local a = math.pi * 2 * i / 6
    local breathe = 0.5 + 0.5 * math.sin(time * math.pi * 4 - i * math.pi / 3)
    add({ k = "dots", tone = "hi", size = 0.9 + 0.6 * breathe, pts = { k.iso({ 24 * math.cos(a), 24 * math.sin(a), z(TOP_Z) }, P) } })
  end
  solid("lo", k.cylinder(0, 0, 7, z(TOP_Z), 2.4, P, 32))
  add({ k = "restore" })
  -- 中文标题
  add({ k = "text", text = "天猫精灵 X1 智能音箱", x = W / 2, y = H - 72, size = 27 })
  return json(ops)
end
