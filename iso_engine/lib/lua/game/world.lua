-- 世界（地图）：地面范围 + 物件 + 目标。纯数据，无依赖。
local M = {}

function M.new()
  return {
    size = 40,               -- 地面 [-size, size]^2
    speed = 9,               -- 玩家速度（世界单位/秒）
    player = { x = 0, y = 0, r = 2.5 },
    props = {                -- 圆形物件（障碍 + 可拾取）
      { x = 6,  y = -4, r = 3,   kind = "tree" },
      { x = -7, y = 5,  r = 3,   kind = "box" },
      { x = 0,  y = 9,  r = 2.5, kind = "mushroom" },
      { x = -5, y = -8, r = 3,   kind = "tree" },
      { x = 12, y = -6, r = 3,   kind = "box" },
    },
    goal = { x = 14, y = 14, r = 3 },   -- 到达即胜
    -- 其他"动态角色"（NPC）：巡游（在路点间来回）；可被暂停（主角除外）
    npcs = {
      { x = -12, y = 0,  r = 2.2, kind = "guard", speed = 5, wp = { { x = -12, y = 0 },  { x = 12, y = 0 } } },
      { x = 0,   y = -12, r = 2.2, kind = "drone", speed = 7, wp = { { x = 0, y = -12 }, { x = 0, y = 12 } } },
    },
  }
end

return M
