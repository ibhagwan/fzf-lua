---@diagnostic disable-next-line: unbalanced-assignments
---@type string[], string[], table<string, boolean>
local exported_modules, lazyloaded_modules, exported_wapi = ...

local buf = {}
local write = function(s) buf[#buf + 1] = s end
local flush = function()
  assert(io.open("lua/fzf-lua/types.lua", "w")):write(table.concat(buf, ""))
  buf = {}
end

local mark = vim.pesc("---GENERATED from `make gen`")
for line in io.lines("lua/fzf-lua/types.lua") do
  write(line .. "\n")
  if line:match(mark) then
    break
  end
end
-- generate api typings
write("\n")
for _, v in vim.spairs(exported_modules) do
  write(([[FzfLua.%s = require("fzf-lua.%s")]] .. "\n"):format(v, v))
end
write("\n")
for k, v in vim.spairs(lazyloaded_modules) do
  write(([[FzfLua.%s = require(%q).%s]] .. "\n"):format(k, v[1], v[2]))
end
write("\n")

local obj = vim.system({ "sh", "-c", [[
  emmylua_doc_cli lua/fzf-lua/ --output-format json --output stdout | jq '.types[] | select(.name == "fzf-lua.Win")'
]] }):wait()

---@type EmmyDocTypeClass
local res = vim.json.decode(obj.stdout or "")

---@param m EmmyDocTypeMember
local write_member = function(m)
  if not exported_wapi[m.name] then return end
  write("---@field " .. m.name .. " ")
  if m.is_async then write("async") end
  write("fun(")

  local first = true
  vim.iter(m.params):each(function(p)
    if first then
      first = false
      write(("%s: %s"):format(p.name, p.typ))
    else
      write((", %s: %s"):format(p.name, p.typ))
    end
  end)
  write(")")

  first = true
  vim.iter(m.returns):each(function(r)
    if first then
      first = false
      write(": " .. r.typ)
    else
      write(", " .. r.typ)
    end
  end)
  write("\n")
end

write("---@class fzf-lua.win.api: fzf-lua.Win\n")
vim.iter(res.members):each(write_member)

flush()
