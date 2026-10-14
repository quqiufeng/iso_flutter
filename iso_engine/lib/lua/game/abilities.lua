-- abilities.lua —— 技能表：signature (world) -> ok?；加技能 = 加一个函数 + config.abilities 一行
local C = require("config")

local A = {}

-- 大招：全体敌方受创（AoE）
function A.ult(w)
  local cfg = C.abilities.ult
  for _, u in ipairs(w.units) do
    if u.side == "right" and u.hp > 0 then w:hit(u, cfg.dmg, nil) end
  end
  return true
end

-- 旋转挥刀：全体我方单位原地旋风斩，各自对周围敌方 AoE
function A.whirl(w)
  local cfg = C.abilities.whirl
  local any = false
  for _, u in ipairs(w.units) do
    if u.side == "left" and u.hp > 0 then
      any = true
      for _, o in ipairs(w.units) do
        if o.side == "right" and o.hp > 0
          and math.abs(o.x - u.x) <= cfg.range and math.abs(o.lane - u.lane) <= cfg.cross then
          w:hit(o, cfg.dmg, u)
        end
      end
    end
  end
  return any
end

return A
