local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"

-- Our "copy" of the devicons library functions so we can load the library
-- from the headless instance and better support edge cases like multi-part
-- extension names (#1053)
-- Not that it makes much difference at this point but this also lowers the
-- minimum requirements of neovim 0.7 as we no longer need to run setup
-- and fail due to using the newer highlight creation APIs
local M = {}

M.plugin_loaded = function()
  return M.__HAS_DEVICONS
end

M.plugin_path = function()
  return M.__DEVICONS_PATH
end

M.load_devicons_plugin = function()
  if M.plugin_loaded() then return end
  -- limit devicons support to nvim >=0.8, although official support is >=0.7
  -- running setup on 0.7 errs with "W18: Invalid character in group name"
  if utils.__HAS_NVIM_07 then
    M.__HAS_DEVICONS, M.__DEVICONS_LIB = pcall(require, "nvim-web-devicons")
    if M.__HAS_DEVICONS then
      M.__DEVICONS_PATH = path.parent(path.parent(path.normalize(
        debug.getinfo(M.__DEVICONS_LIB.setup, "S").source:gsub("^@", ""))))
    end
  end
end

-- Load devicons at least once on require
M.load_devicons_plugin()

M.load_devicons_fzflua_server = function()
  local res = nil
  local ok, errmsg = pcall(function()
    ---@diagnostic disable-next-line: undefined-field
    local chan_id = vim.fn.sockconnect("pipe", _G._fzf_lua_server, { rpc = true })
    res = vim.rpcrequest(
      chan_id,
      "nvim_exec_lua",
      "return require'fzf-lua.devicons'.STATE",
      {})
    vim.fn.chanclose(chan_id)
  end)
  if not ok or type(res) ~= "table" then
    io.stderr:write(string.format("RPC error getting fzf_lua:devicons:STATE: %s\n", errmsg))
    return
  else
    M.STATE = res
  end
end

M.load_icons = function()
  if not M.plugin_loaded() then return end
  if M.STATE and M.STATE.icons
      -- Refresh if `bg` changed from dark/light (#855)
      and (not M.STATE.bg or vim.o.bg == M.STATE.bg) then
    return
  end
  -- save the current background
  M.STATE.bg = vim.o.bg
  -- rpc request cannot return a table that has mixed elements
  -- of both indexed items and key value, it will fail with
  -- "Cannot convert given lua table"
  -- NOTES:
  -- (1) devicons.get_icons() returns the default icon in [1]
  -- (2) we cannot rely on having either .name or .color (#817)
  local ok, all_devicons = pcall(function()
    M.__DEVICONS_LIB.refresh() -- reloads light|dark theme
    return M.__DEVICONS_LIB.get_icons()
  end)
  if not ok or not all_devicons or vim.tbl_isempty(all_devicons) then
    -- something is wrong with devicons
    -- can't use `error` due to fast event
    print("[Fzf-lua] error: devicons.get_icons() is nil or empty!")
    return
  end
  local theme
  if vim.o.background == "light" then
    ok, theme = pcall(require, "nvim-web-devicons.icons-light")
  else
    ok, theme = pcall(require, "nvim-web-devicons.icons-default")
  end
  if not ok or type(theme) ~= "table" or not theme.icons_by_filename then
    print("[Fzf-lua] error: devicons.theme is nil or empty!")
    return
  end
  local icons_by_filename = theme.icons_by_filename or {}
  local icons_by_file_extension = theme.icons_by_file_extension or {}
  if type(all_devicons[1]) == "table" then
    M.STATE.default_icon.icon = all_devicons[1].icon or M.STATE.default_icon.icon
    M.STATE.default_icon.color = all_devicons[1].color or M.STATE.default_icon.color
  end
  M.STATE.icons = {
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
        color = v.color or (function()
          -- some devicons customizations remove `info.color`
          -- retrieve the color from the highlight group (#801)
          local hlgroup = "DevIcon" .. (v.name or k)
          local hexcol = utils.hexcol_from_hl(hlgroup, "fg")
          if hexcol and #hexcol > 0 then
            return hexcol
          end
        end)(),
      }
      -- NOTE: entries like "R" can appear in both icons by filename/extension
      if icons_by_filename[k] then
        M.STATE.icons.by_filename[k] = info
      end
      if icons_by_file_extension[k] then
        if k:match(".+%.") then
          M.STATE.icons.by_ext_2part[k] = info
          M.STATE.icons.ext_has_2part[path.extension(k)] = true
        else
          M.STATE.icons.by_ext[k] = info
        end
      end
      -- if not icons_by_file_extension[k] and not icons_by_filename[k] then
      --   print("icons_by_operating_system", k)
      -- end
    end
  end
  return M.STATE.icons
end

---@param filepath string
---@param extensionOverride string?
---@return string, string?
M.get_devicon = function(filepath, extensionOverride)
  if not M.STATE or not M.STATE.icons then
    return unpack({ "", nil })
  end

  if path.ends_with_separator(filepath) then
    -- path is directory
    return M.STATE.dir_icon.icon, M.STATE.dir_icon.color
  end

  local icon, color
  local filename = path.tail(filepath)
  local ext = extensionOverride or path.extension(filename, true)

  -- lookup directly by filename
  local by_filename = M.STATE.icons.by_filename[filename]
  if by_filename then
    icon, color = by_filename.icon, by_filename.color
  end

  -- check for `ext` as extension can be nil, e.g. "dockerfile"
  -- lookup by 2 part extensions, e.g. "foo.test.tsx"
  if ext and not icon and M.STATE.icons.ext_has_2part[ext] then
    local ext2 = path.extension(filename:sub(1, #filename - #ext - 1))
    if ext2 then
      local by_ext_2part = M.STATE.icons.by_ext_2part[ext2 .. "." .. ext]
      if by_ext_2part then
        icon, color = by_ext_2part.icon, by_ext_2part.color
      end
    end
  end

  -- finally lookup by "one-part" extension (i.e. no dots in ext)
  if ext and not icon then
    local by_ext = M.STATE.icons.by_ext[ext]
    if by_ext then
      icon, color = by_ext.icon, by_ext.color
    end
  end

  -- Default icon/color, we never return nil
  icon = icon or M.STATE.default_icon.icon
  color = color or M.STATE.default_icon.color

  if M.STATE.icon_padding then
    icon = icon .. M.STATE.icon_padding
  end

  return icon, color
end

M.load = function(opts)
  opts = opts or {}

  M.STATE = vim.tbl_deep_extend("force", M.STATE or {}, {
    icon_padding = type(opts.icon_padding) == "string" and opts.icon_padding or nil,
    dir_icon = vim.tbl_extend("force", { icon = "", color = nil }, opts.dir_icon or {}),
    default_icon =
        vim.tbl_extend("force", { icon = "", color = "#6d8086" }, opts.default_icon or {}),
  })

  -- Check if we're running from the headless instance, attempt to  load our
  -- icons with the RPC response of `get_icons` from the main fzf-lua instance
  ---@diagnostic disable-next-line: undefined-field
  if vim.g.fzf_lua_is_headless and not _G._fzf_lua_server and not _G._devicons_path then
    local errmsg = "fzf-lua fatal: '_G._fzf_lua_server', '_G._devicons_path' both nil\n"
    io.stderr:write(errmsg)
    print(errmsg)
    return
  end
  if vim.g.fzf_lua_is_headless and _G._fzf_lua_server then
    -- headless instance, fzf-lua server exists, attempt
    -- to load icons from main neovim instance
    M.load_devicons_fzflua_server()
    return
  end
  if vim.g.fzf_lua_is_headless and _G._devicons_path then
    -- headless instance, no fzf-lua server was specified
    -- but we got devicon's lib path, add to runtime path
    -- so `load_devicons_plugin` can find the library
    vim.opt.runtimepath:append(_G._devicons_path)
  end
  -- Attempt to load devicons plugin
  M.load_devicons_plugin()

  -- Load custom overrides before loading icons
  if vim.g.fzf_lua_is_headless
      ---@diagnostic disable-next-line: undefined-field
      and _G._devicons_setup and vim.loop.fs_stat(_G._devicons_setup) then
    ---@diagnostic disable-next-line: undefined-field
    local file = loadfile(_G._devicons_setup)
    if file then pcall(file) end
  end

  -- Load the devicons iconset
  M.load_icons()
end

-- For testing
M.unload = function()
  M.STATE = nil
  M.__HAS_DEVICONS = nil
  M.__DEVICONS_LIB = nil
  M.__DEVICONS_PATH = nil
  M.load_devicons_plugin()
end

return M
