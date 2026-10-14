-- 水晶方块 Tetris —— LÖVE 运行时
-- 方块素材：Nano Banana 出的 q 版玻璃水晶块（同一参考图 → 一致），见 ../README
-- 运行：love ~/iso_flutter/game/tetris
local root = love.filesystem.getSource()

local function loadImage(path, mip)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a"); f:close()
  local ok, img = pcall(love.graphics.newImage, love.filesystem.newFileData(d, "b.png"), mip and { mipmaps = true } or nil)
  return ok and img or nil
end

local COLS, ROWS = 10, 20
local TYPES = { "i", "o", "t", "s", "z", "j", "l" }
local SHAPES = {
  i = { { 0, 0, 0, 0 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
  o = { { 1, 1 }, { 1, 1 } },
  t = { { 0, 1, 0 }, { 1, 1, 1 }, { 0, 0, 0 } },
  s = { { 0, 1, 1 }, { 1, 1, 0 }, { 0, 0, 0 } },
  z = { { 1, 1, 0 }, { 0, 1, 1 }, { 0, 0, 0 } },
  j = { { 1, 0, 0 }, { 1, 1, 1 }, { 0, 0, 0 } },
  l = { { 0, 0, 1 }, { 1, 1, 1 }, { 0, 0, 0 } },
}
local COL = { i = { .3, .85, .95 }, o = { .98, .82, .25 }, t = { .72, .4, .95 }, s = { .35, .9, .45 },
              z = { .95, .3, .35 }, j = { .35, .6, .98 }, l = { .98, .6, .2 } }

local BLK = {}
local font

local board, cur, nextType, bag
local score, lines, level, over, paused
local fallT, fallInterval
local lockFx, flashes, parts, shake, dropTrail, lineFlash

local function rnd() return love.math.random(1, #bag) end
local function refillBag()
  bag = {}
  for _, t in ipairs(TYPES) do bag[#bag + 1] = t end
  for i = #bag, 2, -1 do local j = love.math.random(i); bag[i], bag[j] = bag[j], bag[i] end
end
local function nextFromBag()
  if #bag == 0 then refillBag() end
  return table.remove(bag)
end

local function emptyBoard()
  board = {}
  for r = 1, ROWS do board[r] = {} end
end

local function collide(m, ox, oy)
  for r = 1, #m do for c = 1, #m[r] do
    if m[r][c] == 1 then
      local x, y = ox + c - 1, oy + r - 1
      if x < 1 or x > COLS or y > ROWS then return true end
      if y >= 1 and board[y][x] then return true end
    end
  end end
  return false
end

local function spawn()
  local t = nextType or nextFromBag()
  nextType = nextFromBag()
  local src = SHAPES[t]
  local m = {}
  for i = 1, #src do m[i] = {}; for j = 1, #src[i] do m[i][j] = src[i][j] end end
  cur = { t = t, m = m, x = math.floor((COLS - #m[1]) / 2) + 1, y = 1 }
  if collide(cur.m, cur.x, cur.y) then over = true end
end

local function rotCW(m)
  local n = #m; local o = {}
  for r = 1, n do o[r] = {}; for c = 1, n do o[r][c] = m[n - c + 1][r] end end
  return o
end

local function tryRotate()
  local m = rotCW(cur.m)
  for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
    if not collide(m, cur.x + dx, cur.y) then cur.m = m; cur.x = cur.x + dx; return end
  end
end

local function lockFlashCell(x, y) lockFx[y][x] = 0.18 end

local function lock()
  for r = 1, #cur.m do for c = 1, #cur.m[r] do
    if cur.m[r][c] == 1 then
      local x, y = cur.x + c - 1, cur.y + r - 1
      if y >= 1 then board[y][x] = cur.t; lockFlashCell(x, y) end
    end
  end end
  -- 消行
  local cleared = {}
  for y = 1, ROWS do
    local full = true
    for x = 1, COLS do if not board[y][x] then full = false; break end end
    if full then cleared[#cleared + 1] = y end
  end
  if #cleared > 0 then
    -- 闪光 + 碎晶粒子
    for _, y in ipairs(cleared) do
      flashes[#flashes + 1] = { y = y, t = 0, life = 0.35 }
      for x = 1, COLS do
        for k = 1, 2 do
          parts[#parts + 1] = {
            t = board[y][x] or "i", gx = x + 0.5, gy = y + 0.5,
            vx = (love.math.random() - 0.5) * 8, vy = -love.math.random() * 7 - 2,
            rot = love.math.random() * 6.28, vr = (love.math.random() - 0.5) * 12,
            s = 0.55 + love.math.random() * 0.4, life = 0.7 + love.math.random() * 0.35, age = 0,
          }
        end
      end
    end
    lineFlash = 0.4
    -- 下移
    table.sort(cleared)
    for i = #cleared, 1, -1 do
      table.remove(board, cleared[i]); table.insert(board, 1, {})
    end
    local n = #cleared
    score = score + ({ 0, 100, 300, 500, 800 })[n] * level
    lines = lines + n
    level = 1 + math.floor(lines / 10)
    fallInterval = math.max(0.06, 0.8 - (level - 1) * 0.07)
    shake = math.min(10, 4 + n * 2)
  end
  spawn()
end

local function reset()
  emptyBoard()
  lockFx = {}
  for r = 1, ROWS do lockFx[r] = {} end
  bag = {}; refillBag(); nextType = nextFromBag()
  score, lines, level, over, paused = 0, 0, 1, false, false
  fallT, fallInterval = 0, 0.8
  flashes, parts, dropTrail = {}, {}, {}
  shake, lineFlash = 0, 0
  spawn()
end

local function ghostY()
  local y = cur.y
  while not collide(cur.m, cur.x, y + 1) do y = y + 1 end
  return y
end

local function hardDrop()
  local gy = ghostY()
  local d = gy - cur.y
  for i = 1, math.min(d, 8) do dropTrail[#dropTrail + 1] = { x = cur.x, y = cur.y + i, m = cur.m, t = cur.t, life = 0.25, age = 0 } end
  cur.y = gy
  shake = math.max(shake, math.min(8, d * 0.8))
  lock()
end

function love.load()
  love.graphics.setBackgroundColor(0.06, 0.07, 0.12)
  local ok, f = pcall(love.graphics.newFont, 18)
  if ok then font = f end
  -- 中文字体
  local fp = os.getenv("HOME") .. "/.local/share/fonts/TsangerJinKai/TsangerJinKai02-W05.ttf"
  local h = io.open(fp, "rb")
  if h then
    local bytes = h:read("*a"); h:close()
    local ok2, cf = pcall(love.graphics.newFont, love.filesystem.newFileData(bytes, "cjk.ttf"), 18)
    if ok2 then font = cf end
  end
  if font then love.graphics.setFont(font) end
  for _, t in ipairs(TYPES) do
    local img = loadImage(root .. "/assets/blocks/" .. t .. ".png", true)
    if img then img:setFilter("linear", "linear"); img:setMipmapFilter("linear") end
    BLK[t] = img
  end
  reset()
end

function love.keypressed(k)
  if k == "r" then reset(); return end
  if over then return end
  if k == "p" then paused = not paused; return end
  if paused then return end
  if k == "left" then if not collide(cur.m, cur.x - 1, cur.y) then cur.x = cur.x - 1 end
  elseif k == "right" then if not collide(cur.m, cur.x + 1, cur.y) then cur.x = cur.x + 1 end
  elseif k == "down" then if not collide(cur.m, cur.x, cur.y + 1) then cur.y = cur.y + 1; score = score + 1 end
  elseif k == "up" or k == "x" then tryRotate()
  elseif k == "space" then hardDrop()
  end
end

function love.update(d)
  for i = #parts, 1, -1 do
    local p = parts[i]; p.age = p.age + d
    p.gx = p.gx + p.vx * d; p.vy = p.vy + 40 * d; p.gy = p.gy + p.vy * d; p.rot = p.rot + p.vr * d
    if p.age > p.life then table.remove(parts, i) end
  end
  for i = #flashes, 1, -1 do flashes[i].t = flashes[i].t + d; if flashes[i].t > flashes[i].life then table.remove(flashes, i) end end
  for i = #dropTrail, 1, -1 do dropTrail[i].age = dropTrail[i].age + d; if dropTrail[i].age > dropTrail[i].life then table.remove(dropTrail, i) end end
  for r = 1, ROWS do for x = 1, COLS do if lockFx[r][x] then lockFx[r][x] = lockFx[r][x] - d; if lockFx[r][x] <= 0 then lockFx[r][x] = nil end end end end
  shake = math.max(0, shake - d * 40)
  lineFlash = math.max(0, lineFlash - d)
  if over or paused then return end
  fallT = fallT + d
  if fallT >= fallInterval then
    fallT = fallT - fallInterval
    if not collide(cur.m, cur.x, cur.y + 1) then cur.y = cur.y + 1 else lock() end
  end
end

-- 布局
local function layout()
  local w, h = love.graphics.getDimensions()
  local panel = 170
  local cell = math.min((h - 60) / ROWS, (w - panel - 60) / COLS)
  local bw, bh = cell * COLS, cell * ROWS
  local bx = (w - panel - bw) / 2
  local by = (h - bh) / 2
  return cell, bx, by, w, h
end

local function drawBlock(t, px, py, sz, alpha, rot)
  local img = BLK[t]
  love.graphics.setColor(1, 1, 1, alpha or 1)
  if img then
    local iw, ih = img:getDimensions()
    love.graphics.draw(img, px + sz / 2, py + sz / 2, rot or 0, sz / iw, sz / ih, iw / 2, ih / 2)
  else
    local c = COL[t] or { 1, 1, 1 }
    love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
    love.graphics.rectangle("fill", px + 1, py + 1, sz - 2, sz - 2, 4, 4)
  end
  love.graphics.setColor(1, 1, 1)
end

function love.draw()
  local cell, bx, by, w, h = layout()
  local shx, shy = 0, 0
  if shake > 0 then shx = (love.math.random() * 2 - 1) * shake; shy = (love.math.random() * 2 - 1) * shake end
  love.graphics.push()
  love.graphics.translate(shx, shy)

  -- 棋盘背景
  love.graphics.setColor(0.10, 0.12, 0.20)
  love.graphics.rectangle("fill", bx, by, cell * COLS, cell * ROWS, 8, 8)
  love.graphics.setColor(0.16, 0.19, 0.30)
  for r = 0, ROWS do love.graphics.line(bx, by + r * cell, bx + cell * COLS, by + r * cell) end
  for c = 0, COLS do love.graphics.line(bx + c * cell, by, bx + c * cell, by + cell * ROWS) end
  love.graphics.setColor(0.35, 0.5, 0.9, 0.8)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", bx, by, cell * COLS, cell * ROWS, 8, 8)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)

  local function cx(x) return bx + (x - 1) * cell end
  local function cy(y) return by + (y - 1) * cell end

  -- 已落方块
  for y = 1, ROWS do for x = 1, COLS do
    if board[y][x] then
      drawBlock(board[y][x], cx(x), cy(y), cell, 1)
      if lockFx[y][x] then
        love.graphics.setColor(1, 1, 1, lockFx[y][x] / 0.18 * 0.7)
        love.graphics.rectangle("fill", cx(x), cy(y), cell, cell, 4, 4)
        love.graphics.setColor(1, 1, 1)
      end
    end
  end end

  -- 消行闪白
  for _, f in ipairs(flashes) do
    local a = 1 - f.t / f.life
    love.graphics.setColor(1, 1, 1, a * 0.9)
    love.graphics.rectangle("fill", bx, cy(f.y), cell * COLS, cell)
  end
  love.graphics.setColor(1, 1, 1)

  if not over then
    -- ghost
    local gy = ghostY()
    for r = 1, #cur.m do for c = 1, #cur.m[r] do
      if cur.m[r][c] == 1 then drawBlock(cur.t, cx(cur.x + c - 1), cy(gy + r - 1), cell, 0.22) end
    end end
    -- 当前块
    for r = 1, #cur.m do for c = 1, #cur.m[r] do
      if cur.m[r][c] == 1 then drawBlock(cur.t, cx(cur.x + c - 1), cy(cur.y + r - 1), cell, 1) end
    end end
  end

  -- 掉落拖影
  for _, d in ipairs(dropTrail) do
    local a = 1 - d.age / d.life
    for r = 1, #d.m do for c = 1, #d.m[r] do
      if d.m[r][c] == 1 then drawBlock(d.t, cx(d.x + c - 1), cy(d.y + r - 1), cell, a * 0.25) end
    end end
  end

  -- 碎晶粒子
  for _, p in ipairs(parts) do
    local a = 1 - p.age / p.life
    local sz = cell * p.s
    drawBlock(p.t, bx + (p.gx - 1) * cell - (sz - cell) / 2, by + (p.gy - 1) * cell - (sz - cell) / 2, sz, a, p.rot)
  end
  love.graphics.setColor(1, 1, 1)

  love.graphics.pop()

  -- 侧栏
  local px = bx + cell * COLS + 26
  local py = by + 6
  love.graphics.setColor(0.85, 0.9, 1)
  love.graphics.print("分数", px, py); py = py + 22
  love.graphics.setColor(1, 1, 1); love.graphics.print(string.format("%d", score), px, py); py = py + 40
  love.graphics.setColor(0.85, 0.9, 1); love.graphics.print("消行", px, py); py = py + 22
  love.graphics.setColor(1, 1, 1); love.graphics.print(string.format("%d", lines), px, py); py = py + 40
  love.graphics.setColor(0.85, 0.9, 1); love.graphics.print("等级", px, py); py = py + 22
  love.graphics.setColor(1, 1, 1); love.graphics.print(string.format("%d", level), px, py); py = py + 46

  love.graphics.setColor(0.85, 0.9, 1); love.graphics.print("下一个", px, py); py = py + 30
  -- next 预览
  local nm = SHAPES[nextType]
  local ncell = cell * 0.7
  for r = 1, #nm do for c = 1, #nm[r] do
    if nm[r][c] == 1 then drawBlock(nextType, px + (c - 1) * ncell, py + (r - 1) * ncell, ncell, 1) end
  end end

  -- 提示
  love.graphics.setColor(0.6, 0.66, 0.8)
  love.graphics.print("← → 移动   ↑ 旋转", px, h - 120)
  love.graphics.print("↓ 软降   空格 瞬降", px, h - 96)
  love.graphics.print("P 暂停   R 重开", px, h - 72)

  -- 全屏消行闪
  if lineFlash > 0 then
    love.graphics.setColor(1, 1, 1, lineFlash * 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1)
  end

  if paused then
    love.graphics.setColor(0, 0, 0, 0.5); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1); love.graphics.printf("已暂停", 0, h / 2 - 20, w, "center")
  end
  if over then
    love.graphics.setColor(0, 0, 0, 0.6); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("游戏结束", 0, h / 2 - 40, w, "center")
    love.graphics.printf(string.format("分数 %d", score), 0, h / 2, w, "center")
    love.graphics.printf("按 R 重开", 0, h / 2 + 40, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end
