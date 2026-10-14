-- weapons.lua —— 命中效果表：signature (u, target, world)；加武器 = 加一个函数
local W = {}

W.melee  = function(u, t, w) w:hit(t, u.stats.atk, u) end
W.arrow  = function(u, t, w) w:hit(t, u.stats.atk, u) end
W.heavy  = function(u, t, w) w:hit(t, u.stats.atk, u) end

-- 溅射：命中目标 + 目标同侧邻近单位（半伤）
W.splash = function(u, t, w)
  w:hit(t, u.stats.atk, u)
  for _, o in ipairs(w:alliesNear(t, 1.5, t.lane)) do
    w:hit(o, u.stats.atk * 0.5, u)
  end
end

return W
