-- rigarcher —— 用 AI 生成角色切出的分件做骨骼动画。运行：love example/rig-archer
local root = os.getenv("HOME") .. "/iso_flutter"
package.path = root .. "/iso_engine/lib/lua/?.lua;" .. package.path
local rig = require("rig")

local PARTS = os.getenv("RIG_PARTS") or (root .. "/example/rig-archer/parts")
local function loadImg(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close()
  return love.graphics.newImage(love.filesystem.newFileData(d, "p.png"))
end
local function att(file, w, h, px, py)
  local img = loadImg(PARTS .. "/" .. file)
  if img then img:setFilter("linear", "linear") end
  return { img = img, w = w, h = h, pivotX = px, pivotY = py }
end

-- 该角色切件坐标（来自 cutparts.sh 的 parts.json，bbox 660x977；y 向下）
local def = {
  bones = {
    { name = "root" },
    { name = "spine", parent = "root",  x = 0,     y = -294 },  -- 髋
    { name = "chest", parent = "spine", x = 0,     y = -371 },  -- 颈
    { name = "head",  parent = "chest", x = 0,     y = 0 },
    { name = "armL",  parent = "chest", x = -132,  y = 127 },
    { name = "armR",  parent = "chest", x = 132,   y = 127 },
    { name = "legL",  parent = "spine", x = -72.5, y = 0 },
    { name = "legR",  parent = "spine", x = 72.5,  y = 0 },
  },
  slots = {
    { name = "armL",  bone = "armL",  order = 1, att = att("armL.png",  198, 136, 198, 68) },
    { name = "legL",  bone = "legL",  order = 2, att = att("legL.png",  145, 294, 72,  0) },
    { name = "legR",  bone = "legR",  order = 3, att = att("legR.png",  145, 294, 72,  0) },
    { name = "torso", bone = "spine", order = 4, att = att("torso.png", 290, 371, 145, 371) },
    { name = "head",  bone = "head",  order = 5, att = att("head.png",  316, 312, 158, 312) },
    { name = "armR",  bone = "armR",  order = 6, att = att("armR.png",  198, 136, 0,   68) },
  },
  clips = {
    idle = {
      duration = 2.2, loop = true,
      bones = {
        spine = { { t = 0, y = -294 }, { t = 1.1, y = -300, ease = "inout" }, { t = 2.2, y = -294, ease = "inout" } },
        head  = { { t = 0, rot = 0.02 }, { t = 1.1, rot = -0.04, ease = "inout" }, { t = 2.2, rot = 0.02, ease = "inout" } },
        armL  = { { t = 0, rot = 0.06 }, { t = 1.1, rot = 0.12, ease = "inout" }, { t = 2.2, rot = 0.06, ease = "inout" } },
        armR  = { { t = 0, rot = -0.06 }, { t = 1.1, rot = -0.12, ease = "inout" }, { t = 2.2, rot = -0.06, ease = "inout" } },
      },
    },
    walk = {
      duration = 0.7, loop = true,
      bones = {
        spine = { { t = 0, y = -294 }, { t = 0.175, y = -302, ease = "out" }, { t = 0.35, y = -294, ease = "in_" },
                  { t = 0.525, y = -302, ease = "out" }, { t = 0.7, y = -294, ease = "in_" } },
        chest = { { t = 0, rot = 0.04 }, { t = 0.35, rot = -0.04 }, { t = 0.7, rot = 0.04 } },
        head  = { { t = 0, rot = -0.03 }, { t = 0.35, rot = 0.03 }, { t = 0.7, rot = -0.03 } },
        armL  = { { t = 0, rot = -0.5 }, { t = 0.35, rot = 0.5 }, { t = 0.7, rot = -0.5 } },
        armR  = { { t = 0, rot = 0.5 }, { t = 0.35, rot = -0.5 }, { t = 0.7, rot = 0.5 } },
        legL  = { { t = 0, rot = 0.16, y = 0 }, { t = 0.175, rot = -0.05, y = -14, ease = "out" },
                  { t = 0.35, rot = -0.16, y = 0 }, { t = 0.7, rot = 0.16, y = 0 } },
        legR  = { { t = 0, rot = -0.16, y = 0 }, { t = 0.525, rot = 0.05, y = -14, ease = "out" },
                  { t = 0.7, rot = -0.16, y = 0 } },
      },
    },
  },
}

local R = rig.new(def)
local W, H = 720, 420
local SHOTS = { { "idle", 0 }, { "idle", 0.5 }, { "walk", 0 }, { "walk", 0.175 }, { "walk", 0.35 }, { "walk", 0.525 } }

local function renderStrip(path)
  local canvas = love.graphics.newCanvas(W, H)
  love.graphics.setCanvas(canvas); love.graphics.clear(0.94, 0.94, 0.90)
  for i, sh in ipairs(SHOTS) do
    R:setClip(sh[1], { time = sh[2] }); R:_apply()
    R:draw(50 + (i - 1) % 6 * 118, 380, 0.30, false)
    love.graphics.setColor(0, 0, 0); love.graphics.print(sh[1] .. " " .. sh[2], 50 + (i - 1) % 6 * 118 - 24, 396); love.graphics.setColor(1, 1, 1)
  end
  love.graphics.setCanvas()
  local fd = canvas:newImageData():encode("png")
  local f = io.open(path, "wb"); f:write(fd:getString()); f:close()
end

function love.load()
  if os.getenv("RIG_EXPORT") then renderStrip(os.getenv("RIG_EXPORT")); love.event.quit()
  else R:setClip("walk"); love.graphics.setBackgroundColor(0.94, 0.94, 0.90) end
end
function love.update(dt) if not os.getenv("RIG_EXPORT") then R:update(dt) end end
function love.keypressed(k) if k == "1" then R:setClip("idle") elseif k == "2" then R:setClip("walk") end end
function love.draw()
  if os.getenv("RIG_EXPORT") then return end
  R:draw(W/2 - 90, H - 20, 0.32, false); R:draw(W/2 + 90, H - 20, 0.32, true)
  love.graphics.print("1=idle  2=walk", 16, 16)
end
