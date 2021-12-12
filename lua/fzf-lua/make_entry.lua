local M = {}

local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = nil

-- attempt to load the current config
-- should fail if we're running headless
do
  local ok, module = pcall(require, "fzf-lua.config")
  if ok then config = module end
end

-- These globals are set by spawn.fn_transform loadstring
---@diagnostic disable-next-line: undefined-field
M._fzf_lua_server = _G._fzf_lua_server
---@diagnostic disable-next-line: undefined-field
M._devicons_path = _G._devicons_path

local function load_config_section(s, datatype)
  if config then
    local keys = utils.strsplit(s, '.')
    local iter, sect = config, nil
    for i=1,#keys do
      iter = iter[keys[i]]
      if not iter then break end
      if i == #keys and type(iter) == datatype then
        sect = iter
      end
    end
    return sect
  elseif M._fzf_lua_server then
    -- load config from our running instance
    local res = nil
    local ok, errmsg = pcall(function()
      local chan_id = vim.fn.sockconnect("pipe", M._fzf_lua_server, { rpc = true })
      res = vim.rpcrequest(chan_id, "nvim_exec_lua", ([[
        return require'fzf-lua'.config.%s
      ]]):format(s), {})
      vim.fn.chanclose(chan_id)
    end)
    if not ok then
      io.write(("Error loading remote config section '%s': %s\n")
        :format(s, errmsg))
    elseif type(res) == datatype then
      return res
    end
  end
end

-- Setup the terminal colors codes for nvim-web-devicons colors
local setup_devicon_term_hls = function()
  local function hex(hexstr)
    local r,g,b = hexstr:match('.(..)(..)(..)')
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    return r, g, b
  end

  for _, info in pairs(M._devicons.get_icons()) do
    local r, g, b = hex(info.color)
    utils.add_ansi_code('DevIcon' .. info.name, string.format('[38;2;%s;%s;%sm', r, g, b))
  end
end

local function load_devicons()
  -- file was called from a headless instance
  -- load nvim-web-devicons manually
  if config and config._has_devicons then
    M._devicons = config._devicons
  elseif M._devicons_path and vim.loop.fs_stat(M._devicons_path) then
    local file = loadfile(M._devicons_path)
    M._devicons = file and file()
  end
  if M._devicons and M._devicons.setup and not M._devicons.has_loaded() then
    -- if the caller has devicons lazy loaded
    -- running without calling setup will generate an error:
    --  nvim-web-devicons.lua:972: E5560:
    --  nvim_command must not be called in a lua loop callback
    M._devicons.setup()
  end
  if M._devicons and M._devicons.has_loaded() then
    -- Setup devicon terminal ansi color codes
    setup_devicon_term_hls()
  end
end

-- Load remote config and devicons
load_devicons()

if not config then
  local _config = { globals = { git = {}, files = {} } }
  _config.globals.git.icons = load_config_section('globals.git.icons', 'table') or {}
  _config.globals.file_icon_colors = load_config_section('globals.file_icon_colors', 'table') or {}
  _config.globals.file_icon_padding = load_config_section('globals.file_icon_padding', 'string')
  _config.globals.files.git_status_cmd = load_config_section('globals.files.git_status_cmd', 'table')

  -- _G.dump(_config)
  config = _config
end

M.get_devicon = function(file, ext)
  local icon, hl
  if M._devicons then
    icon, hl  = M._devicons.get_icon(file, ext:lower(), {default = true})
  else
    icon, hl = '', 'dark_grey'
  end

  -- allow user override of the color
  local override = config.globals.file_icon_colors
    and config.globals.file_icon_colors[ext]
  if override then
      hl = override
  end

  return icon..config.globals.file_icon_padding:gsub(" ", utils.nbsp), hl
end

M.get_diff_files = function(opts)
    local diff_files = {}
    local cmd = opts.git_status_cmd or config.globals.files.git_status_cmd
    if not cmd then return {} end
    local status, err = utils.io_systemlist(path.git_cwd(cmd, opts.cwd))
    if err == 0 then
        for i = 1, #status do
          local icon = status[i]:match("[MUDARC?]+")
          local file = status[i]:match("[^ ]*$")
          if icon and file then
            diff_files[file] = icon
          end
        end
    end

    return diff_files
end

M.preprocess = function(opts)
  if opts.cwd_only and not opts.cwd then
    opts.cwd = vim.loop.cwd()
  end

  if opts.git_icons then
    opts.diff_files = M.get_diff_files(opts)
  end
  return opts
end

M.file = function(opts, x)
  local ret = {}
  local icon, hl
  local file = utils.strip_ansi_coloring(string.match(x, '[^:]*'))
  -- TODO: this can cause issues with files/grep/live_grep
  -- process_lines gsub will replace the entry with nil
  -- **low priority as we never use 'cwd_only' with files/grep
  if opts.cwd_only and path.starts_with_separator(file) then
    local cwd = opts.cwd or vim.loop.cwd()
    if not path.is_relative(file, cwd) then
      return nil
    end
  end
  -- fd v8.3 requires adding '--strip-cwd-prefix' to remove
  -- the './' prefix, will not work with '--color=always'
  -- https://github.com/sharkdp/fd/blob/master/CHANGELOG.md
  if not (opts.strip_cwd_prefix == false) and path.starts_with_cwd(x) then
     x = path.strip_cwd_prefix(x)
     -- this is required to fix git icons not showing
     -- since `git status -s` does not prepend './'
     -- we can assume no ANSI coloring is present
     -- since 'path.starts_with_cwd == true'
     file = x
  end
  if opts.cwd and #opts.cwd > 0 then
    -- TODO: does this work if there are ANSI escape codes in x?
    x = path.relative(x, opts.cwd)
  end
  if opts.file_icons then
    local filename = path.tail(file)
    local ext = path.extension(filename)
    icon, hl = M.get_devicon(filename, ext)
    if opts.color_icons then
      -- extra workaround for issue #119 (or similars)
      -- use default if we can't find the highlight ansi
      local fn = utils.ansi_codes[hl] or utils.ansi_codes['dark_grey']
      icon = fn(icon)
    end
    ret[#ret+1] = icon
    ret[#ret+1] = utils.nbsp
  end
  if opts.git_icons then
    local indicators = opts.diff_files and opts.diff_files[file] or utils.nbsp
    for i=1,#indicators do
      icon = indicators:sub(i,i)
      local git_icon = config.globals.git.icons[icon]
      if git_icon then
        icon = git_icon.icon
        if opts.color_icons then
          icon = utils.ansi_codes[git_icon.color or "dark_grey"](icon)
        end
      end
      ret[#ret+1] = icon
    end
    ret[#ret+1] = utils.nbsp
  end
  ret[#ret+1] = x
  return table.concat(ret)
end

return M
