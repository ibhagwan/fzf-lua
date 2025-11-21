local obj = vim.system({ "sh", "-c", [[
  emmylua_doc_cli lua/fzf-lua/ --output-format json --output stdout
]] }):wait()

vim.opt.rtp:append(vim.fn.fnamemodify(debug.getinfo(1, "S").source:gsub("^@", ""), ":h:h:h:p"))
local defaults = require("fzf-lua.defaults").defaults

local res = vim.json.decode(obj.stdout or "")

local tymap = {}
local modmap = {}
vim.iter(res.types):each(function(ty)
  tymap[ty.name] = ty
end)
vim.iter(res.modules):each(function(mod)
  modmap[mod.name] = mod
end)

-- vim.print(vim.tbl_keys(modmap.defaults.file))
-- vim.print(modmap.defaults)

---@param target string
---@param child string
---@return boolean
local function is_ancestor(target, child)
  if child == target then return true end
  for _, base in ipairs(tymap[child].bases or {}) do
    if tymap[base] and tymap[base].name and is_ancestor(target, tymap[base].name) then
      return true
    end
  end
  return false
end

local function is_field_inherit(ty, field_name)
  for _, base in ipairs(ty.bases or {}) do
    local base_ty = tymap[base]
    if base_ty then
      for _, f in ipairs(base_ty.members or {}) do
        if f.name == field_name then
          return true
        end
      end
      if is_field_inherit(base_ty, field_name) then
        return true
      end
    end
  end
  return false
end

local function fix_typ(typ, default)
  if typ == "fzf-lua.profile" then
    assert(tymap[typ].name, "Type not found: " .. typ)
    return fix_typ(tymap[typ].typ, default)
  elseif typ:match("%(.*%)") then
    local ty = typ:sub(2, -2) -- remove parentheses
    local is = vim.iter(vim.split(ty, ",")):all(function(t)
      return t:match([[".-"]])
    end)
    if is then
      return "string[]", typ
    end
  end
  return typ, default
end

local normalize_classname = function(classname)
  return classname:gsub("^fzf%-lua%.config%.", ""):gsub("(%l)(%u)", "%1_%2"):lower()
end

local literal = function(v)
  if type(v) ~= "function" then
    return vim.inspect(v, { newline = "" })
  end
  local info = debug.getinfo(v)
  local file = info.source:sub(2)
  local lnum = info.linedefined
  local end_lnum = info.lastlinedefined
  if lnum > 50000 then return end
  local cnt = 1
  for line in io.lines(file) do
    if cnt >= lnum and cnt <= end_lnum then
      if line:match("^%s*return%s+") then
        return "return " .. line:match("^%s*return%s+(.+)%s*$")
      end
      -- return 'eeeeeeeeeeeeeeeee'
    end
    if cnt > end_lnum then break end
    cnt = cnt + 1
  end
  return ("<function %s:%d>"):format(info.short_src, lnum)
end

local alias = {
  __HLS = "hls",
}

local done = {}

local globals = {
  winopts = true,
  keymap = true,
  actions = true,
}

local make_desc = function(norm, member)
  if type(member.description) == "string" then
    return member.description
  end
  if norm:match("globals.hls.fzf.%w+$") then
  end
end

local concat = function(x, sep)
  local function flatten(y)
    local ret = {}
    for k, v in pairs(y) do
      assert(type(k) == "number", "Expected array-like table")
      if type(v) == "table" then
        vim.list_extend(ret, flatten(v))
      elseif type(v) == "string" then
        ret[#ret + 1] = v
      end
    end
    return ret
  end
  if not x then return "" end
  return table.concat(flatten(x), sep or "\n") .. "\n"
end

local function _member_to_markdown(classname, member, rec)
  local name = alias[member.name] or member.name or "Unknown"
  local typ = member.typ
      or (member.returns and member.returns[1] and member.returns[1].typ)
      or "Unknown"
  local norm = ("%s.%s"):format(normalize_classname(classname), name)
  local default = type(member.literal) == "string" and member.literal or
      literal(vim.tbl_get(defaults, select(2, unpack(vim.split(norm, "%.")))))
  typ, default = fix_typ(typ, default)
  if done[norm] or name:match("^_") or name == "[string]" then return end
  done[norm] = true
  local subclass = tymap[typ] or tymap[typ:match(".*%?")]
  if rec and subclass and subclass.members and #subclass.members > 0 then
    return vim.iter(subclass.members):map(function(sub_member)
      return _member_to_markdown(norm, sub_member, rec + 1)
    end):totable()
  end
  local out = {}
  out[#out + 1] = ("##### %s"):format(norm)
  out[#out + 1] = ""
  out[#out + 1] = ("Type: `%s`, Default: `%s`"):format(typ, default)
  out[#out + 1] = ""
  local desc = make_desc(norm, member)
  if type(desc) == "string" then
    out[#out + 1] = desc
    out[#out + 1] = ""
  end
  return out
end

local member_to_markdown = function(...)
  return concat(_member_to_markdown(...))
end

if _G.arg[1] == "Defaults" then
  local ty = assert(tymap["fzf-lua.config.Defaults"])
  vim.iter(ty.members)
      :each(function(member)
        if (member.name:match("^_")
              and not member.name:match("__HLS"))
            or ((defaults[normalize_classname(member.typ:match("fzf%-lua%.config%.(.*)") or "")]
                or defaults[normalize_classname(member.typ:match("fzf%-lua%.config%.(.-)Base") or "")])
              and not globals[normalize_classname(member.typ:match("fzf%-lua%.config%.(.*)") or "")])
        then
          return
        end
        vim.print(member_to_markdown("globals", member, 1))
      end)
  return
end

-- non global
local ancestor = "fzf-lua.config.Base"
vim.iter(vim.spairs(tymap)):each(function(_, ty)
  -- vim.print(is_ancestor(ancestor, ty.name), ty.bases)
  if not ty.name:match("fzf%-lua%.config%.")
      or ty.name == "fzf-lua.config.Base"
      or ty.name == "fzf-lua.config.Resolved"
      or ty.name == "fzf-lua.config.Defaults"
      or not is_ancestor(ancestor, ty.name)
  then
    return
  end

  if _G.arg[1] and not ty.name:lower():match(_G.arg[1]) then
    return
  end

  vim.iter(ty.members)
      :filter(function(member) return not is_field_inherit(ty, member.name) end)
      :each(function(member)
        if member.name:match("^_") or ((member.typ and member.typ:match("fzf%-lua%.config%."))) then return end
        vim.print(member_to_markdown(ty.name, member))
      end)
end)
-- vim.print(res.types[1])
