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
---@diagnostic disable-next-line: undefined-field
M._devicons_setup = _G._devicons_setup

local function load_config_section(s, datatype, optional)
  if config then
    local keys = utils.strsplit(s, ".")
    local iter, sect = config, nil
    for i = 1, #keys do
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
    local is_bytecode = false
    local exec_str, exec_opts = nil, nil
    if datatype == "function" then
      is_bytecode = true
      exec_opts = { s, datatype }
      exec_str = ("return require'fzf-lua'.config.bytecode(...)"):format(s)
    else
      exec_opts = {}
      exec_str = ("return require'fzf-lua'.config.%s"):format(s)
    end
    local ok, errmsg = pcall(function()
      local chan_id = vim.fn.sockconnect("pipe", M._fzf_lua_server, { rpc = true })
      res = vim.rpcrequest(chan_id, "nvim_exec_lua", exec_str, exec_opts)
      vim.fn.chanclose(chan_id)
    end)
    if ok and is_bytecode then
      ok, res = pcall(loadstring, res)
    end
    if not ok and not optional then
      io.stderr:write(("Error loading remote config section '%s': %s\n")
        :format(s, errmsg))
    elseif ok and type(res) == datatype then
      return res
    end
  end
end

local function set_config_section(s, data)
  if M._fzf_lua_server then
    -- save config in our running instance
    local ok, errmsg = pcall(function()
      local chan_id = vim.fn.sockconnect("pipe", M._fzf_lua_server, { rpc = true })
      vim.rpcrequest(chan_id, "nvim_exec_lua", ([[
        local data = select(1, ...)
        require'fzf-lua'.config.%s = data
      ]]):format(s), { data })
      vim.fn.chanclose(chan_id)
    end)
    if not ok then
      io.stderr:write(("Error setting remote config section '%s': %s\n")
        :format(s, errmsg))
    end
    return ok
  elseif config then
    local keys = utils.strsplit(s, ".")
    local iter = config
    for i = 1, #keys do
      iter = iter[keys[i]]
      if not iter then break end
      if i == #keys - 1 then
        iter[keys[i + 1]] = data
        return iter
      end
    end
  end
end

-- Setup the terminal colors codes for nvim-web-devicons colors
local setup_devicon_term_hls = function()
  local function hex(hexstr)
    local r, g, b = hexstr:match(".(..)(..)(..)")
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    return r, g, b
  end

  for _, info in pairs(M._devicons and M._devicons.get_icons() or M._devicons_map) do
    local r, g, b = hex(info.color)
    utils.add_ansi_code("DevIcon" .. info.name, string.format("[38;2;%s;%s;%sm", r, g, b))
  end
end

local function load_devicons()
  if config and config._has_devicons then
    -- file was called from the primary instance
    -- acquire nvim-web-devicons from config
    M._devicons = config._devicons
  elseif M._fzf_lua_server and load_config_section("_has_devicons", "boolean") then
    -- file was called from a headless instance
    -- load nvim-web-devicons via the RPC to the main instance
    M._devicons_map = load_config_section("_devicons_geticons()", "table")
  end
  if not M._devicons and not M._devicons_map
      and M._devicons_path and vim.loop.fs_stat(M._devicons_path) then
    -- file was called from a headless instance
    -- fallback load nvim-web-devicons manually
    -- add nvim-web-devicons path to `package.path`
    -- so `require("nvim-web-devicons")` can find it
    package.path = (";%s/?.lua;"):format(vim.fn.fnamemodify(M._devicons_path, ":h"))
        .. package.path
    M._devicons = require("nvim-web-devicons")
    -- WE NO LONGER USE THIS, LEFT FOR DOCUMENTATION
    -- loading with 'require' is needed, 'loadfile'
    -- cannot load a custom setup function as it's
    -- considered a separate instance and the inner
    -- 'require' in the setup file will create an
    -- additional 'nvim-web-devicons' instance
    --[[ local file = loadfile(M._devicons_path)
    M._devicons = file and file() ]]
    -- did caller specify a custom setup function?
    -- must be called before the next step as `setup`
    -- is ignored when called the second time
    M._devicons_setup = M._devicons_setup and vim.fn.expand(M._devicons_setup)
    if M._devicons and M._devicons_setup and vim.loop.fs_stat(M._devicons_setup) then
      local file = loadfile(M._devicons_setup)
      if file then file() end
    end
  end
  if M._devicons and M._devicons.setup and not M._devicons.has_loaded() then
    -- if the caller has devicons lazy loaded
    -- running without calling setup will generate an error:
    --  nvim-web-devicons.lua:972: E5560:
    --  nvim_command must not be called in a lua loop callback
    -- running in a pcall to avoid panic with neovim <= 0.6
    -- due to usage of new highlighting API introduced with v0.7
    pcall(M._devicons.setup)
  end
  if M._devicons and M._devicons.has_loaded() or M._devicons_map then
    -- Setup devicon terminal ansi color codes
    setup_devicon_term_hls()
  end
end

-- Load remote config and devicons
pcall(load_devicons)

if not config then
  local _config = { globals = { git = {}, files = {}, grep = {} } }
  _config.globals.git.icons = load_config_section("globals.git.icons", "table") or {}
  _config.globals.file_icon_colors = load_config_section("globals.file_icon_colors", "table") or {}
  _config.globals.file_icon_padding = load_config_section("globals.file_icon_padding", "string")
  _config.globals.files.git_status_cmd = load_config_section("globals.files.git_status_cmd", "table")
  _config.globals.grep.rg_glob_fn = load_config_section("globals.grep.rg_glob_fn", "function", true)

  _config.globals.nbsp = load_config_section("globals.nbsp", "string")
  if _config.globals.nbsp then utils.nbsp = _config.globals.nbsp end

  config = _config
end

M.get_devicon = function(file, ext)
  local icon, hl
  if M._devicons then
    icon, hl = M._devicons.get_icon(file, ext:lower(), { default = true })
  elseif M._devicons_map then
    local info = M._devicons_map[ext:lower()] or M._devicons_map["<default>"]
    -- the default icon is not a guranteed as nvim-web-devicons
    -- can be configured with `default = false`
    if info then
      icon = info.icon
      hl = "DevIcon" .. info.name
    end
  else
    icon, hl = "", "dark_grey"
  end

  -- allow user override of the color
  local override = config.globals.file_icon_colors
      and config.globals.file_icon_colors[ext]
  if override then
    hl = override
  end

  if config.globals.file_icon_padding and
      #config.globals.file_icon_padding > 0 then
    icon = icon .. config.globals.file_icon_padding
  end

  return icon, hl
end

M.get_diff_files = function(opts)
  local diff_files = {}
  local cmd = opts.git_status_cmd or config.globals.files.git_status_cmd
  if not cmd then return {} end
  local ok, status, err = pcall(utils.io_systemlist, path.git_cwd(cmd, opts))
  if ok and err == 0 then
    for i = 1, #status do
      local icon = status[i]:match("[MUDARCT?]+")
      local file = status[i]:match("[^ ]*$")
      if icon and file then
        diff_files[file] = icon:gsub("%?%?", "?")
      end
    end
  end

  return diff_files
end

M.glob_parse = function(query, opts)
  if not query or not query:find(opts.glob_separator) then
    return query, nil
  end
  if config.globals.grep.rg_glob_fn then
    return config.globals.grep.rg_glob_fn(query, opts)
  end
  local glob_args = ""
  local search_query, glob_str = query:match("(.*)" .. opts.glob_separator .. "(.*)")
  for _, s in ipairs(utils.strsplit(glob_str, "%s")) do
    glob_args = glob_args .. ("%s %s ")
        :format(opts.glob_flag, vim.fn.shellescape(s))
  end
  return search_query, glob_args
end

M.preprocess = function(opts)
  if opts.cwd_only and not opts.cwd then
    opts.cwd = vim.loop.cwd()
  end

  if opts.git_icons then
    opts.diff_files = M.get_diff_files(opts)
  end

  local argv = function(i, debug)
    -- argv1 is actually the 7th argument if we count
    -- arguments already supplied by 'wrap_spawn_stdio'.
    -- If no index was supplied use the last argument
    local idx = tonumber(i) and tonumber(i) + 6 or #vim.v.argv
    if debug then
      io.stdout:write(("[DEBUG]: argv(%d) = %s\n")
        :format(idx, vim.fn.shellescape(vim.v.argv[idx])))
    end
    return vim.v.argv[idx]
  end

  -- live_grep replace pattern with last argument
  local argvz = "{argvz}"
  local has_argvz = opts.cmd and opts.cmd:match(argvz)

  -- save our last search argument for resume
  if opts.argv_expr and has_argvz then
    local query = argv(nil, opts.debug)
    set_config_section("__resume_data.last_query", query)
    if opts.__module__ then
      set_config_section(("globals.%s._last_search"):format(opts.__module__),
        { query = query, no_esc = true })
    end
  end

  -- did the caller request rg with glob support?
  -- manipulation needs to be done before the argv hack
  if opts.rg_glob and has_argvz then
    local query = argv()
    local search_query, glob_args = M.glob_parse(query, opts)
    if glob_args then
      -- gsub doesn't like single % on rhs
      search_query = search_query:gsub("%%", "%%%%")
      -- reset argvz so it doesn't get replaced again below
      opts.cmd = opts.cmd:gsub(argvz,
        glob_args .. vim.fn.shellescape(search_query))
    end
  end

  -- nifty hack to avoid having to double escape quotations
  -- see my comment inside 'live_grep' initial_command code
  if opts.argv_expr then
    opts.cmd = opts.cmd:gsub("{argv.*}",
      function(x)
        local idx = x:match("{argv(.*)}")
        return vim.fn.shellescape(argv(idx))
      end)
  end

  return opts
end

M.lcol = function(entry, opts)
  if not entry then return nil end
  local filename = entry.filename or vim.api.nvim_buf_get_name(entry.bufnr)
  return string.format("%s:%s:%s:%s%s",
    -- uncomment to test URIs
    -- "file://" .. filename,
    filename, --utils.ansi_codes.magenta(filename),
    utils.ansi_codes.green(tostring(entry.lnum)),
    utils.ansi_codes.blue(tostring(entry.col)),
    entry.text and #entry.text > 0 and " " or "",
    not entry.text and "" or
    (opts and opts.trim_entry and vim.trim(entry.text)) or entry.text)
end

local COLON_BYTE = string.byte(":")

M.file = function(x, opts)
  opts = opts or {}
  local ret = {}
  local icon, hl
  local colon_idx = utils.find_next_char(x, COLON_BYTE) or 0
  local file_part = colon_idx > 1 and x:sub(1, colon_idx - 1) or x
  local rest_of_line = colon_idx > 1 and x:sub(colon_idx) or nil
  -- strip ansi coloring from path so we can use filters
  -- otherwise the ANSI escape sequence will get in the way
  -- TODO: we only support path modification without ANSI
  -- escape sequences, it becomes too expensive to modify
  -- and restore the path with escape sequences
  local filepath, file_is_ansi = utils.strip_ansi_coloring(file_part)
  -- fd v8.3 requires adding '--strip-cwd-prefix' to remove
  -- the './' prefix, will not work with '--color=always'
  -- https://github.com/sharkdp/fd/blob/master/CHANGELOG.md
  if not (opts.strip_cwd_prefix == false) and path.starts_with_cwd(filepath) then
    filepath = path.strip_cwd_prefix(filepath)
  end
  -- make path relative
  if opts.cwd and #opts.cwd > 0 then
    filepath = path.relative(filepath, opts.cwd)
  end
  if path.starts_with_separator(filepath) then
    -- filter for cwd only
    if opts.cwd_only then
      local cwd = opts.cwd or vim.loop.cwd()
      if not path.is_relative(filepath, cwd) then
        return nil
      end
    end
    -- replace $HOME with ~
    filepath = path.HOME_to_tilde(filepath)
  end
  -- only check for ignored patterns after './' was
  -- stripped and path was transformed to relative
  if opts.file_ignore_patterns then
    for _, pattern in ipairs(opts.file_ignore_patterns) do
      if #pattern > 0 and filepath:match(pattern) then
        return nil
      end
    end
  end
  -- only shorten after we're done with all the filtering
  -- save a copy for git indicator and icon lookups
  local origpath = filepath
  if opts.path_shorten then
    filepath = path.shorten(filepath, tonumber(opts.path_shorten))
  end
  if opts.git_icons then
    local indicators = opts.diff_files and opts.diff_files[origpath] or utils.nbsp
    for i = 1, #indicators do
      icon = indicators:sub(i, i)
      local git_icon = config.globals.git.icons[icon]
      if git_icon then
        icon = git_icon.icon
        if opts.color_icons then
          icon = utils.ansi_codes[git_icon.color or "dark_grey"](icon)
        end
      end
      ret[#ret + 1] = icon
    end
    ret[#ret + 1] = utils.nbsp
  end
  if opts.file_icons then
    local filename = path.tail(origpath)
    local ext = path.extension(filename)
    icon, hl = M.get_devicon(filename, ext)
    if opts.color_icons then
      -- extra workaround for issue #119 (or similars)
      -- use default if we can't find the highlight ansi
      local fn = utils.ansi_codes[hl] or utils.ansi_codes["dark_grey"]
      icon = fn(icon)
    end
    ret[#ret + 1] = icon
    ret[#ret + 1] = utils.nbsp
  end
  ret[#ret + 1] = file_is_ansi > 0 and file_part or filepath
  ret[#ret + 1] = rest_of_line
  return table.concat(ret)
end

M.tag = function(x, opts)
  local name, file, text = x:match("([^\t]+)\t([^\t]+)\t(.*)")
  if not file or not name or not text then return x end
  text = text:match([[(.*);"]]) or text -- remove ctag comments
  -- unescape ctags special chars
  -- '\/' -> '/'
  -- '\\' -> '\'
  for _, s in ipairs({ "/", "\\" }) do
    text = text:gsub([[\]] .. s, s)
  end
  local line, tag = text:match("(%d-);?(/.*/)")
  line = line and #line > 0 and tonumber(line)
  return ("%s%s: %s %s"):format(
    M.file(file, opts),
    not line and "" or ":" .. utils.ansi_codes.green(tostring(line)),
    utils.ansi_codes.magenta(name),
    utils.ansi_codes.green(tag)
  ), line
end

return M
