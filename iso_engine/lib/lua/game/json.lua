-- json.lua —— 极简 JSON 编码（供 state 导出，纯 Lua）
local M = {}

local function esc(s) return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end

function M.encode(v)
  local t = type(v)
  if t == "string" then return esc(v)
  elseif t == "number" then return v == math.floor(v) and string.format("%d", v) or string.format("%.4f", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    if #v > 0 then
      local p = {}
      for i = 1, #v do p[i] = M.encode(v[i]) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local p = {}
    for _, k in ipairs(keys) do p[#p + 1] = esc(tostring(k)) .. ":" .. M.encode(v[k]) end
    return "{" .. table.concat(p, ",") .. "}"
  end
  return "null"
end

return M
