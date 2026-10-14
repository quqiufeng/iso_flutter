-- rig-demo —— 骨骼系统演示（色块占位件）。运行：love example/rig-demo
-- 自动把 6 个姿态渲染到 /tmp/opencode/rig_out.png 后退出；也可去掉 quit 当窗口 demo 看。
local root = os.getenv("HOME") .. "/iso_flutter"
package.path = root .. "/iso_engine/lib/lua/?.lua;" .. package.path
local rig = require("rig")

local white
local function part(w, h) return { img = white, w = w, h = h } end

local def = {
  bones = {
    { name = "root" },
    { name = "hip",   parent = "root",  y = -46 },
    { name = "torso", parent = "hip",   y = -6 },
    { name = "head",  parent = "torso", y = -30 },
    { name = "armL",  parent = "torso", x = -11, y = 2 },
    { name = "armR",  parent = "torso", x = 11,  y = 2 },
    { name = "legL",  parent = "hip",   x = -7 },
    { name = "legR",  parent = "hip",   x = 7 },
  },
  slots = {
    { name = "armL",  bone = "armL",  order = 1, att = part(9, 30),  color = { 0.20, 0.28, 0.55 } },
    { name = "legL",  bone = "legL",  order = 2, att = part(11, 40), color = { 0.15, 0.15, 0.22 } },
    { name = "torso", bone = "torso", order = 3, att = part(26, 36), color = { 0.85, 0.30, 0.28 } },
    { name = "head",  bone = "head",  order = 4, att = part(26, 26), color = { 0.95, 0.80, 0.68 } },
    { name = "legR",  bone = "legR",  order = 5, att = part(11, 40), color = { 0.18, 0.18, 0.26 } },
    { name = "armR",  bone = "armR",  order = 6, att = part(9, 30),  color = { 0.24, 0.34, 0.65 } },
  },
  clips = {
    idle = {
      duration = 2, loop = true,
      bones = {
        torso = { { t = 0, y = -6 }, { t = 1, y = -7.5, ease = "inout" }, { t = 2, y = -6, ease = "inout" } },
        head  = { { t = 0, rot = 0.02 }, { t = 1, rot = -0.03, ease = "inout" }, { t = 2, rot = 0.02, ease = "inout" } },
        armL  = { { t = 0, rot = 0.15 }, { t = 1, rot = 0.05, ease = "inout" }, { t = 2, rot = 0.15, ease = "inout" } },
        armR  = { { t = 0, rot = -0.15 }, { t = 1, rot = -0.05, ease = "inout" }, { t = 2, rot = -0.15, ease = "inout" } },
      },
    },
    walk = {
      duration = 0.8, loop = true,
      bones = {
        legL = { { t = 0, rot = 0.5 }, { t = 0.4, rot = -0.5 }, { t = 0.8, rot = 0.5 } },
        legR = { { t = 0, rot = -0.5 }, { t = 0.4, rot = 0.5 }, { t = 0.8, rot = -0.5 } },
        armL = { { t = 0, rot = -0.45 }, { t = 0.4, rot = 0.45 }, { t = 0.8, rot = -0.45 } },
        armR = { { t = 0, rot = 0.45 }, { t = 0.4, rot = -0.45 }, { t = 0.8, rot = 0.45 } },
        hip  = { { t = 0, y = -46 }, { t = 0.2, y = -43, ease = "out" }, { t = 0.4, y = -46, ease = "in_" },
                 { t = 0.6, y = -43, ease = "out" }, { t = 0.8, y = -46, ease = "in_" } },
      },
    },
  },
}

local R = rig.new(def)
local W, H = 640, 360
local SHOTS = { { "idle", 0 }, { "idle", 0.5 }, { "walk", 0 }, { "walk", 0.2 }, { "walk", 0.4 }, { "walk", 0.6 } }

function love.load()
  local id = love.image.newImageData(8, 8); id:mapPixel(function() return 1, 1, 1, 1 end)
  white = love.graphics.newImage(id)
  for _, s in ipairs(def.slots) do s.att.img = white end
  if os.getenv("RIG_EXPORT") then
    local canvas = love.graphics.newCanvas(W, H)
    love.graphics.setCanvas(canvas); love.graphics.clear(0.93, 0.93, 0.90)
    for i, sh in ipairs(SHOTS) do
      R:setClip(sh[1], { time = sh[2] }); R:_apply()
      R:draw(60 + (i - 1) % 6 * 100, 300, 1.6, false)
      love.graphics.setColor(0, 0, 0); love.graphics.print(sh[1] .. " t=" .. sh[2], 60 + (i - 1) % 6 * 100 - 30, 320); love.graphics.setColor(1, 1, 1)
    end
    love.graphics.setCanvas()
    local fd = canvas:newImageData():encode("png")
    local f = io.open(os.getenv("RIG_EXPORT"), "wb"); f:write(fd:getString()); f:close()
    love.event.quit()
  else
    R:setClip("walk")
    love.graphics.setBackgroundColor(0.93, 0.93, 0.90)
  end
end

function love.update(dt) if not os.getenv("RIG_EXPORT") then R:update(dt) end end
function love.keypressed(k) if k == "1" then R:setClip("idle") elseif k == "2" then R:setClip("walk") end end
function love.draw()
  if os.getenv("RIG_EXPORT") then return end
  R:draw(200, 260, 2.0, false); R:draw(420, 260, 2.0, true)
  love.graphics.print("1=idle  2=walk", 20, 20)
end
