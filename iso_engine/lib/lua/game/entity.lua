-- entity.lua —— 实体（只是数据）：位置 / 血量 / 阵营 / 数值引用 / 状态标记
-- 行为、武器、技能都作用于"实体 + 世界"，实体自身不含逻辑。
local C = require("config")

local E = {}

-- side: "left"|"right"；type: config.units 的键；lane: 行(0-based)；x: 列位置
function E.new(side, type, lane, x)
  local s = C.units[type]
  return {
    side = side, type = type, stats = s,
    lane = lane, x = x,
    hp = s.hp, max = s.hp, cd = 0,
    moving = false, attacking = false,
    state = "advance",          -- advance | engage（供扩展/渲染）
  }
end

return E
