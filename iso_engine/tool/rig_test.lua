-- rig_test.lua —— headless 自测：验证 FK 世界坐标 + 关键帧插值（无需 LÖVE）
-- 运行：luajit iso_engine/tool/rig_test.lua
package.path = (arg[0]:match("^(.*)/tool/") or ".") .. "/lib/lua/?.lua;" .. package.path
local rig = require("rig")

local function part(w, h) return { img = "IMG", w = w, h = h } end
local def = {
  bones = {
    { name = "root" }, { name = "hip", parent = "root", y = -46 },
    { name = "torso", parent = "hip", y = -6 }, { name = "head", parent = "torso", y = -30 },
    { name = "armL", parent = "torso", x = -11, y = 2 }, { name = "armR", parent = "torso", x = 11, y = 2 },
    { name = "legL", parent = "hip", x = -7 }, { name = "legR", parent = "hip", x = 7 },
  },
  slots = {
    { name = "armL", bone = "armL", order = 1, att = part(9, 30), color = { 0.2, 0.28, 0.55 } },
    { name = "legL", bone = "legL", order = 2, att = part(11, 40), color = { 0.15, 0.15, 0.22 } },
    { name = "torso", bone = "torso", order = 3, att = part(26, 36), color = { 0.85, 0.3, 0.28 } },
    { name = "head", bone = "head", order = 4, att = part(26, 26), color = { 0.95, 0.8, 0.68 } },
    { name = "legR", bone = "legR", order = 5, att = part(11, 40), color = { 0.18, 0.18, 0.26 } },
    { name = "armR", bone = "armR", order = 6, att = part(9, 30), color = { 0.24, 0.34, 0.65 } },
  },
  clips = {
    walk = {
      duration = 0.8, loop = true,
      bones = {
        legL = { { t = 0, rot = 0.5 }, { t = 0.4, rot = -0.5 }, { t = 0.8, rot = 0.5 } },
        legR = { { t = 0, rot = -0.5 }, { t = 0.4, rot = 0.5 }, { t = 0.8, rot = -0.5 } },
        armL = { { t = 0, rot = -0.45 }, { t = 0.4, rot = 0.45 }, { t = 0.8, rot = -0.45 } },
        armR = { { t = 0, rot = 0.45 }, { t = 0.4, rot = -0.45 }, { t = 0.8, rot = 0.45 } },
      },
    },
  },
}

local R = rig.new(def)
local pass = true
local function check(name, got, want)
  local ok = math.abs(got - want) < 0.01
  if not ok then pass = false end
  print(string.format("  [%s] %-18s got=%.2f want=%.2f", ok and "ok" or "FAIL", name, got, want))
end

print("== FK（rest/idle，无动画骨骼）==")
R:setClip(nil)
local wm = R:worldMatrices()
check("head.y", wm.head.f, -82)
check("torso.y", wm.torso.f, -52)
check("armL.x", wm.armL.e, -11)

print("== 插值（walk t=0.2：legL 中点，rot 0.5→-0.5）==")
R:setClip("walk", { time = 0.2 })
R:_apply()
check("legL.rot@0.2", R.state.legL.rot, 0)  -- 0.2 是 0→0.4 的中点（inout），中点为 0
check("legL.x 保留", R.state.legL.x, -7)     -- 动画骨也必须保留 rest x
check("torso.y 未动", R.state.torso.y, -6)

print(pass and "\nALL PASS ✅" or "\n有失败 ❌")
os.exit(pass and 0 or 1)
