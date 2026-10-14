-- 对拍：Lua 引擎算同一张图（对应 tool/kit_parity.dart）
local k = require("iso_kit")
local L = require("lathe")

local p = k.fitProjection(k.boxCorners({ -80, -80, 160, 160, 0 }, -10, 170), 560, 560, { pad = 40, azimuth = 45 })
local fv = L.frameAlong({ -45, -45, 0 }, { 0, 0, 1 })
local mer = { { 0, 0 }, { 0, 60, 1 }, { 14, 70, 1 }, { 46, 70, 1 }, { 60, 60, 1 }, { 60, 0 } }
local s = L.lathe(mer, fv, p, { bevel = 0.8 })
print("FILL=" .. s.fill)
print("LEN=" .. #s.fill .. " SHADES=" .. #s.shades[1] .. "," .. #s.shades[2] .. "," .. #s.shades[3] .. "," .. #s.shades[4] .. " OUTLINE=" .. #s.outline)
local c = k.cylinder(0, 0, 42, 0, 118, p, 64, 1.0)
print("CYL=" .. #c.fill .. " TOP=" .. #c.top)
