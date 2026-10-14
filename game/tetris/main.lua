-- 水晶方块 Tetris —— LÖVE 运行时（渲染/输入/特效）
-- 逻辑在 sim.lua（纯 Lua 仿真：确定性/headless/可回放/带落子记忆）；本文件只消费 state()/events。
-- 运行：love ~/iso_flutter/game/tetris
local sim = require("sim")

local COLS, ROWS = sim.COLS, sim.ROWS
local TYPES, SHAPES = sim.TYPES, sim.SHAPES

local function loadImage(path, mip)
  if not love.filesystem.getInfo(path) then return nil end
  local ok, img = pcall(love.graphics.newImage, path, mip and { mipmaps = true } or nil)
  return ok and img or nil
end

-- ===== 截图钩子 =====（消行动画触发时自动连拍；CAPTURE_DIR 启用）
local CAP_DIR = os.getenv("CAPTURE_DIR")
local CAP_FRAMES = tonumber(os.getenv("CAPTURE_FRAMES") or "36")
local AUTO = os.getenv("AUTO")                     -- 设了=AUTO 让 AI 自动玩（无人值守抓消行）
local capLeft, capName, capStarted = 0, "cap", false
local aiT = 0
local function capBegin(name)
  if not CAP_DIR then return end
  capName, capLeft = name or "cap", CAP_FRAMES
  if not capStarted then os.execute("mkdir -p '" .. CAP_DIR .. "'"); capStarted = true end
end
local function capFrame()
  if capLeft <= 0 or not CAP_DIR then return end
  local n = CAP_FRAMES - capLeft
  capLeft = capLeft - 1
  love.graphics.captureScreenshot(function(img)
    local fd = img:encode("png")
    local f = io.open(CAP_DIR .. "/" .. capName .. string.format("_%03d.png", n), "wb")
    if f then f:write(fd:getString()); f:close() end
  end)
end

-- 中国传统色（见 /opt/my-agent/operator/CHINESE-COLORS.md）
local function hex(s)
  return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255 }
end
local THEME = {
  bg     = hex("#EAF3DC"),      -- 霜地（嫩绿宣纸）
  board  = hex("#F5FAEC"),      -- 嫩菊绿（棋盘底）
  grid   = hex("#D3E1BB"),      -- 姚黄（浅网格）
  border = hex("#7BC092"),      -- 梅子青（浅绿边框）
  ink    = hex("#1D1B1C"),      -- 墨色（主文字）
  dim    = hex("#5B6B4F"),      -- 次文字
  btn    = hex("#F5FAEC"),
  btnOn  = hex("#D6E6BE"),
}
local COL = {                   -- 方块：中国传统色（柔和养眼）
  i = hex("#57AECB"), o = hex("#EFC53B"), t = hex("#9B8AE8"), s = hex("#4CAF6E"),
  z = hex("#CE5A57"), j = hex("#3E77AE"), l = hex("#CE8246"),
}

local BLK = {}
local font

-- 当前局（纯 Lua 仿真）
local game

-- juice 状态
local lockFx, flashes, parts, shake, dropTrail, lineFlash

local function resetJuice()
  lockFx = {}
  for r = 1, ROWS do lockFx[r] = {} end
  flashes, parts, dropTrail = {}, {}, {}
  shake, lineFlash = 0, 0
end

local function newGame(seed)
  game = sim.new({ seed = seed or os.time() })
  resetJuice()
end

-- ===== 文件桥（agent 接口驱动：读状态 / 写指令，无需截图）=====
-- 游戏每帧把 state 写成 JSON，agent 读它（含当前块与后续方块序列 queue）；
-- agent 写命令文件，游戏读取并执行。默认目录为 app 私有外部目录（adb 可读写）。
local BRIDGE = os.getenv("BRIDGE_DIR")
if not BRIDGE and love.system and love.system.getOS() == "Android" then
  BRIDGE = "/sdcard/Android/data/org.love2d.android/files"
end
local lastCmd, bridgeFrame = nil, 0

local function bridgeWrite()
  if not BRIDGE then return end
  local s = game:state()
  local rows = {}
  for r = 1, ROWS do
    local row = {}
    for c = 1, COLS do row[c] = s.board[r][c] or "." end
    rows[r] = table.concat(row)
  end
  local obj = {
    tick = s.tick, over = s.over, paused = s.paused,
    score = s.score, lines = s.lines, level = s.level, locks = s.locks,
    cur = s.cur and { t = s.cur.t, x = s.cur.x, y = s.cur.y, m = s.cur.m } or false,
    next = s.next, queue = s.queue, board = rows,
  }
  local f = io.open(BRIDGE .. "/tetris_state.json", "wb")
  if f then f:write(sim.encode(obj)); f:close() end
end

local function bridgeRead()
  if not BRIDGE then return end
  local f = io.open(BRIDGE .. "/tetris_cmd.txt", "rb")
  if not f then return end
  local data = f:read("*a"); f:close()
  if data == lastCmd then return end
  lastCmd = data
  for line in data:gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "restart" then newGame()
    elseif line == "pause" then game:act("pause")
    elseif line == "hold" then game.fallInterval = 1e9          -- 冻结重力（agent 完全掌控）
    elseif line == "release" then game.fallInterval = math.max(0.06, 0.8 - (game.level - 1) * 0.07)
    elseif line:match("^act:") then game:act(line:sub(5)) end
  end
end

-- ===== 触屏 / 鼠标 控制（手机无键盘）=====
local FONT_PATH = "assets/fonts/TsangerJinKai02-subset.ttf"
local function newFont(sz)
  if love.filesystem.getInfo(FONT_PATH) then
    local ok, f = pcall(love.graphics.newFont, FONT_PATH, sz)
    if ok then return f end
  end
  local ok, f = pcall(love.graphics.newFont, sz)
  return ok and f or nil
end

local BTN = {}                              -- 每帧可点的按钮矩形
local held = {}                             -- 按住的按钮 → { t, nextAt }（连发）
local REPEAT_DELAY, REPEAT_GAP = 0.20, 0.06

local function uiScale()
  local h = love.graphics.getHeight()
  return math.max(0.85, math.min(h / 720, 2.4))
end
local function ctrlH() return 58 * uiScale() end

local function moveX(dx)
  if not game.over and not game.paused then game:act(dx < 0 and "left" or "right") end
end

local function buildButtons()
  BTN = {}
  local w, h = love.graphics.getDimensions()
  local s = uiScale()
  local labels = { { "left", "←" }, { "right", "→" }, { "rotate", "" }, { "hard", "" } }
  local n = #labels
  local gap = 8 * s
  local bh = ctrlH() - 20 * s
  local bw = math.min(bh * 1.3, 96 * s, (w - (n + 1) * gap) / n)
  local total = n * bw + (n - 1) * gap
  local x0 = (w - total) / 2
  local y = h - ctrlH() + (ctrlH() - bh) / 2
  for i, lb in ipairs(labels) do
    BTN[#BTN + 1] = { id = lb[1], x = x0 + (i - 1) * (bw + gap), y = y, w = bw, h = bh,
                      label = lb[2], font = newFont(math.floor(30 * s)) }
  end
  -- 暂停 / 重开（矮横条，别太高）
  local pw, ph = 62 * s, 32 * s
  BTN[#BTN + 1] = { id = "pause",   x = w - pw * 2 - 20 * s, y = 8 * s, w = pw, h = ph, label = "暂停", font = newFont(math.floor(16 * s)) }
  BTN[#BTN + 1] = { id = "restart", x = w - pw - 12 * s,      y = 8 * s, w = pw, h = ph, label = "重开", font = newFont(math.floor(16 * s)) }
end

local function buttonAt(x, y)
  for _, b in ipairs(BTN) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then return b end
  end
end

local function pressBtn(id)
  if id == "restart" then newGame()
  elseif id == "pause" then game:act("pause")
  elseif not game.over and not game.paused then
    if id == "left" then game:act("left")
    elseif id == "right" then game:act("right")
    elseif id == "rotate" then game:act("rotate")
    elseif id == "hard" then game:act("hard") end
  end
end

local function stepHeld(d)
  for id, st in pairs(held) do
    if id == "left" or id == "right" then
      st.t = st.t + d
      if st.t >= st.nextAt then
        moveX(id == "left" and -1 or 1)
        st.nextAt = st.nextAt + REPEAT_GAP
      end
    end
  end
end

local function drawButtons()
  local s = uiScale()
  for _, b in ipairs(BTN) do
    local on = held[b.id] ~= nil
    local bc = on and THEME.btnOn or THEME.btn
    love.graphics.setColor(bc[1], bc[2], bc[3], on and 0.95 or 0.9)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 10 * s, 10 * s)
    love.graphics.setColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.9)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 10 * s, 10 * s)
    local cx, cy = b.x + b.w / 2, b.y + b.h / 2
    if b.id == "rotate" then
      local r = b.h * 0.26
      local lw = math.max(2, 4 * s)
      love.graphics.setColor(THEME.ink)
      love.graphics.setLineWidth(lw)
      local a0, a1 = -2.3, 1.7
      love.graphics.arc("line", "open", cx, cy, r, a0, a1)
      love.graphics.setLineWidth(1)
      local ah = r * 0.55
      local tx, ty = -math.sin(a1), math.cos(a1)
      local nx, ny = math.cos(a1), math.sin(a1)
      local px, py = cx + r * math.cos(a1), cy + r * math.sin(a1)
      love.graphics.polygon("fill",
        px + tx * ah, py + ty * ah,
        px + nx * ah * 0.85, py + ny * ah * 0.85,
        px - nx * ah * 0.85, py - ny * ah * 0.85)
    elseif b.id == "hard" then
      local lw = math.max(2, 4 * s)
      love.graphics.setColor(THEME.ink)
      love.graphics.setLineWidth(lw)
      local w, hh = b.w * 0.22, b.h * 0.20
      for k = 0, 1 do
        local yy = cy - hh * 1.3 + k * hh * 1.5
        love.graphics.line(cx - w, yy, cx, yy + hh, cx + w, yy)
      end
      love.graphics.setLineWidth(1)
    elseif b.font then
      love.graphics.setFont(b.font)
      love.graphics.setColor(THEME.ink)
      local fh = b.font:getHeight()
      love.graphics.printf(b.label, b.x, b.y + (b.h - fh) / 2, b.w, "center")
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function love.resize() buildButtons() end

function love.load()
  love.graphics.setBackgroundColor(THEME.bg)
  font = newFont(math.floor(18 * uiScale()))
  if font then love.graphics.setFont(font) end
  for _, t in ipairs(TYPES) do
    local img = loadImage("assets/blocks/" .. t .. ".png", true)
    if img then img:setFilter("linear", "linear"); img:setMipmapFilter("linear") end
    BLK[t] = img
  end
  newGame()
  buildButtons()
end

function love.keypressed(k)
  if k == "f2" then capBegin("manual"); return end
  if k == "r" then newGame(); return end
  if k == "p" then game:act("pause"); return end
  if game.over or game.paused then return end
  if k == "left" then game:act("left")
  elseif k == "right" then game:act("right")
  elseif k == "down" then game:act("soft")
  elseif k == "up" or k == "x" then game:act("rotate")
  elseif k == "space" then game:act("hard")
  end
end

-- 触摸（Android 会同时产生鼠标事件）/ 鼠标点击控制条
function love.mousepressed(mx, my, btn)
  if btn ~= 1 then return end
  local b = buttonAt(mx, my)
  if b then held[b.id] = { t = 0, nextAt = REPEAT_DELAY }; pressBtn(b.id) end
end
function love.mousereleased() held = {} end

-- ===== 简单 AI（AUTO 无人值守用）：枚举 旋转×落点，按启发式选最优 =====
local function evalOcc(occ)
  local h = {}
  for c = 1, COLS do local v = 0; for r = 1, ROWS do if occ[r][c] then v = ROWS - r + 1; break end end h[c] = v end
  local agg, holes, bump = 0, 0, 0
  for c = 1, COLS do agg = agg + h[c]
    local solid = false
    for r = 1, ROWS do if occ[r][c] then solid = true elseif solid then holes = holes + 1 end end
  end
  for c = 1, COLS - 1 do bump = bump + math.abs(h[c] - h[c + 1]) end
  local lines = 0
  for r = 1, ROWS do local full = true; for c = 1, COLS do if not occ[r][c] then full = false; break end end if full then lines = lines + 1 end end
  return -(0.51 * agg + 0.76 * holes + 0.18 * bump) + 0.76 * lines
end

local function aiBest()
  local best, bm, bx = -1e9, nil, nil
  local cur = game.cur
  local m = cur.m
  for _ = 0, 3 do
    for x = 1, COLS do
      if not game:collide(m, x, cur.y) then
        local y = cur.y
        while not game:collide(m, x, y + 1) do y = y + 1 end
        local occ = {}
        for r = 1, ROWS do occ[r] = {}; for c = 1, COLS do occ[r][c] = game.board[r][c] end end
        local okp = true
        for r = 1, #m do for c = 1, #m[r] do
          if m[r][c] == 1 then
            local yy, xx = y + r - 1, x + c - 1
            if yy < 1 or yy > ROWS or xx < 1 or xx > COLS then okp = false else occ[yy][xx] = true end
          end
        end end
        if okp then local sc = evalOcc(occ); if sc > best then best, bm, bx = sc, m, x end end
      end
    end
    m = sim.rotCW(m)
  end
  return bm, bx
end

-- 消费 Sim 事件流 → 特效/音效/连拍
local function consumeEvents()
  for _, ev in ipairs(game.events) do
    if ev.type == "lock" then
      for _, cell in ipairs(ev.rec.cells) do
        if lockFx[cell.y] then lockFx[cell.y][cell.x] = 0.18 end
      end
    elseif ev.type == "harddrop" then
      for i = 1, math.min(ev.dist, 8) do
        dropTrail[#dropTrail + 1] = { x = ev.x, y = ev.fromY + i, m = ev.m, t = ev.t, life = 0.25, age = 0 }
      end
      shake = math.max(shake, math.min(8, ev.dist * 0.8))
    elseif ev.type == "clear" then
      capBegin("line")                                  -- 消行 → 自动连拍
      for _, y in ipairs(ev.rows) do flashes[#flashes + 1] = { y = y, t = 0, life = 0.35 } end
      for i, y in ipairs(ev.rows) do
        local row = ev.types[i] or {}
        for x = 1, COLS do for k = 1, 2 do
          parts[#parts + 1] = {
            t = row[x] or "i", gx = x + 0.5, gy = y + 0.5,
            vx = (love.math.random() - 0.5) * 8, vy = -love.math.random() * 7 - 2,
            rot = love.math.random() * 6.28, vr = (love.math.random() - 0.5) * 12,
            s = 0.55 + love.math.random() * 0.4, life = 0.7 + love.math.random() * 0.35, age = 0,
          }
        end end
      end
      lineFlash = 0.4
      shake = math.max(shake, math.min(10, 4 + ev.lines * 2))
    end
  end
  game:clearEvents()
end

function love.update(d)
  bridgeRead()
  stepHeld(d)
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
  if game.over or game.paused then
    bridgeFrame = bridgeFrame + 1
    if bridgeFrame % 6 == 0 then bridgeWrite() end
    return
  end
  if AUTO then                                    -- AI 自动玩（无人值守抓消行）
    aiT = aiT - d
    if aiT <= 0 then
      local bm, bx = aiBest()
      if bm and bx then game.cur.m, game.cur.x = bm, bx; game:act("hard") end
      aiT = 0.2
    end
  end
  game:step(d)
  consumeEvents()
  bridgeFrame = bridgeFrame + 1
  if bridgeFrame % 2 == 0 then bridgeWrite() end
end

-- 布局
local function layout()
  local w, h = love.graphics.getDimensions()
  local s = uiScale()
  local ch = ctrlH()
  local pad = 6 * s
  local portrait = h > w * 1.06
  local topH = portrait and (60 * s) or 0
  local panel = portrait and 0 or (150 * s)
  local availW = w - panel - pad * 2
  local availH = h - ch - topH - pad * 2
  local cell = math.min(availH / ROWS, availW / COLS)
  local bw, bh = cell * COLS, cell * ROWS
  local bx = pad + (availW - bw) / 2
  local by = pad + topH + (availH - bh) / 2
  return cell, bx, by, w, h, s, ch, topH, panel, portrait
end

local function drawBlock(t, px, py, sz, alpha, rot)
  local img = BLK[t]
  local c = COL[t] or { 1, 1, 1 }
  love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
  if img then
    local iw, ih = img:getDimensions()
    love.graphics.draw(img, px + sz / 2, py + sz / 2, rot or 0, sz / iw, sz / ih, iw / 2, ih / 2)
  else
    love.graphics.rectangle("fill", px + 1, py + 1, sz - 2, sz - 2, 4, 4)
  end
  love.graphics.setColor(1, 1, 1)
end

function love.draw()
  local cell, bx, by, w, h, s, ch, topH, panel, portrait = layout()
  local shx, shy = 0, 0
  if shake > 0 then shx = (love.math.random() * 2 - 1) * shake; shy = (love.math.random() * 2 - 1) * shake end
  love.graphics.push()
  love.graphics.translate(shx, shy)

  -- 棋盘背景（嫩菊绿底 + 梅子青描边）
  love.graphics.setColor(THEME.board)
  love.graphics.rectangle("fill", bx, by, cell * COLS, cell * ROWS, 8, 8)
  love.graphics.setColor(THEME.grid[1], THEME.grid[2], THEME.grid[3], 0.5)
  love.graphics.setLineWidth(1)
  for r = 0, ROWS do love.graphics.line(bx, by + r * cell, bx + cell * COLS, by + r * cell) end
  for c = 0, COLS do love.graphics.line(bx + c * cell, by, bx + c * cell, by + cell * ROWS) end
  love.graphics.setColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.9)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", bx, by, cell * COLS, cell * ROWS, 8, 8)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)

  local function cx(x) return bx + (x - 1) * cell end
  local function cy(y) return by + (y - 1) * cell end

  -- 已落方块（来自 sim.board）
  local board = game.board
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

  if not game.over and game.cur then
    local cur = game.cur
    local gy = game:ghostY()
    for r = 1, #cur.m do for c = 1, #cur.m[r] do
      if cur.m[r][c] == 1 then drawBlock(cur.t, cx(cur.x + c - 1), cy(gy + r - 1), cell, 0.22) end
    end end
    for r = 1, #cur.m do for c = 1, #cur.m[r] do
      if cur.m[r][c] == 1 then drawBlock(cur.t, cx(cur.x + c - 1), cy(cur.y + r - 1), cell, 1) end
    end end
  end

  -- 掉落拖影
  for _, dd in ipairs(dropTrail) do
    local a = 1 - dd.age / dd.life
    for r = 1, #dd.m do for c = 1, #dd.m[r] do
      if dd.m[r][c] == 1 then drawBlock(dd.t, cx(dd.x + c - 1), cy(dd.y + r - 1), cell, a * 0.25) end
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

  local nm = SHAPES[game.nextType]
  if portrait then
    -- 竖屏：顶部 HUD（只留分数），下一个预览在右上按钮左侧
    local tx, ty = 18 * s, 12 * s
    love.graphics.setColor(THEME.ink)
    love.graphics.print(string.format("分数 %d", game.score), tx, ty)
    local ncell = math.min(cell * 0.38, 10 * s)
    local cols = #nm[1]
    local nx = w - 62 * s * 2 - 36 * s - cols * ncell
    for r = 1, #nm do for c = 1, #nm[r] do
      if nm[r][c] == 1 then drawBlock(game.nextType, nx + (c - 1) * ncell, ty + 4 * s + (r - 1) * ncell, ncell, 1) end
    end end
  else
    -- 横屏/桌面：右侧栏（只留分数 + 下一个预览）
    local px = bx + cell * COLS + 22 * s
    local py = by + 6 * s
    love.graphics.setColor(THEME.ink)
    love.graphics.print(string.format("分数 %d", game.score), px, py); py = py + 40 * s
    local ncell = cell * 0.7
    for r = 1, #nm do for c = 1, #nm[r] do
      if nm[r][c] == 1 then drawBlock(game.nextType, px + (c - 1) * ncell, py + (r - 1) * ncell, ncell, 1) end
    end end
  end

  drawButtons()                                   -- 触屏控制条

  -- 全屏消行闪
  if lineFlash > 0 then
    love.graphics.setColor(1, 1, 1, lineFlash * 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1)
  end

  if game.paused then
    love.graphics.setColor(0, 0, 0, 0.5); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1); love.graphics.printf("已暂停", 0, h / 2 - 20, w, "center")
  end
  if game.over then
    love.graphics.setColor(0, 0, 0, 0.6); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("游戏结束", 0, h / 2 - 40, w, "center")
    love.graphics.printf(string.format("分数 %d", game.score), 0, h / 2, w, "center")
    love.graphics.printf("点右上角重开", 0, h / 2 + 40, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
  capFrame()                                      -- 截图钩子：连拍中
end
