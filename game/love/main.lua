-- LÖVE 集成：等距「兵线对推」。
-- 复用：iso_engine/lib/lua/game/battle.lua（纯 Lua Sim）+ app/assets/sprites/*.png（img.sh 生成）
-- 运行：love ~/iso_flutter/game/love
local root = love.filesystem.getSource():gsub("/game/love$", "")

-- Lua 模块（标准 require 走真实文件系统）
package.path = root .. "/iso_engine/lib/lua/game/?.lua;" .. root .. "/iso_engine/lib/lua/?.lua;" .. package.path

local battle = require("battle")
local rig = require("rig")
local skin = require("skin")

-- 加载 CC0 角色帧（game/love/assets/chars/<name>_<anim>_<i>.png）
ANIM = {}
local function loadAnim(name, anim, maxf)
  local list = {}
  for i = 0, maxf - 1 do
    local img = loadImage(root .. "/game/love/assets/chars/" .. name .. "_" .. anim .. "_" .. i .. ".png")
    if not img then break end
    img:setFilter("linear", "linear")
    list[#list + 1] = img
  end
  ANIM[name] = ANIM[name] or {}
  ANIM[name][anim] = list
end

-- 从真实路径读图（LÖVE 11 无 mountFullPath → io 读字节 + newFileData）
function loadImage(path, mip)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, img = pcall(love.graphics.newImage, love.filesystem.newFileData(data, "sprite.png"), mip and { mipmaps = true } or nil)
  return ok and img or nil
end

-- Nano Banana 关键帧动画（game/love/assets/nb/<name>_<anim>_<i>.png）
NBANIM = {}
local function loadNbAnim(name, anim, maxf)
  local list = {}
  for i = 0, maxf - 1 do
    local img = loadImage(root .. "/game/love/assets/nb/" .. name .. "_" .. anim .. "_" .. i .. ".png", true)
    if not img then break end
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear")
    list[#list + 1] = img
  end
  if #list > 0 then NBANIM[name] = NBANIM[name] or {}; NBANIM[name][anim] = list end
end

local CA, SA, SE, CE, U = 0.70710678, 0.70710678, 0.5, 0.86602540, 1.2649110640673518
local cam  -- 前向声明（drawRigUnit 会用到，稍后赋值）

-- 骨骼骑士（Nano Banana 生成角色 → cutparts.sh 切件；见 example/rig-knight）
local RIGDEF
local function loadRigDef()
  local dir = root .. "/example/rig-knight/parts/"
  local function im(f) local x = loadImage(dir .. f); if x then x:setFilter("linear", "linear") end; return x end
  local function att(f, w, h, px, py) return { img = im(f), w = w, h = h, pivotX = px, pivotY = py } end
  RIGDEF = {
    bones = {
      { name = "root" },
      { name = "spine", parent = "root",  x = 0,    y = -398 },
      { name = "chest", parent = "spine", x = 0,    y = -506 },
      { name = "head",  parent = "chest", x = 0,    y = 0 },
      { name = "armL",  parent = "chest", x = -248, y = 90 },
      { name = "armR",  parent = "chest", x = 248,  y = 90 },
      { name = "legL",  parent = "spine", x = -103, y = 0 },
      { name = "legR",  parent = "spine", x = 103,  y = 0 },
    },
    slots = {
      { name = "armL",  bone = "armL",  order = 1, att = att("armL.png",  208, 633, 135, 0) },
      { name = "legL",  bone = "legL",  order = 2, att = att("legL.png",  206, 398, 103, 0) },
      { name = "legR",  bone = "legR",  order = 3, att = att("legR.png",  206, 398, 103, 0) },
      { name = "torso", bone = "spine", order = 4, att = att("torso.png", 412, 506, 206, 506) },
      { name = "head",  bone = "head",  order = 5, att = att("head.png",  620, 904, 310, 904) },
      { name = "armR",  bone = "armR",  order = 6, att = att("armR.png",  208, 633, 73,  0) },
    },
    clips = {
      idle = { duration = 2.4, loop = true, bones = {
        spine = { { t = 0, y = -398 }, { t = 1.2, y = -404, ease = "inout" }, { t = 2.4, y = -398, ease = "inout" } },
        chest = { { t = 0, rot = 0.015 }, { t = 1.2, rot = -0.02, ease = "inout" }, { t = 2.4, rot = 0.015, ease = "inout" } },
        armL  = { { t = 0, rot = 0.03 }, { t = 1.2, rot = 0.07, ease = "inout" }, { t = 2.4, rot = 0.03, ease = "inout" } },
        armR  = { { t = 0, rot = -0.03 }, { t = 1.2, rot = -0.07, ease = "inout" }, { t = 2.4, rot = -0.03, ease = "inout" } },
      } },
      walk = { duration = 0.72, loop = true, bones = {
        spine = { { t = 0, y = -398 }, { t = 0.18, y = -408, ease = "out" }, { t = 0.36, y = -398, ease = "in_" }, { t = 0.54, y = -408, ease = "out" }, { t = 0.72, y = -398, ease = "in_" } },
        chest = { { t = 0, rot = 0.05 }, { t = 0.36, rot = -0.05 }, { t = 0.72, rot = 0.05 } },
        head  = { { t = 0, rot = -0.03 }, { t = 0.36, rot = 0.03 }, { t = 0.72, rot = -0.03 } },
        armL  = { { t = 0, rot = -0.55 }, { t = 0.36, rot = 0.55 }, { t = 0.72, rot = -0.55 } },
        armR  = { { t = 0, rot = 0.55 }, { t = 0.36, rot = -0.55 }, { t = 0.72, rot = 0.55 } },
        legL  = { { t = 0, rot = 0.22, y = 0 }, { t = 0.18, rot = -0.05, y = -22, ease = "out" }, { t = 0.36, rot = -0.22, y = 0 }, { t = 0.72, rot = 0.22, y = 0 } },
        legR  = { { t = 0, rot = -0.22, y = 0 }, { t = 0.54, rot = 0.05, y = -22, ease = "out" }, { t = 0.72, rot = -0.22, y = 0 } },
      } },
    },
  }
end

local RIGUNITS = setmetatable({}, { __mode = "k" })
local function drawRigUnit(u, x, y)
  local R = RIGUNITS[u]
  if not R then R = rig.new(RIGDEF); RIGUNITS[u] = R; u.phase = (u.x * 0.7 + u.lane * 1.3) end
  local clip = u.moving and "walk" or "idle"
  R:setClip(clip, { time = (love.timer.getTime() + u.phase) % RIGDEF.clips[clip].duration })
  R:draw(x, y, 2.0 * cam.s / 1808, u.side == "right")
end

-- 单图网格蒙皮（skin.lua）：整张骑士图不切、按骨骼平滑形变（无切痕）
local SKINDEF, SKIN_HPX, SKIN_HPY, SKIN_H
local function buildKnightSkin()
  local img = loadImage(root .. "/example/rig-knight/knight_half.png")
  if img then img:setFilter("linear", "linear") end
  if not img then return end
  local s = 0.5
  local hipX, hipY = 825 * s, 1666 * s            -- 髋（图像坐标）
  local neckX, neckY = 825 * s, 1160 * s
  local shLX, shLY = 577 * s, 1250 * s
  local shRX, shRY = 1073 * s, 1250 * s
  SKIN_HPX, SKIN_HPY = hipX, hipY + 199           -- 脚底（图像坐标）
  SKIN_H = 1810 * s
  SKINDEF = {
    image = img,
    bbox = { x = 308 * s, y = 256 * s, w = 1036 * s, h = 1810 * s },
    grid = { 16, 22 }, radius = 200 * s, power = 2, maxInfl = 4,
    bones = {
      { name = "root", x = hipX, y = hipY + 199 },
      { name = "spine", parent = "root",  x = 0, y = -199 },
      { name = "chest", parent = "spine", x = 0, y = -253 },
      { name = "head",  parent = "chest", x = 0, y = 0 },
      { name = "armL",  parent = "chest", x = -124, y = 45 },
      { name = "armR",  parent = "chest", x = 124,  y = 45 },
      { name = "legL",  parent = "spine", x = -51,  y = 0 },
      { name = "legR",  parent = "spine", x = 51,   y = 0 },
    },
    segs = {
      root  = { hipX, hipY + 200, hipX, hipY + 225 },
      spine = { hipX, hipY, neckX, neckY + 20 },
      chest = { hipX, (hipY + neckY) / 2, neckX, neckY },
      head  = { neckX, neckY, neckX, neckY - 210 },
      armL  = { shLX, shLY, shLX - 45, shLY + 260 },
      armR  = { shRX, shRY, shRX + 45, shRY + 260 },
      legL  = { hipX - 51, hipY, hipX - 60, hipY + 200 },
      legR  = { hipX + 51, hipY, hipX + 60, hipY + 200 },
    },
    clips = {
      idle = { duration = 2.4, loop = true, bones = {
        spine = { { t = 0, y = -199 }, { t = 1.2, y = -201 }, { t = 2.4, y = -199 } },
        armL  = { { t = 0, rot = 0.04 }, { t = 1.2, rot = 0.09 }, { t = 2.4, rot = 0.04 } },
        armR  = { { t = 0, rot = -0.04 }, { t = 1.2, rot = -0.09 }, { t = 2.4, rot = -0.04 } },
      } },
      walk = { duration = 0.72, loop = true, bones = {
        spine = { { t = 0, y = -199 }, { t = 0.18, y = -203, ease = "out" }, { t = 0.36, y = -199, ease = "in_" }, { t = 0.54, y = -203, ease = "out" }, { t = 0.72, y = -199, ease = "in_" } },
        chest = { { t = 0, rot = 0.04 }, { t = 0.36, rot = -0.04 }, { t = 0.72, rot = 0.04 } },
        armL  = { { t = 0, rot = -0.4 }, { t = 0.36, rot = 0.4 }, { t = 0.72, rot = -0.4 } },
        armR  = { { t = 0, rot = 0.4 }, { t = 0.36, rot = -0.4 }, { t = 0.72, rot = 0.4 } },
        legL  = { { t = 0, rot = 0.2 }, { t = 0.36, rot = -0.2 }, { t = 0.72, rot = 0.2 } },
        legR  = { { t = 0, rot = -0.2 }, { t = 0.36, rot = 0.2 }, { t = 0.72, rot = -0.2 } },
      } },
    },
  }
end

local SKINU = setmetatable({}, { __mode = "k" })
local function drawSkinUnit(u, x, y)
  local S = SKINU[u]
  if not S then
    S = skin.new(SKINDEF); SKINU[u] = S
    u.phase = (u.x * 0.7 + u.lane * 1.3)
  end
  local clip = u.moving and "walk" or "idle"
  S:setClip(clip, { time = (love.timer.getTime() + u.phase) % SKINDEF.clips[clip].duration })
  S:deform()
  local sc = 2.0 * cam.s / SKIN_H
  S:draw(x - SKIN_HPX * sc, y - SKIN_HPY * sc, sc, u.side == "right")
end

-- 等距投影（地面 x,y → 屏幕相对）
local FY = 0.78  -- 竖向压扁（俯视 3/4）
local function iso(x, y) return x, y * FY end

cam = { ox = 0, oy = 0, s = 40 }
local function sx(x, y) local a, b = iso(x, y); return cam.ox + a * cam.s, cam.oy + b * cam.s end

local SPR, PART, game
local dt = 1 / 60

local function loadSprites()
  SPR = {}
  for _, n in ipairs({ "sword", "archer", "mage", "goblin", "shooter", "ogre", "castle_blue", "castle_red", "tile", "sword_sheet", "goblin_sheet", "archer_sheet", "mage_sheet", "shooter_sheet", "ogre_sheet" }) do
    local img = loadImage(root .. "/app/assets/sprites/" .. n .. ".png")
    local ok = img ~= nil
    if ok then img:setFilter("linear", "linear"); SPR[n] = img end
  end
  -- 分件（A 骨骼）
  PART = {}
  for _, n in ipairs({ "sword_head","sword_torso","sword_arm","sword_leg","sword_weapon",
                       "goblin_head","goblin_torso","goblin_arm","goblin_leg","goblin_weapon" }) do
    local img = loadImage(root .. "/app/assets/parts/" .. n .. ".png")
    if img then img:setFilter("linear", "linear"); PART[n] = img end
  end
  -- 帧表 → 4 帧 Quad（B 逐帧）
  QUAD = {}
  for _, n in ipairs({ "sword_sheet", "goblin_sheet", "archer_sheet", "mage_sheet", "shooter_sheet", "ogre_sheet" }) do
    local img = SPR[n]
    if img then
      local fw = img:getWidth() / 4
      local base = n:gsub("_sheet$", "")
      QUAD[base] = {}
      for i = 0, 3 do
        QUAD[base][i + 1] = love.graphics.newQuad(i * fw, 0, fw, img:getHeight(), img:getDimensions())
      end
    end
  end
end
local QUAD = {}

local function fit()
  local w, h = love.graphics.getDimensions()
  local cols, rows = game.cols, game.rows
  cam.s = math.min(w * 0.88 / cols, h * 0.98 / (rows * FY))  -- 战场铺满屏幕（留边给两塔）
  cam.ox = w / 2 - cols / 2 * cam.s
  cam.oy = h / 2 - rows * FY / 2 * cam.s
end

local sel = "sword"
local TYPESEL = { ["1"] = "sword", ["2"] = "archer", ["3"] = "mage" }
-- 兵种 → 分件组装角色（char.sh 生成；可换武器 + 染色）
local CHARMAP = { sword = "u1", archer = "u2", mage = "u3", goblin = "e1", shooter = "e2", ogre = "e3" }
-- 兵种 → Nano Banana 关键帧角色（assets/nb/<name>_<anim>_<i>.png）
local NBMAP = { sword = "knight", archer = "knight", mage = "knight", goblin = "knight", shooter = "knight", ogre = "knight" }

-- 飘伤害数字 / 大招特效 / 闪光 / 震屏
local POPS = {}
local ULT_FX = nil
local FLASH_T = 0
local SHAKE = 0
local ULT_DUR = 1.1
local WHIRL_DUR = 0.75

-- NB 关键帧动画：大招 / 旋风斩 / 攻击 / 走 / 站；含受击闪红 + 弧光
local function drawNBUnit(u, x, y, name)
  local A = NBANIM[name]
  if not A then return false end
  local h = 1.9 * cam.s
  local dir = (u.side == "right") and -1 or 1
  local img
  if u._castUlt and u._castUlt > 0 and A.ult and #A.ult > 0 then
    -- 大招：蓄力→举剑→砸地（不循环，从头放）
    local p  = 1 - u._castUlt / ULT_DUR
    local fi = math.min(#A.ult, math.floor(p * #A.ult) + 1)
    img = A.ult[fi]
  elseif A.whirl and #A.whirl > 0 and ((u._whirl and u._whirl > 0) or (u.attacking and u.type == "ogre")) then
    -- 旋转挥刀（旋风斩）：玩家技能(W) 或 食人魔攻击
    local p
    if u._whirl and u._whirl > 0 then p = 1 - u._whirl / WHIRL_DUR
    else p = 1 - (u.cd or 0) / ((battle.TYPES[u.type] or {}).rate or 1) end
    local fi = math.min(#A.whirl, math.floor(p * #A.whirl) + 1)
    img = A.whirl[fi]
    -- 旋转刀光（多道弧线绕身飞转 + 扩散环）
    local rot = p * 6.283 * 2
    love.graphics.setLineWidth(7)
    for k = 0, 3 do
      local a0 = rot + k * 1.571
      love.graphics.setColor(1, 1, 1, 0.85 * (1 - p))
      love.graphics.arc("line", "open", x, y - h * 0.45, h * 0.85, a0, a0 + 1.6)
    end
    for k = 0, 1 do
      local rr = (1 - p) * (0.4 + k * 0.35)
      love.graphics.setColor(0.8, 0.92, 1, 0.5 * (1 - rr)); love.graphics.setLineWidth(5)
      love.graphics.ellipse("line", x, y, (0.9 - rr) * h * 0.8, (0.9 - rr) * h * 0.8 * FY)
    end
    love.graphics.setColor(1, 1, 1); love.graphics.setLineWidth(1)
  elseif u.attacking and A.attack and #A.attack > 0 and (battle.TYPES[u.type] or {}).rate then
    -- 攻击：举剑→劈砍→收势，同步攻击间隔
    local rate = (battle.TYPES[u.type] or {}).rate
    local p  = 1 - (u.cd or 0) / rate
    local fi = math.min(#A.attack, math.floor(p * #A.attack) + 1)
    img = A.attack[fi]
    if p > 0.15 and p < 0.72 then
      love.graphics.setColor(1, 1, 1, 0.6 * (1 - math.abs(p - 0.42) / 0.3)); love.graphics.setLineWidth(3)
      love.graphics.arc("line", "open", x + dir * 0.22 * h, y - h * 0.5, h * 0.34, -0.95 * dir, 0.75 * dir)
      love.graphics.setColor(1, 1, 1); love.graphics.setLineWidth(1)
    end
  else
    local list = (u.moving and A.walk) or A.idle or A.walk
    if not list or #list == 0 then return false end
    local fps = u.moving and 10 or 8
    local fi = math.floor(love.timer.getTime() * fps + u.x * 1.3 + u.lane * 0.7) % #list + 1
    img = list[fi]
  end
  if not img then return false end
  local w = h * img:getWidth() / img:getHeight()
  local fl = u._flash
  if fl and fl > 0 then love.graphics.setColor(1, 0.5, 0.5) end          -- 受击闪红
  love.graphics.draw(img, x - w / 2 * dir, y - h, 0, dir * w / img:getWidth(), h / img:getHeight())
  if fl and fl > 0 then love.graphics.setColor(1, 1, 1) end
  return true
end

function love.load()
  love.graphics.setBackgroundColor(0.94, 0.94, 0.92)
  -- 中文字体（仓耳今楷）
  local fp = os.getenv("HOME") .. "/.local/share/fonts/TsangerJinKai/TsangerJinKai02-W05.ttf"
  local h = io.open(fp, "rb")
  if h then
    local bytes = h:read("*a"); h:close()
    local ok, f = pcall(love.graphics.newFont, love.filesystem.newFileData(bytes, "cjk.ttf"), 16)
    if ok then love.graphics.setFont(f) end
  end
  loadSprites()
  loadRigDef()
  buildKnightSkin()
  for _, nm in ipairs({ "u1", "u2", "u3", "e1", "e2", "e3" }) do
    loadAnim(nm, "walk", 12); loadAnim(nm, "idle", 12); loadAnim(nm, "hit", 6); loadAnim(nm, "death", 12)
  end
  loadNbAnim("knight", "walk", 4); loadNbAnim("knight", "idle", 4); loadNbAnim("knight", "attack", 3)
  loadNbAnim("knight", "whirl", 5); loadNbAnim("knight", "ult", 4)
  game = battle.new({ cols = 10, rows = 8 })
  fit()
end

function love.update(d)
  if game.over then return end
  game:step(d)
  -- 伤害事件 → 受击闪红 + 飘伤害数字
  for _, u in ipairs(game.units) do
    local lh = u._lastHp
    if lh and u.hp < lh - 0.01 then
      u._flash = 0.16
      local x, y = sx(u.x, u.lane)
      POPS[#POPS + 1] = { x = x, y = y - 2.0 * cam.s, val = math.max(1, math.floor(lh - u.hp + 0.5)), t = 0 }
    end
    u._lastHp = u.hp
    if u._flash then u._flash = u._flash - d; if u._flash <= 0 then u._flash = nil end end
    if u._castUlt then u._castUlt = u._castUlt - d; if u._castUlt <= 0 then u._castUlt = nil end end
    if u._whirl then u._whirl = u._whirl - d; if u._whirl <= 0 then u._whirl = nil end end
  end
  for i = #POPS, 1, -1 do
    POPS[i].t = POPS[i].t + d
    if POPS[i].t > 0.9 then table.remove(POPS, i) end
  end
  if ULT_FX then
    ULT_FX.t = ULT_FX.t + d
    if not ULT_FX.impacted and ULT_FX.t >= 0.45 * ULT_FX.life then
      ULT_FX.impacted = true; SHAKE = 15; FLASH_T = 0.3     -- 砸地瞬间：震屏 + 闪光
    end
    if ULT_FX.t > ULT_FX.life then ULT_FX = nil end
  end
  if FLASH_T > 0 then FLASH_T = math.max(0, FLASH_T - d) end
  SHAKE = math.max(0, SHAKE - d * 45)
end

function love.keypressed(k)
  if TYPESEL[k] then sel = TYPESEL[k] end
  if k == "r" then game = battle.new({ cols = 10, rows = 8 }); fit(); POPS = {}; ULT_FX = nil; FLASH_T = 0; SHAKE = 0 end
  if (k == "space" or k == "q") and not game.over then
    if game:ultimate() then                        -- 大招：全体敌方受创
      local lead
      for _, u in ipairs(game.units) do
        if u.side == "left" and u.hp > 0 and (not lead or u.x > lead.x) then lead = u end
      end
      local x, y
      if lead then lead._castUlt = ULT_DUR; x, y = sx(lead.x, lead.lane)
      else x, y = sx(1, game.rows / 2) end
      ULT_FX = { x = x, y = y, t = 0, life = ULT_DUR, sparks = {} }
      for k2 = 1, 18 do
        local ang = love.math.random() * 6.283
        ULT_FX.sparks[k2] = { dx = math.cos(ang), dy = math.sin(ang) * FY, s = 1.5 + love.math.random() * 2.5 }
      end
    end
  end
  if k == "w" and not game.over then                       -- 旋转挥刀：全体我方单位旋风斩
    if game:whirlwind() then
      for _, u in ipairs(game.units) do
        if u.side == "left" and u.hp > 0 then u._whirl = WHIRL_DUR end
      end
    end
  end
end

function love.mousepressed(mx, my, btn)
  if btn ~= 1 or game.over then return end
  -- 屏幕 → 地面（逆等距）
  local gx = (mx - cam.ox) / cam.s
  local gy = (my - cam.oy) / (cam.s * FY)
  if gx < game.cols / 2 then
    game:deploy(math.max(0, math.min(game.rows - 1, math.floor(gy + 0.5))), sel)
  end
end

-- 分件骨骼：把件按关节位置/角度画出来
local function part(img, px, py, ang, lenPx, flip, pvx, pvy)
  if not img then return end
  local iw, ih = img:getDimensions()
  local sc = lenPx / ih
  love.graphics.draw(img, px, py, ang, sc * (flip and -1 or 1), sc, iw * pvx, ih * pvy)
end

local function drawRig(u, x, y)
  local dir = (u.side == "right") and -1 or 1
  local H = 1.55 * cam.s
  local flip = dir < 0
  local moving = u.moving
  local t = love.timer.getTime()
  local ph = t * 9 + u.x * 1.2
  local sw = moving and math.sin(ph) * 0.5 or 0
  local b = moving and math.abs(math.sin(ph)) * 0.03 or 0     -- 躯干起伏
  local atk = u.cd and u.rate and u.cd > u.rate * 0.8
  local hipY, shoY, headY = y - H * 0.44, y - H * 0.74 - H * b, y - H * 0.90 - H * b
  local P = PART
  if u.side == "right" then love.graphics.setColor(1.15, 0.62, 0.62) else love.graphics.setColor(1, 1, 1) end
  local function pfx(k) return "sword_" .. k end  -- 统一用骑士这套件（可靠）
  -- 层序：后腿 → 后臂 → 躯干 → 头 → 前腿 → 前臂(+武器)
  part(P[pfx("leg")], x, hipY, sw * dir, H * 0.50, flip, 0.5, 0.06)
  part(P[pfx("arm")], x, shoY, -sw * dir, H * 0.34, flip, 0.5, 0.06)
  part(P[pfx("torso")], x, (hipY + shoY) / 2, 0, H * 0.40, flip, 0.5, 0.5)
  part(P[pfx("head")], x, headY, 0, H * 0.30, flip, 0.5, 0.92)
  part(P[pfx("leg")], x, hipY, -sw * dir, H * 0.50, flip, 0.5, 0.06)
  local armAng = (atk and -1.4 or sw) * dir
  part(P[pfx("arm")], x, shoY, armAng, H * 0.34, flip, 0.5, 0.06)
  part(P[pfx("weapon")], x + dir * 0.10 * H, shoY + H * (atk and -0.02 or 0.28), (atk and 0.9 or 0.3) * dir, H * 0.36, flip, 0.5, 0.9)
  love.graphics.setColor(1, 1, 1)
end

local function drawUnit(u)
  local x, y = sx(u.x, u.lane)
  local t = love.timer.getTime()
  -- Nano Banana 关键帧（最高优先级）
  local nbn = NBMAP[u.type]
  if nbn and drawNBUnit(u, x, y, nbn) then
    if u.hp < u.max then
      local bw = 32
      love.graphics.setColor(0, 0, 0, 0.2); love.graphics.rectangle("fill", x - bw / 2, y - 2.4 * cam.s, bw, 4)
      local col = u.side == "left" and { 0.24, 0.39, 0.87 } or { 0.9, 0.28, 0.3 }
      love.graphics.setColor(col); love.graphics.rectangle("fill", x - bw / 2, y - 2.4 * cam.s, bw * (u.hp / u.max), 4); love.graphics.setColor(1, 1, 1)
    end
    return
  end
  -- 骨骼骑士（单图网格蒙皮，skin.lua）
  if SKINDEF then
    drawSkinUnit(u, x, y)
    if u.hp < u.max then
      local bw = 32
      love.graphics.setColor(0, 0, 0, 0.2); love.graphics.rectangle("fill", x - bw / 2, y - 1.7 * cam.s, bw, 4)
      local col = u.side == "left" and { 0.24, 0.39, 0.87 } or { 0.9, 0.28, 0.3 }
      love.graphics.setColor(col); love.graphics.rectangle("fill", x - bw / 2, y - 1.7 * cam.s, bw * (u.hp / u.max), 4); love.graphics.setColor(1, 1, 1)
    end
    return
  end
  -- 备用：刚性分件骨骼
  if RIGDEF then
    drawRigUnit(u, x, y)
    if u.hp < u.max then
      local bw = 32
      love.graphics.setColor(0, 0, 0, 0.2); love.graphics.rectangle("fill", x - bw / 2, y - 1.7 * cam.s, bw, 4)
      local col = u.side == "left" and { 0.24, 0.39, 0.87 } or { 0.9, 0.28, 0.3 }
      love.graphics.setColor(col); love.graphics.rectangle("fill", x - bw / 2, y - 1.7 * cam.s, bw * (u.hp / u.max), 4); love.graphics.setColor(1, 1, 1)
    end
    return
  end
  local nm = CHARMAP[u.type] or ((u.side == "left") and "u1" or "e1")
  local A = ANIM[nm]
  if A and A.walk and #A.walk > 0 then
    local anim = (u.moving and A.walk) or A.idle
    if not anim or #anim == 0 then anim = A.walk end
    local fps = u.moving and 10 or 5
    local fi = math.floor(t * fps + u.x * 1.3 + u.lane * 0.7) % #anim + 1
    local img = anim[fi]
    local h = 1.5 * cam.s
    local w = h * img:getWidth() / img:getHeight()
    local fx = (u.side == "right") and -1 or 1
    love.graphics.draw(img, x - w / 2 * fx, y - h, 0, fx * w / img:getWidth(), h / img:getHeight())
    if u.hp < u.max then
      local bw = 32
      love.graphics.setColor(0, 0, 0, 0.2); love.graphics.rectangle("fill", x - bw / 2, y - 1.7 * cam.s, bw, 4)
      local col = u.side == "left" and { 0.24, 0.39, 0.87 } or { 0.9, 0.28, 0.3 }
      love.graphics.setColor(col); love.graphics.rectangle("fill", x - bw / 2, y - 1.7 * cam.s, bw * (u.hp / u.max), 4); love.graphics.setColor(1, 1, 1)
    end
    return
  end
  if PART and PART[u.type .. "_head"] then
    drawRig(u, x, y)
    if u.hp < u.max then
      local bw = 32
      love.graphics.setColor(0, 0, 0, 0.2); love.graphics.rectangle("fill", x - bw / 2, y - 2.6 * cam.s, bw, 4)
      local col = u.side == "left" and { 0.24, 0.39, 0.87 } or { 0.9, 0.28, 0.3 }
      love.graphics.setColor(col); love.graphics.rectangle("fill", x - bw / 2, y - 2.6 * cam.s, bw * (u.hp / u.max), 4); love.graphics.setColor(1, 1, 1)
    end
    return
  end
  local img = SPR[u.type]
  local quads = QUAD[u.type]
  if not img or (quads and QUAD[u.type]) then img = SPR[u.type .. "_sheet"] or img end
  if not img then return end
  local fw = quads and img:getWidth() / 4 or img:getWidth()
  local h = 1.35 * cam.s
  local w = h * fw / img:getHeight()
  local fx = (u.side == "right") and -1 or 1
  local q = nil
  if quads then
    local frame = u.moving and (math.floor(t * 10 + u.x * 1.7 + u.lane) % 4 + 1) or 1
    q = quads[frame]
  end
  if q then
    love.graphics.draw(img, q, x - w / 2 * fx, y - h, 0, fx * w / fw, h / img:getHeight())
  else
    love.graphics.draw(img, x - w / 2 * fx, y - h, 0, fx * w / fw, h / img:getHeight())
  end
  -- HP 条
  if u.hp < u.max then
    local bw = 32
    love.graphics.setColor(0, 0, 0, 0.2); love.graphics.rectangle("fill", x - bw / 2, y - 2.5 * cam.s, bw, 4)
    local col = u.side == "left" and { 0.24, 0.39, 0.87 } or { 0.9, 0.28, 0.3 }
    love.graphics.setColor(col)
    love.graphics.rectangle("fill", x - bw / 2, y - 2.5 * cam.s, bw * (u.hp / u.max), 4)
    love.graphics.setColor(1, 1, 1)
  end
end

function love.draw()
  -- 震屏（大招砸地）
  local shx, shy = 0, 0
  if SHAKE > 0 then shx = (love.math.random() * 2 - 1) * SHAKE; shy = (love.math.random() * 2 - 1) * SHAKE end
  love.graphics.push()
  love.graphics.translate(shx, shy)
  -- 地面：向四周多铺 PAD 格，铺满整个窗口（战场内棋盘格 + 场外暗一档）
  local PAD = 7
  for c = -PAD, game.cols - 1 + PAD do
    for r = -PAD, game.rows - 1 + PAD do
      local inPlay = c >= 0 and c < game.cols and r >= 0 and r < game.rows
      if not inPlay then
        love.graphics.setColor(0.70, 0.77, 0.66)
      elseif (c + r) % 2 == 0 then
        love.graphics.setColor(0.84, 0.91, 0.79)
      else
        love.graphics.setColor(0.80, 0.87, 0.75)
      end
      local q = { { c, r }, { c + 1, r }, { c + 1, r + 1 }, { c, r + 1 } }
      local pts = {}
      for _, p in ipairs(q) do local X, Y = sx(p[1], p[2]); pts[#pts + 1] = X; pts[#pts + 1] = Y end
      love.graphics.polygon("fill", pts)
    end
  end
  -- 战场网格线
  love.graphics.setColor(0.62, 0.67, 0.58)
  for c = 0, game.cols do local x1, y1 = sx(c, 0); local x2, y2 = sx(c, game.rows); love.graphics.line(x1, y1, x2, y2) end
  for r = 0, game.rows do local x1, y1 = sx(0, r); local x2, y2 = sx(game.cols, r); love.graphics.line(x1, y1, x2, y2) end
  love.graphics.setColor(1, 1, 1)

  -- 城堡
  for _, s in ipairs({ { true, "castle_blue" }, { false, "castle_red" } }) do
    local img = SPR[s[2]]
    if img then
      local bx = s[1] and -0.4 or game.cols - 0.6
      local X, Y = sx(bx, game.rows / 2)
      local h = 3.0 * cam.s
      local w = h * img:getWidth() / img:getHeight()
      love.graphics.draw(img, X - w / 2, Y - h, 0, w / img:getWidth(), h / img:getHeight())
    end
  end

  -- 单位（按深度）
  local us = {}
  for _, u in ipairs(game.units) do us[#us + 1] = u end
  table.sort(us, function(a, b) return (a.x + a.lane) < (b.x + b.lane) end)
  for _, u in ipairs(us) do drawUnit(u) end

  -- 飘伤害数字
  for _, p in ipairs(POPS) do
    local a = 1 - p.t / 0.9
    love.graphics.setColor(1, 0.28, 0.22, a)
    love.graphics.print("-" .. p.val, p.x - 8, p.y - p.t * 44)
  end
  love.graphics.setColor(1, 1, 1)

  -- 大招特效：蓄力金晕 → 冲击环 + 放射光 + 火花
  if ULT_FX then
    local p = ULT_FX.t / ULT_FX.life
    local cx, cy, R = ULT_FX.x, ULT_FX.y, 9 * cam.s
    if p < 0.45 then
      local q = p / 0.45
      for k = 1, 4 do
        local a = 0.22 * (1 - k / 5) * q
        love.graphics.setColor(1, 0.82, 0.32, a)
        love.graphics.ellipse("fill", cx, cy, (2.4 - k * 0.5) * cam.s * q, (2.4 - k * 0.5) * cam.s * q * FY)
      end
      love.graphics.setColor(1, 0.95, 0.7, q); love.graphics.setLineWidth(3)
      for k = 1, 6 do
        local ang = k / 6 * 6.283 + p * 6
        love.graphics.line(cx, cy - 2 * cam.s, cx + math.cos(ang) * 1.2 * cam.s * q, cy - 2 * cam.s + math.sin(ang) * 1.2 * cam.s * FY * q)
      end
      love.graphics.setColor(1, 1, 1); love.graphics.setLineWidth(1)
    else
      local q = (p - 0.45) / 0.55
      love.graphics.setColor(1, 0.85, 0.4, 0.35 * (1 - q))
      love.graphics.ellipse("fill", cx, cy, (0.3 + q) * R * 0.6, (0.3 + q) * R * 0.6 * FY)
      for k = 0, 2 do
        local rr = q + k * 0.22
        if rr <= 1.05 then
          local aa = 0.75 * (1 - rr)
          love.graphics.setColor(1, 0.9, 0.5, aa); love.graphics.setLineWidth(10 * (1 - rr) + 2)
          love.graphics.ellipse("line", cx, cy, rr * R, rr * R * FY)
        end
      end
      love.graphics.setLineWidth(3)
      for a = 0, 11 do
        local ang = a / 12 * 6.283
        love.graphics.setColor(1, 0.95, 0.6, 0.6 * (1 - q))
        love.graphics.line(cx + math.cos(ang) * 0.2 * R, cy + math.sin(ang) * 0.2 * R * FY,
                           cx + math.cos(ang) * (0.4 + q) * R, cy + math.sin(ang) * (0.4 + q) * R * FY)
      end
      love.graphics.setColor(1, 1, 1); love.graphics.setLineWidth(1)
      for _, s in ipairs(ULT_FX.sparks) do
        local dd = q * s.s * R * 0.6
        love.graphics.setColor(1, 0.8, 0.35, 0.9 * (1 - q))
        love.graphics.circle("fill", cx + s.dx * dd, cy + s.dy * dd, 3 * (1 - q) + 1)
      end
      love.graphics.setColor(1, 1, 1)
    end
  end

  love.graphics.pop()

  -- 全屏闪光（不随震屏）
  if FLASH_T > 0 then
    love.graphics.setColor(1, 1, 0.92, FLASH_T / 0.3 * 0.7)
    local w, hh = love.graphics.getDimensions()
    love.graphics.rectangle("fill", 0, 0, w, hh)
    love.graphics.setColor(1, 1, 1)
  end

  -- HUD
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.print(string.format("资源 %.0f   波次 %d   我方 %d / 敌方 %d", game.resource, game.wave, game.bases.left.hp, game.bases.right.hp), 12, 10)
  love.graphics.print("1 剑士  2 弓手  3 法师  ·  点左半场布兵  ·  空格 大招  ·  W 旋斩  ·  R 重开", 12, 32)
  if game.over then
    love.graphics.print(game.winner == "left" and "我方胜利！" or "基地失守…", 12, 60)
  end
  love.graphics.setColor(1, 1, 1)
end
