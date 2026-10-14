-- config.lua —— 对推游戏**纯数值/数据**（加兵种/改数值只动这里，不碰逻辑）
-- 单位字段：hp/atk/range(格)/speed(格/秒)/rate(攻击间隔秒)/cost；ai=行为名；weapon=武器名；hue 供上色
local C = {}

C.rows, C.cols = 5, 10
C.baseHp = 100
C.resourceStart = 120
C.resourceRegen = 13          -- 每秒
C.resourceCap = 300
C.killReward = 12             -- 击杀敌方单位回资源

C.units = {
  -- 我方（左，防守/布防）
  sword  = { name = "剑士",   side = "left",  hp = 70,  atk = 12, range = 1.2, speed = 1.7, cost = 30, rate = 0.8, weapon = "melee",  ai = "rush",   hue = 200 },
  archer = { name = "弓手",   side = "left",  hp = 40,  atk = 10, range = 4.5, speed = 1.2, cost = 45, rate = 1.0, weapon = "arrow",  ai = "ranged", hue = 140 },
  mage   = { name = "法师",   side = "left",  hp = 45,  atk = 18, range = 3.5, speed = 1.1, cost = 70, rate = 1.4, weapon = "splash", ai = "ranged", hue = 280 },
  -- 敌方（右，进攻）
  goblin = { name = "哥布林", side = "right", hp = 55,  atk = 10, range = 1.0, speed = 1.9, cost = 0,  rate = 0.7, weapon = "melee",  ai = "rush",   hue = 20 },
  shooter= { name = "弩手",   side = "right", hp = 38,  atk = 11, range = 4.0, speed = 1.3, cost = 0,  rate = 1.1, weapon = "arrow",  ai = "ranged", hue = 340 },
  ogre   = { name = "食人魔", side = "right", hp = 160, atk = 18, range = 1.3, speed = 1.3, cost = 0,  rate = 1.0, weapon = "heavy",  ai = "rush",   hue = 0 },
}

-- 技能（冷却 + 数值）
C.abilities = {
  ult   = { cd = 14, dmg = 55 },                    -- 全体敌方受创
  whirl = { cd = 6,  dmg = 40, range = 2.5, cross = 1.5 },  -- 我方旋风斩：周围 AoE
}

-- 敌方波次（数据驱动；改这里即可调难度曲线）
function C.enemyWave(wave, rows)
  local pool = { "goblin", "goblin", "shooter" }
  if wave > 2 then pool[#pool + 1] = "ogre" end
  local n = 1 + math.floor(wave / 4)
  local out = {}
  for i = 1, n do
    out[#out + 1] = { type = pool[((wave + i) % #pool) + 1], lane = (wave + i) % rows }
  end
  return out
end
function C.waveInterval(wave) return math.max(2.4, 4.2 - wave * 0.08) end

return C
