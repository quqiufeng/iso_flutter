-- behaviors.lua —— 行为(AI)策略表：统一签名 (u, w, dt)，只通过 world API 交互
-- 加新行为 = 加一个函数；config 里 ai 字段引用它。
local B = {}

-- 公共：射程内有敌就交战，否则按 advance 决定是否推进
local function engageOrAdvance(u, w, dt, advance)
  local e = w:nearestEnemy(u, u.stats.range)
  if e then
    w:engage(u, e, dt)
  elseif advance then
    w:advance(u, dt)
  end
end

B.rush   = function(u, w, dt) engageOrAdvance(u, w, dt, true)  end  -- 推进，遇敌停
B.ranged = function(u, w, dt) engageOrAdvance(u, w, dt, true)  end  -- 同上（区别在射程/武器）
B.guard  = function(u, w, dt) engageOrAdvance(u, w, dt, false) end  -- 守线不越

return B
