local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local Object = require "fzf-lua.class"

-- Our "copy" of the devicons library functions so we can load the library
-- from the headless instance and better support edge cases like multi-part
-- extension names (#1053)

local DevIconsBase = Object:extend()

function DevIconsBase:loaded()
  return self._package_loaded
end

function DevIconsBase:path()
  return self._package_path
end

function DevIconsBase:name()
  return self._name
end

function DevIconsBase:state()
  return self._state
end

function DevIconsBase:set_state(state)
  self._state = state
end

function DevIconsBase:unload()
  self._state = nil
  self._package = nil
  self._package_path = nil
  self._package_loaded = nil
end

local NvimWebDevicons = DevIconsBase:extend()

function NvimWebDevicons:new()
  self._name = "devicons"
  self._package_name = "nvim-web-devicons"
  return self
end

function NvimWebDevicons:load()
  -- limit devicons support to nvim >=0.8, although official support is >=0.7
  -- running setup on 0.7 errs with "W18: Invalid character in group name"
  if not self._package_loaded and utils.__HAS_NVIM_07 then
    self._package_loaded, self._package = pcall(require, self._package_name)
    if self._package_loaded then
      self._package_path = path.parent(path.parent(path.normalize(
        debug.getinfo(self._package.setup, "S").source:gsub("^@", ""))))
    end
  end
  return self._package_loaded
end

function NvimWebDevicons:is_mock()
  return type(self._package_path) == "string"
      and self._package_path:match("mini") ~= nil
end

---@return boolean|nil success
function NvimWebDevicons:load_icons(opts)
  if not self:loaded() then return end

  self._state = vim.tbl_deep_extend("force", self._state or {}, {
    icon_padding = type(opts.icon_padding) == "string" and opts.icon_padding or nil,
    dir_icon = vim.tbl_extend("force", { icon = "", color = nil }, opts.dir_icon or {}),
    default_icon =
        vim.tbl_extend("force", { icon = "", color = "#6d8086" }, opts.default_icon or {}),
  })

  -- test if we have the correct icon set for the current background
  -- if the background changed from light<->dark, refresh the icons (#855)
  if self._state and self._state.icons
      and self._state.bg == vim.o.bg
      and self._state.termguicolors == vim.o.termguicolors
  then
    return true
  end

  -- save the current background & termguicolors
  self._state.bg = vim.o.bg
  self._state.termguicolors = vim.o.termguicolors

  -- The state object needs to be RPC request compatible
  -- rpc request cannot return a table that has mixed elements
  -- of both indexed items and key value, it will fail with
  -- "Cannot convert given lua table", we therefore build our
  -- state object as a key/value map

  -- NOTES:
  -- (1) devicons.get_icons() returns the default icon in [1]
  -- (2) we cannot rely on having either .name or .color (#817)
  local ok, all_devicons = pcall(function()
    if self._state and self._state.icons then
      self._package.refresh() -- reloads light|dark theme
    end
    return self._package.get_icons()
  end)
  if not ok or not all_devicons or utils.tbl_isempty(all_devicons) then
    -- something is wrong with devicons
    utils.err("devicons.get_icons() is nil or empty!")
    return
  end
  local icons = {
    by_filename = self._package.get_icons_by_filename(),
    by_extension = self._package.get_icons_by_extension(),
  }
  if type(all_devicons[1]) == "table" then
    self._state.default_icon.icon = all_devicons[1].icon or self._state.default_icon.icon
    self._state.default_icon.color =
        (self._state.termguicolors and all_devicons[1].color or all_devicons[1].cterm_color) or
        self._state.default_icon.color
  end
  self._state.icons = {
    by_filename = {},  -- full filename (path.tail) lookup
    by_ext = {},       -- simple extension lookup
    by_ext_2part = {}, -- 2-part extensions, e.g. "foo.test.js"
    -- lookup table to indicate extension has potentially has better match
    -- in the 2part for example, ".js" will send us looking for "test.js"
    ext_has_2part = {},

  }
  for k, v in pairs(all_devicons) do
    -- skip all indexed (numeric) entries
    if type(k) == "string" then
      local info = {
        -- NOTE: we no longer need name since we use the RGB color directly
        -- name = v.name or k,
        icon = v.icon or "",
        color = (self._state.termguicolors and v.color or v.cterm_color)
            or (function()
              -- some devicons customizations remove `info.color`
              -- retrieve the color from the highlight group (#801)
              local hlgroup = "DevIcon" .. (v.name or k)
              local hexcol = utils.hexcol_from_hl(hlgroup, "fg", opts.mode)
              if hexcol and #hexcol > 0 then
                return hexcol
              end
            end)(),
      }
      -- NOTE: entries like "R" can appear in both icons by filename/extension
      if icons.by_filename[k] then
        self._state.icons.by_filename[k] = info
      end
      if icons.by_extension[k] then
        if k:match(".+%.") then
          self._state.icons.by_ext_2part[k] = info
          self._state.icons.ext_has_2part[path.extension(k)] = true
        else
          self._state.icons.by_ext[k] = info
        end
      end
      -- if not icons_by_extension[k] and not icons_by_filename[k] then
      --   print("icons_by_operating_system", k)
      -- end
    end
  end
  return true
end

function NvimWebDevicons:icon_by_ft(ft)
  if not self:loaded() then return end
  return self._package.get_icon_by_filetype(ft)
end

local MiniIcons = DevIconsBase:extend()

function MiniIcons:new()
  self._name = "mini"
  self._package_name = "mini.icons"
  return self
end

function MiniIcons:load()
  if not self._package_loaded and utils.__HAS_NVIM_08 then
    self._package_loaded, self._package = pcall(require, self._package_name)
    if self._package_loaded then
      self._package_path = path.parent(path.parent(path.parent(path.normalize(
        debug.getinfo(self._package.setup, "S").source:gsub("^@", "")))))
    end
  end
  return self._package_loaded
end

function MiniIcons:refresh_hlgroups(mode)
  if not self._state or not self._hlgroups then return end
  self._state.hl2hex = {}
  for hl, _ in pairs(self._hlgroups) do
    self._state.hl2hex["_" .. hl] = utils.hexcol_from_hl(hl, "fg", mode)
  end
end

function MiniIcons:load_icons(opts)
  if not self:loaded() then return end

  -- Icon set already loaded, refresh hlgroups and return
  if self._state and self._state.icons then
    self:refresh_hlgroups(opts.mode)
    return true
  end

  -- Mini.icons requires calling `setup()`
  ---@diagnostic disable-next-line: undefined-field
  if not _G.MiniIcons then
    require(self._package_name).setup()
  end

  -- Something isn't right
  if not _G.MiniIcons then return end

  -- Automatically discover highlight groups used by mini
  self._hlgroups = {}

  local function mini_get(category, name)
    local icon, hl = _G.MiniIcons.get(category, name)
    -- Store for `:refresh_hlgroups()`
    self._hlgroups[hl] = true
    -- Adding _underscore tells `get_devicon` to resolve using `_state.hl2hex`
    return { icon = icon, color = "_" .. hl }
  end

  self._state = vim.tbl_deep_extend("force", self._state or {}, {
    icon_padding = type(opts.icon_padding) == "string" and opts.icon_padding or nil,
    dir_icon = mini_get("default", "directory"),
    default_icon = mini_get("default", "file"),
    icons = {
      by_filename_case_sensitive = true,
      by_filename = {},  -- full filename (path.tail) lookup
      by_filetype = {},  -- filetype lookup (vim.filetype.match)
      by_ext = {},       -- simple extension lookup
      by_ext_2part = {}, -- 2-part extensions, e.g. "foo.test.js"
      -- lookup table to indicate extension has potentially has better match
      -- in the 2part for example, ".js" will send us looking for "test.js"
      ext_has_2part = {},
    }
  })

  for _, file in ipairs(_G.MiniIcons.list("file")) do
    self._state.icons.by_filename[file] = mini_get("file", file)
  end

  for _, ext in ipairs(_G.MiniIcons.list("extension")) do
    local info = mini_get("extension", ext)
    if ext:match(".+%.") then
      self._state.icons.by_ext_2part[ext] = info
      self._state.icons.ext_has_2part[path.extension(ext)] = true
    else
      self._state.icons.by_ext[ext] = info
    end
  end

  for _, ft in ipairs(_G.MiniIcons.list("filetype")) do
    self._state.icons.by_filetype[ft] = mini_get("filetype", ft)
  end

  -- Extensions that have weird behaviors within `vim.filetype.match`
  -- https://github.com/ibhagwan/fzf-lua/issues/1358#issuecomment-2254215160
  for k, v in pairs({
    sh   = "sh",
    bash = "sh",
    ksh  = "sh",
    tcsh = "sh",
  }) do
    self._state.icons.by_ext[k] = self._state.icons.by_filetype[v]
  end

  -- Resolve discovered hlgroups to colors
  self:refresh_hlgroups(opts.mode)

  return true
end

function MiniIcons:icon_by_ft(ft)
  if not self:loaded() then return end
  return self._package.get("filetype", ft)
end

local FzfLuaServer = DevIconsBase:extend()

function FzfLuaServer:new()
  self._name = "srv"
  return self
end

function FzfLuaServer:path()
  ---@diagnostic disable-next-line: undefined-field
  return _G._fzf_lua_server or vim.g.fzf_lua_server
end

function FzfLuaServer:load()
  return type(self:path()) == "string"
end

function FzfLuaServer:load_icons(opts)
  if type(self._state) == "table" then
    return self._state
  end
  local ok, errmsg = pcall(function()
    local chan_id = vim.fn.sockconnect("pipe", self:path(), { rpc = true })
    self._state = vim.rpcrequest(
      chan_id,
      "nvim_exec_lua",
      "return require'fzf-lua.devicons'.state(...)",
      { opts and opts.srv_plugin or nil })
    vim.fn.chanclose(chan_id)
  end)
  if not ok then
    io.stdout:write(string.format(
      "RPC error getting fzf_lua:devicons:STATE (%s): %s\n", self:path(), errmsg))
  end
  return self._state == "table"
end

-- When using mini from the external process we store the new icon cache on process exit
function FzfLuaServer:update_state_mini()
  -- Abort when `self._state` is `nil`, can happen with live_grep
  -- `exec_empty_query=false` (default) as icons aren't loaded (#1391)
  if not self:path() or type(self._state) ~= "table" then return end
  local ok, errmsg = pcall(function()
    local chan_id = vim.fn.sockconnect("pipe", self:path(), { rpc = true })
    self._state = vim.rpcrequest(chan_id, "nvim_exec_lua", [[
      require"fzf-lua.devicons".set_state(...)
      ]], { "mini", self._state })
    vim.fn.chanclose(chan_id)
  end)
  if not ok then
    io.stdout:write(string.format(
      "RPC error setting fzf_lua:devicons:STATE (%s): %s\n", self:path(), errmsg))
  end
end

local M = {}

M.__SRV = FzfLuaServer:new()
M.__MINI = MiniIcons:new()
M.__DEVICONS = NvimWebDevicons:new()

-- Load an icons provider and sets the module local var `M.PLUGIN`
-- "auto" prefers nvim-web-devicons, "srv" RPC-queries main instance
---@param provider boolean|string|"auto"|"devicons"|"mini"|"srv"
---@return boolean success
M.plugin_load = function(provider)
  -- Called from "make_entry.lua" without params (already loaded)
  if provider == nil and M.PLUGIN and M.PLUGIN:loaded() then
    return true
  end
  M.PLUGIN = provider == "srv" and M.__SRV
      or provider == "mini" and M.__MINI
      or provider == "devicons" and M.__DEVICONS
      or (function()
        if vim.g.fzf_lua_is_headless then
          -- headless instance, fzf-lua server exists, attempt
          -- to load icons from main neovim instance
          ---@diagnostic disable-next-line: undefined-field
          if type(_G._fzf_lua_server) == "string" then
            return M.__SRV
          end
          ---@diagnostic disable-next-line: undefined-field
          if _G._devicons_path then
            -- headless instance, no fzf-lua server was specified
            -- but we got devicon's lib path, add to runtime path
            -- so `load()` can find the library
            ---@diagnostic disable-next-line: undefined-field
            vim.opt.runtimepath:append(_G._devicons_path)
          else
            -- FATAL: headless but no global vars are defined
            local errmsg = "fzf-lua fatal: '_G._fzf_lua_server', '_G._devicons_path' both nil\n"
            io.stderr:write(errmsg)
            print(errmsg)
          end
        end
        -- Prioritize nvim-web-devicons
        local ret = M.__DEVICONS
        -- Load mini only if `_G.MiniIcons` is present or if using `mock_nvim_web_devicons()`
        -- at which point we would like to replace the mock with first-class MiniIcons (#1358)
        ---@diagnostic disable-next-line: undefined-field
        if not M.__DEVICONS:load() and _G.MiniIcons or M.__DEVICONS:is_mock() and M.__MINI:load()
        then
          ret = M.__MINI
        end
        -- Load custom setup file
        if vim.g.fzf_lua_is_headless
            ---@diagnostic disable-next-line: undefined-field
            and _G._devicons_setup and uv.fs_stat(_G._devicons_setup) then
          ---@diagnostic disable-next-line: undefined-field
          local file = loadfile(_G._devicons_setup)
          if file then pcall(file) end
        end
        return ret
      end)()
  return M.PLUGIN:load()
end

-- Attemp to loadeLoa icons plugin at least once on require
M.plugin_load()

M.plugin_loaded = function()
  return M.PLUGIN:loaded()
end

M.plugin_path = function()
  return M.PLUGIN:path()
end

M.plugin_name = function()
  return M.PLUGIN:name()
end

M.icon_by_ft = function(ft)
  return M.PLUGIN:icon_by_ft(ft)
end

-- NOTE: plugin_name is only sent when called from `FzfLuaServer:load_icons`
-- it is used when testing from "devicons_spec.lua" as calling `M.load()`
-- changes the ref in `M.PLUGIN` and will then return a nil `:state()`
---@param plugin_name string
---@return table STATE
M.state = function(plugin_name)
  if plugin_name == "mini" then
    return M.__MINI:state()
  elseif plugin_name == "devicons" then
    return M.__DEVICONS:state()
  else
    return M.PLUGIN:state()
  end
end

-- NOTE: this gets called when on "make_entry.postprocess" when `file_icons="mini"`
M.set_state = function(plugin_name, state)
  if plugin_name == "mini" then
    return M.__MINI:set_state(state)
  elseif plugin_name == "devicons" then
    return M.__DEVICONS:set_state(state)
  else
    return M.PLUGIN:set_state(state)
  end
end

-- For testing
M.unload = function()
  M.PLUGIN:unload()
end


---@param filepath string
---@param extensionOverride string?
---@return string, string?
M.get_devicon = function(filepath, extensionOverride)
  local STATE = M.state()
  if not STATE or not STATE.icons then
    return unpack({ "", nil })
  end

  local function validate_hl(col)
    if col and col:match("^_") then
      return STATE.hl2hex[col]
    else
      return col
    end
  end

  if path.ends_with_separator(filepath) then
    -- path is directory
    return STATE.dir_icon.icon, validate_hl(STATE.dir_icon.color)
  end

  local icon, color
  local filename = path.tail(filepath)
  local ext = extensionOverride or path.extension(filename, true)

  -- lookup directly by filename
  local by_filename = STATE.icons.by_filename
      [STATE.icons.by_filename_case_sensitive and filename or filename:lower()]
  if by_filename then
    icon, color = by_filename.icon, by_filename.color
  end

  if ext then ext = ext:lower() end

  -- check for `ext` as extension can be nil, e.g. "dockerfile"
  -- lookup by 2 part extensions, e.g. "foo.test.tsx"
  if ext and not icon and STATE.icons.ext_has_2part[ext] then
    local ext2 = path.extension(filename:sub(1, #filename - #ext - 1))
    if ext2 then
      local by_ext_2part = STATE.icons.by_ext_2part[ext2:lower() .. "." .. ext]
      if by_ext_2part then
        icon, color = by_ext_2part.icon, by_ext_2part.color
      end
    end
  end

  -- finally lookup by "one-part" extension (i.e. no dots in ext)
  if ext and not icon then
    local by_ext = STATE.icons.by_ext[ext]
    if by_ext then
      icon, color = by_ext.icon, by_ext.color
    end
  end

  -- mini.icons supports lookup by filetype
  if not icon and STATE.icons.by_filetype then
    local ft = path.ft_match({ filename = filename })
    local by_ft = ft and #ft > 0 and STATE.icons.by_filetype[ft]

    if not by_ft then
      -- store default icon in cache to avoid lookup by ft a second time
      by_ft = { icon = STATE.default_icon.icon, color = STATE.default_icon.color }
    end

    icon, color = by_ft.icon, by_ft.color

    -- Store in the corresponding lookup table to prevent another `vim.filetype.match`
    -- NOTE: this logic has a flaw by design where certain filenames/extensions will
    -- differ from mini.icons as mini performs fullpath lookup and caching which results
    -- in a very large cache which is better avoided in fzf-lua for performance reasons
    if ext then
      STATE.icons.by_ext[ext] = by_ft
    else
      STATE.icons.by_filename[filename] = by_ft
    end
  end

  -- Default icon/color, we never return nil
  icon = icon or STATE.default_icon.icon
  color = color or STATE.default_icon.color

  if STATE.icon_padding then
    icon = icon .. STATE.icon_padding
  end

  return icon, validate_hl(color)
end

---@return boolean|nil success
M.load = function(opts)
  opts = opts or {}

  -- If unable to load mini/devicons, abort
  if not M.plugin_load(opts.plugin) then return end

  -- Load/refresh the icon set, does nothing unless unloaded or bg changed
  return M.PLUGIN:load_icons(opts)
end

return M
