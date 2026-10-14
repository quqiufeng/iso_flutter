-- LÖVE 集成：等距「兵线对推」。
-- 复用：iso_engine/lib/lua/game/battle.lua（纯 Lua Sim）+ app/assets/sprites/*.png（img.sh 生成）
-- 运行：love ~/iso_flutter/game/love
local root = love.filesystem.getSource():gsub("/game/love$", "")

-- Lua 模块（标准 require 走真实文件系统）
package.path = root .. "/iso_engine/lib/lua/game/?.lua;" .. package.path

local battle = require("battle")

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
function loadImage(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, img = pcall(love.graphics.newImage, love.filesystem.newFileData(data, "sprite.png"))
  return ok and img or nil
end

-- 等距投影（地面 x,y → 屏幕相对）
local CA, SA, SE, CE, U = 0.70710678, 0.70710678, 0.5, 0.86602540, 1.2649110640673518
local function iso(x, y) return (x * CA - y * SA) * U, (x * SA + y * CA) * SE * U end

local cam = { ox = 0, oy = 0, s = 40 }
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
  local span = (cols + rows) * CA * U
  cam.s = math.min(w * 0.92 / span, h * 0.92 / (span * 0.6))
  cam.ox = w / 2 - ((cols - 1) / 2 * CA - (rows - 1) / 2 * SA) * U * cam.s
  cam.oy = h / 2 - ((cols - 1) / 2 * SA + (rows - 1) / 2 * CA) * SE * U * cam.s + cam.s * 1.2
end

local sel = "sword"
local TYPESEL = { ["1"] = "sword", ["2"] = "archer", ["3"] = "mage" }
-- 兵种 → 分件组装角色（char.sh 生成；可换武器 + 染色）
local CHARMAP = { sword = "u1", archer = "u2", mage = "u3", goblin = "e1", shooter = "e2", ogre = "e3" }

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
  for _, nm in ipairs({ "u1", "u2", "u3", "e1", "e2", "e3" }) do
    loadAnim(nm, "walk", 12); loadAnim(nm, "idle", 12); loadAnim(nm, "hit", 6); loadAnim(nm, "death", 12)
  end
  game = battle.new()
  fit()
end

function love.update(d)
  if game.over then return end
  game:step(d)
end

function love.keypressed(k)
  if TYPESEL[k] then sel = TYPESEL[k] end
  if k == "r" then game = battle.new(); fit() end
end

function love.mousepressed(mx, my, btn)
  if btn ~= 1 or game.over then return end
  -- 屏幕 → 地面（逆等距）
  local a = (mx - cam.ox) / (cam.s * U)
  local b = (my - cam.oy) / (cam.s * U * SE)
  local gx = a * CA + b * SA
  local gy = -a * SA + b * CA
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
  -- 地面网格
  love.graphics.setColor(0.81, 0.88, 0.77)
  for c = 0, game.cols - 1 do
    for r = 0, game.rows - 1 do
      local pts = {}
      local q = { { c, r }, { c + 1, r }, { c + 1, r + 1 }, { c, r + 1 } }
      for _, p in ipairs(q) do local X, Y = sx(p[1], p[2]); pts[#pts + 1] = X; pts[#pts + 1] = Y end
      love.graphics.polygon("fill", pts)
    end
  end
  love.graphics.setColor(0.6, 0.65, 0.57)
  for c = 0, game.cols do local x1, y1 = sx(c, 0); local x2, y2 = sx(c, game.rows); love.graphics.line(x1, y1, x2, y2) end
  for r = 0, game.rows do local x1, y1 = sx(0, r); local x2, y2 = sx(game.cols, r); love.graphics.line(x1, y1, x2, y2) end
  love.graphics.setColor(1, 1, 1)

  -- 城堡
  for _, s in ipairs({ { true, "castle_blue" }, { false, "castle_red" } }) do
    local img = SPR[s[2]]
    if img then
      local bx = s[1] and -0.45 or game.cols - 0.55
      local X, Y = sx(bx + 0.5, game.rows / 2)
      local h = 6.2 * cam.s
      local w = h * img:getWidth() / img:getHeight()
      love.graphics.draw(img, X - w / 2, Y - h, 0, w / img:getWidth(), h / img:getHeight())
    end
  end

  -- 单位（按深度）
  local us = {}
  for _, u in ipairs(game.units) do us[#us + 1] = u end
  table.sort(us, function(a, b) return (a.x + a.lane) < (b.x + b.lane) end)
  for _, u in ipairs(us) do drawUnit(u) end

  -- HUD
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.print(string.format("资源 %.0f   波次 %d   我方 %d / 敌方 %d", game.resource, game.wave, game.bases.left.hp, game.bases.right.hp), 12, 10)
  love.graphics.print("1 剑士  2 弓手  3 法师   ·   点左半场布兵   ·   R 重开", 12, 32)
  if game.over then
    love.graphics.print(game.winner == "left" and "我方胜利！" or "基地失守…", 12, 60)
  end
  love.graphics.setColor(1, 1, 1)
end
