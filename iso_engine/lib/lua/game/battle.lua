-- battle.lua —— 对推游戏（组装门面）
-- 逻辑内核： world.lua（世界 API + 系统）
-- 行为： behaviors.lua     武器： weapons.lua     技能： abilities.lua     数值： config.lua     实体： entity.lua
-- 用法（保持兼容）： local battle = require("battle"); local g = battle.new({cols=10, rows=8})
local World = require("world")
local C = require("config")

local M = {}
M.TYPES = C.units                 -- 兼容：兵种数值表（main/其它按 type 取 rate/name/hue…）
M.config = C
M.new = function(opts) return World.new(opts) end

return M
