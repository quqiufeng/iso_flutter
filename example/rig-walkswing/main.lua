-- rig-knight —— Nano Banana 生成的 3/4 视骑士 → 切件 → 骨骼动画（LÖVE）
-- 运行：love example/rig-knight    |    出图：RIG_EXPORT=out.png love example/rig-knight
local root = os.getenv("HOME") .. "/iso_flutter"
package.path = root .. "/iso_engine/lib/lua/?.lua;" .. package.path
local rig = require("rig")
local PARTS = os.getenv("RIG_PARTS") or (root .. "/example/rig-knight/parts")
local SWORD = os.getenv("RIG_SWORD") or (root .. "/app/assets/parts/sword_weapon.png")

local function loadImg(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close()
  local im = love.graphics.newImage(love.filesystem.newFileData(d, "p.png")); im:setFilter("linear", "linear"); return im
end
local function att(file, w, h, px, py) return { img = loadImg(PARTS .. "/" .. file), w = w, h = h, pivotX = px, pivotY = py } end
local function attPath(path, w, h, px, py) return { img = loadImg(path), w = w, h = h, pivotX = px, pivotY = py } end

-- 坐标来自 cutparts.sh 的 parts.json（bbox 1034x1808；y 向下；脚在 1808）
local def = {
  bones = {
    { name = "root" },
    { name = "spine", parent = "root",  x = 0,    y = -398 },  -- 髋(517,1410)
    { name = "chest", parent = "spine", x = 0,    y = -506 },  -- 颈(517,904)
    { name = "head",  parent = "chest", x = 0,    y = 0 },
    { name = "armL",  parent = "chest", x = -248, y = 90 },    -- 左肩(269,994)
    { name = "armR",  parent = "chest", x = 248,  y = 90 },    -- 右肩(765,994)
    { name = "legL",  parent = "spine", x = -103, y = 0 },     -- 左髋(414,1410)
    { name = "legR",  parent = "spine", x = 103,  y = 0 },
  },
  slots = {
    { name = "armL",  bone = "armL",  order = 1, att = att("armL.png",  208, 633, 135, 0) },
    { name = "legL",  bone = "legL",  order = 2, att = att("legL.png",  206, 398, 103, 0) },
    { name = "legR",  bone = "legR",  order = 3, att = att("legR.png",  206, 398, 103, 0) },
    { name = "torso", bone = "spine", order = 4, att = att("torso.png", 412, 506, 206, 506) },
    { name = "head",  bone = "head",  order = 5, att = att("head.png",  620, 904, 310, 904) },
    { name = "armR",  bone = "armR",  order = 6, att = att("armR.png",  208, 633, 73,  0) },
    { name = "sword", bone = "armR",  order = 7, att = attPath(SWORD, 512, 512, 150, 400), x = 20, y = 585, rot = -0.75 },
  },
  clips = {
    idle = {
      duration = 2.4, loop = true,
      bones = {
        spine = { { t = 0, y = -398 }, { t = 1.2, y = -404, ease = "inout" }, { t = 2.4, y = -398, ease = "inout" } },
        chest = { { t = 0, rot = 0.015 }, { t = 1.2, rot = -0.02, ease = "inout" }, { t = 2.4, rot = 0.015, ease = "inout" } },
        head  = { { t = 0, rot = 0.01 }, { t = 1.2, rot = -0.02, ease = "inout" }, { t = 2.4, rot = 0.01, ease = "inout" } },
        armL  = { { t = 0, rot = 0.03 }, { t = 1.2, rot = 0.07, ease = "inout" }, { t = 2.4, rot = 0.03, ease = "inout" } },
        armR  = { { t = 0, rot = -0.03 }, { t = 1.2, rot = -0.07, ease = "inout" }, { t = 2.4, rot = -0.03, ease = "inout" } },
      },
    },
    walk = {
      duration = 0.72, loop = true,
      bones = {
        spine = { { t = 0, y = -398 }, { t = 0.18, y = -408, ease = "out" }, { t = 0.36, y = -398, ease = "in_" },
                  { t = 0.54, y = -408, ease = "out" }, { t = 0.72, y = -398, ease = "in_" } },
        chest = { { t = 0, rot = 0.05 }, { t = 0.36, rot = -0.05 }, { t = 0.72, rot = 0.05 } },
        head  = { { t = 0, rot = -0.03 }, { t = 0.36, rot = 0.03 }, { t = 0.72, rot = -0.03 } },
        armL  = { { t = 0, rot = -0.55 }, { t = 0.36, rot = 0.55 }, { t = 0.72, rot = -0.55 } },
        armR  = { { t = 0, rot = 0.55 }, { t = 0.36, rot = -0.55 }, { t = 0.72, rot = 0.55 } },
        legL  = { { t = 0, rot = 0.22, y = 0 }, { t = 0.18, rot = -0.05, y = -22, ease = "out" },
                  { t = 0.36, rot = -0.22, y = 0 }, { t = 0.72, rot = 0.22, y = 0 } },
        legR  = { { t = 0, rot = -0.22, y = 0 }, { t = 0.54, rot = 0.05, y = -22, ease = "out" },
                  { t = 0.72, rot = -0.22, y = 0 } },
      },
    },
    walkswing = {
      duration = 1.0, loop = true,
      bones = {
        spine = { { t = 0, y = -398 }, { t = 0.25, y = -406, ease = "out" }, { t = 0.5, y = -398, ease = "in_" },
                  { t = 0.75, y = -406, ease = "out" }, { t = 1.0, y = -398, ease = "in_" } },
        chest = { { t = 0, rot = 0.04 }, { t = 0.5, rot = -0.04 }, { t = 1.0, rot = 0.04 } },
        head  = { { t = 0, rot = -0.02 }, { t = 0.5, rot = 0.02 }, { t = 1.0, rot = -0.02 } },
        armL  = { { t = 0, rot = -0.5 }, { t = 0.5, rot = 0.5 }, { t = 1.0, rot = -0.5 } },
        armR  = { { t = 0, rot = 0.5 }, { t = 0.14, rot = -1.35, ease = "out" }, { t = 0.28, rot = 1.15, ease = "in_" },
                  { t = 0.5, rot = 0.5 }, { t = 0.64, rot = -1.35, ease = "out" }, { t = 0.78, rot = 1.15, ease = "in_" }, { t = 1.0, rot = 0.5 } },
        legL  = { { t = 0, rot = 0.25 }, { t = 0.25, rot = -0.25 }, { t = 0.5, rot = 0.25 }, { t = 0.75, rot = -0.25 }, { t = 1.0, rot = 0.25 } },
        legR  = { { t = 0, rot = -0.25 }, { t = 0.25, rot = 0.25 }, { t = 0.5, rot = -0.25 }, { t = 0.75, rot = 0.25 }, { t = 1.0, rot = -0.25 } },
      },
    },
    attack = {
      duration = 0.5, loop = false,
      bones = {
        chest = { { t = 0, rot = 0.05 }, { t = 0.15, rot = -0.12, ease = "out" }, { t = 0.28, rot = 0.22, ease = "in_" }, { t = 0.5, rot = 0.05 } },
        armR  = { { t = 0, rot = -0.1 }, { t = 0.15, rot = -1.9, ease = "out" }, { t = 0.28, rot = 1.0, ease = "in_" }, { t = 0.5, rot = -0.1 } },
        armL  = { { t = 0, rot = 0.05 }, { t = 0.15, rot = 0.4, ease = "out" }, { t = 0.28, rot = -0.3, ease = "in_" }, { t = 0.5, rot = 0.05 } },
        spine = { { t = 0, y = -398 }, { t = 0.28, y = -390 }, { t = 0.5, y = -398 } },
      },
    },
  },
}

local R = rig.new(def)
local W, H = 760, 460
local SHOTS = {
  { "idle", 0 }, { "idle", 1.2 },
  { "walk", 0 }, { "walk", 0.18 }, { "walk", 0.36 }, { "walk", 0.54 },
  { "attack", 0.15 }, { "attack", 0.28 },
}

local function render(path)
  local c = love.graphics.newCanvas(W, H)
  love.graphics.setCanvas(c); love.graphics.clear(0.94, 0.94, 0.90)
  local cols = 4
  for i, sh in ipairs(SHOTS) do
    R:setClip(sh[1], { time = sh[2] }); R:_apply()
    local gx = 60 + ((i - 1) % cols) * 180
    local gy = 210 + math.floor((i - 1) / cols) * 230
    R:draw(gx, gy, 0.14, false)
    love.graphics.setColor(0, 0, 0); love.graphics.print(sh[1] .. " " .. sh[2], gx - 30, gy + 8); love.graphics.setColor(1, 1, 1)
  end
  love.graphics.setCanvas()
  local fd = c:newImageData():encode("png")
  local f = io.open(path, "wb"); f:write(fd:getString()); f:close()
end

-- 逐帧导出（动画 GIF 用）：RIG_ANIM=<clip> RIG_ANIM_DIR=<dir> RIG_ANIM_N=<帧数>
local function renderAnim(clip, dir, n)
  n = n or 20
  local dur = (def.clips[clip] and def.clips[clip].duration) or 1
  local cw, ch = 260, 320
  for i = 0, n - 1 do
    R:setClip(clip, { time = i / n * dur }); R:_apply()
    local c = love.graphics.newCanvas(cw, ch)
    love.graphics.setCanvas(c); love.graphics.clear(0.94, 0.94, 0.90)
    R:draw(cw / 2, ch - 14, 0.16, false)
    love.graphics.setCanvas()
    local fd = c:newImageData():encode("png")
    local f = io.open(string.format("%s/%s_%03d.png", dir, clip, i), "wb"); f:write(fd:getString()); f:close()
  end
end

function love.load()
  if os.getenv("RIG_ANIM") then
    renderAnim(os.getenv("RIG_ANIM"), os.getenv("RIG_ANIM_DIR") or "/tmp", tonumber(os.getenv("RIG_ANIM_N") or "20"))
    love.event.quit()
  elseif os.getenv("RIG_EXPORT") then render(os.getenv("RIG_EXPORT")); love.event.quit()
  else R:setClip("walk"); love.graphics.setBackgroundColor(0.94, 0.94, 0.90) end
end
function love.update(dt) if not os.getenv("RIG_EXPORT") then R:update(dt) end end
function love.keypressed(k)
  if k == "1" then R:setClip("idle") elseif k == "2" then R:setClip("walk") elseif k == "3" then R:setClip("attack", { loop = false }) end
end
function love.draw()
  if os.getenv("RIG_EXPORT") then return end
  R:draw(W / 2 - 120, H - 30, 0.18, false); R:draw(W / 2 + 120, H - 30, 0.18, true)
  love.graphics.print("1=idle 2=walk 3=attack", 16, 16)
end
