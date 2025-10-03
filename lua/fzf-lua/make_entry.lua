local M = {}

local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local devicons = require "fzf-lua.devicons"
local config

-- attempt to load the current config
-- should fail if we're running headless
do
  local ok, module = pcall(require, "fzf-lua.config")
  if ok then config = module end
end

-- load config from our running instance
local function load_config()
  ---@diagnostic disable-next-line: undefined-field
  if not _G._fzf_lua_server then return end
  local res = nil
  local ok, errmsg = pcall(function()
    ---@diagnostic disable-next-line: undefined-field
    local chan_id = vim.fn.sockconnect("pipe", _G._fzf_lua_server, { rpc = true })
    res = vim.rpcrequest(chan_id, "nvim_exec_lua", [[
      return FzfLua.libuv.serialize(FzfLua.config)
    ]], {})
    res = libuv.deserialize(assert(res))
    vim.fn.chanclose(chan_id)
  end)
  if not ok then
    dump(res)
    dump(errmsg)
  end
  return res
end

local function load_config_section(s, datatype, optional)
  if not _G._fzf_lua_is_headless then
    local val = utils.map_get(config, s)
    return type(val) == datatype and val or nil
    ---@diagnostic disable-next-line: undefined-field
  elseif _G._fzf_lua_server then
    -- load config from our running instance
    local res = nil
    local is_bytecode = false
    local exec_str, exec_opts = nil, nil
    if datatype == "function" then
      is_bytecode = true
      exec_opts = { s, datatype }
      exec_str = "return require'fzf-lua'.config.bytecode(...)"
    else
      exec_opts = {}
      exec_str = ("return require'fzf-lua'.config.%s"):format(s)
    end
    local ok, errmsg = pcall(function()
      ---@diagnostic disable-next-line: undefined-field
      local chan_id = vim.fn.sockconnect("pipe", _G._fzf_lua_server, { rpc = true })
      res = vim.rpcrequest(chan_id, "nvim_exec_lua", exec_str, exec_opts)
      vim.fn.chanclose(chan_id)
    end)
    if ok and is_bytecode then
      ok, res = pcall(loadstring, res)
    end
    ---@diagnostic disable-next-line: undefined-field
    if _G._debug == "v" or _G._debug == 2 then
      ---@diagnostic disable-next-line: undefined-field
      io.stdout:write(("[DEBUG] [load_config] %s = %s" .. (_G._EOL or "\n"))
        :format(s, not ok and errmsg or res))
    end
    if not ok and not optional then
      io.stderr:write(("Error loading remote config section '%s': %s\n"):format(s, errmsg))
    elseif ok and type(res) == datatype then
      return res
    end
  end
end


local opts2 = setmetatable({}, {
  __index = function(_, k)
    if k == "fn_transform_cmd" then
      return load_config_section("__resume_data.opts.fn_transform_cmd", "function", true)
    end
    return utils.map_get(config, "__resume_data.opts." .. k)
  end
})

if _G._fzf_lua_is_headless then
  local _config = load_config() or {} ---@module 'fzf-lua.config'
  _config.globals = { git = {}, files = {}, grep = {} }
  _config.globals.git.icons = load_config_section("globals.git.icons", "table") or {}
  _config.globals.files.git_status_cmd =
      load_config_section("globals.files.git_status_cmd", "table")
      or { "git", "-c", "color.status=false", "--no-optional-locks", "status", "--porcelain=v1" }

  -- prioritize `opts.rg_glob_fn` over globals
  _config.globals.grep.rg_glob_fn = opts2.rg_glob_fn or
      load_config_section("globals.grep.rg_glob_fn", "function", true)

  _config.globals.nbsp = load_config_section("globals.nbsp", "string")
  if _config.globals.nbsp then utils.nbsp = _config.globals.nbsp end

  config = _config

  -- Compat global with known modules so we can use it in callbacks (fn_transform, etc)
  _G.FzfLua = {
    make_entry = M,
    config = config,
    path = path,
    utils = utils,
    libuv = libuv,
    devicons = devicons,
  }
end

M.get_diff_files = function(opts)
  local diff_files = {}
  local cmd = opts.git_status_cmd or config.globals.files.git_status_cmd
  if not cmd then return {} end
  local start = uv.hrtime()
  local ok, status, err = pcall(utils.io_systemlist, path.git_cwd(cmd, opts))
  local seconds = (uv.hrtime() - start) / 1e9
  if seconds >= 0.5 and opts.silent ~= true then
    local exec_str = string.format([[require"fzf-lua".utils.warn(]] ..
      [["'git status' took %.2f seconds, consider using `git_icons=false` in this repository or use `silent=true` to supress this message.")]]
      , seconds)
    if not _G._fzf_lua_is_headless then
      loadstring(exec_str)()
    else
      ---@diagnostic disable-next-line: undefined-field
      local chan_id = vim.fn.sockconnect("pipe", _G._fzf_lua_server, { rpc = true })
      vim.rpcrequest(chan_id, "nvim_exec_lua", exec_str, {})
      vim.fn.chanclose(chan_id)
    end
  end
  if ok and err == 0 then
    for i = 1, #status do
      local line = status[i]
      local icon = line:match("[MUDARCT?]+")
      local file = line:match("[^ ]*$")
      if icon and file then
        -- Extract first char, staged if not space or ? (32 or 63)
        local first = #line > 0 and string.byte(line, 1)
        local is_staged = first ~= 32 and first ~= 63 or nil
        diff_files[file] = { icon:gsub("%?%?", "?"), is_staged }
      end
    end
  end

  return diff_files
end

---@param query string
---@param opts table
---@return string search_query
---@return string? glob_args
M.glob_parse = function(query, opts)
  if not query or not query:find(opts.glob_separator) then
    return query, nil
  end
  local rg_glob_fn = opts.rg_glob_fn or config.globals.grep.rg_glob_fn
  if rg_glob_fn then
    return rg_glob_fn(query, opts)
  end
  local glob_args = ""
  local search_query, glob_str = query:match("(.*)" .. opts.glob_separator .. "(.*)")
  for _, s in ipairs(utils.strsplit(glob_str, "%s+")) do
    if #s > 0 then
      glob_args = glob_args .. ("%s %s "):format(opts.glob_flag, libuv.shellescape(s))
    end
  end
  return search_query, glob_args
end

-- reposition args before ` -e <pattern>` or ` -- <pattern>`
-- enables "-e" and "--fixed-strings --" in `rg_opts` (#781, #794)
---@param cmd string
---@param args string
---@param relocate_pattern string?
---@return string
M.rg_insert_args = function(cmd, args, relocate_pattern)
  local patterns = {}
  for _, a in ipairs({
    { "%s+%-e",  "-e" },
    { "%s+%-%-", "--" },
  }) do
    -- if pattern was specified search for `-e <pattern>`
    -- if pattern was not specified search for `-e<SPACE>` or `-e<EOL>`
    if relocate_pattern and #relocate_pattern > 0 then
      table.insert(patterns, {
        a[1] .. "%s-" .. relocate_pattern .. "%s*",
        a[2] .. " " .. relocate_pattern,
      })
    else
      table.insert(patterns, { a[1] .. "$", a[2] })
      table.insert(patterns, { a[1] .. "%s", a[2] })
    end
  end
  -- if pattern was specified also search for `<pattern>` directly
  if relocate_pattern and #relocate_pattern > 0 then
    table.insert(patterns, { "%s+" .. relocate_pattern .. "%s*", relocate_pattern })
  end
  for _, a in ipairs(patterns) do
    if cmd:match(a[1]) then
      cmd = cmd:gsub(a[1], " ")
      return string.format("%s %s %s", cmd:gsub("%s+$", ""), args:gsub("%s+$", ""), a[2])
    end
  end
  -- cmd doesn't contain `-e` or `--` or <pattern>, concat args
  return string.format("%s %s", cmd, args)
end


---@param s string[]
---@param opts table
---@return string cmd
M.lgrep = function(s, opts)
  -- can be nil when called as fzf initial command
  local query, no_esc = (function()
    -- $FZF_QUERY sends query args as table (#2343)
    if #s > 1 then
      return table.concat(vim.tbl_map(function(x) return libuv.shellescape(x) end, s), " "), 2
    else
      return (s[1] or ""), true
    end
  end)()
  opts.no_esc = nil
  local cmd0 = FzfLua.make_entry.get_grep_cmd(opts, query, no_esc)
  if not opts.exec_empty_query and #query == 0 then
    cmd0 = FzfLua.utils.shell_nop()
  elseif opts.silent_fail ~= false then
    cmd0 = cmd0 .. " || " .. FzfLua.utils.shell_nop()
  end
  if opts.contents or not FzfLua.core.can_transform(opts) then
    return cmd0
  else
    return "reload:" .. cmd0
  end
end

---@param opts table
---@param search_query string
---@param no_esc boolean|number
---@return string?
M.get_grep_cmd = function(opts, search_query, no_esc)
  opts = _G._fzf_lua_is_headless and setmetatable(vim.deepcopy(opts), { __index = opts2 }) or opts
  if opts.raw_cmd and #opts.raw_cmd > 0 then
    return opts.raw_cmd
  end
  local command, is_rg, is_grep = nil, nil, nil
  if opts.cmd and #opts.cmd > 0 then
    command = opts.cmd
  elseif vim.fn.executable("rg") == 1 then
    is_rg = true
    command = string.format("rg %s", opts.rg_opts)
  elseif utils.__IS_WINDOWS then
    utils.warn("Grep requires installing 'rg' on Windows.")
    return nil
  else
    is_grep = true
    command = string.format("grep %s", opts.grep_opts)
  end
  for k, v in pairs({
    follow = opts.toggle_follow_flag or "-L",
    hidden = opts.toggle_hidden_flag or "--hidden",
    no_ignore = opts.toggle_ignore_flag or "--no-ignore",
  }) do
    (function()
      -- Do nothing unless opt was set
      if opts[k] == nil then return end
      command = utils.toggle_cmd_flag(command, v, opts[k])
    end)()
  end

  -- save a copy of the command for `actions.toggle_ignore`
  -- TODO: both `get_grep_cmd` and `get_files_cmd` need to
  -- be reworked into a table of arguments
  opts._cmd = command

  if opts.rg_glob and not command:match("^rg") then
    if not tonumber(opts.rg_glob) and not opts.silent then
      -- Do not display the error message if using the defaults (rg_glob=1)
      utils.warn("'--glob|iglob' flags require 'rg', ignoring 'rg_glob' option.")
    end
    opts.rg_glob = false
  end

  if opts.fn_transform_cmd then
    local new_cmd, new_query = opts.fn_transform_cmd(search_query, command, opts)
    if new_cmd then
      opts.no_esc = true
      opts.search = new_query
      return new_cmd
    end
  elseif opts.rg_glob then
    local new_query, glob_args = M.glob_parse(search_query, opts)
    if glob_args then
      -- since the search string mixes both the query and
      -- glob separators we cannot used unescaped strings
      if not (no_esc or opts.no_esc) then
        new_query = utils.rg_escape(new_query)
        opts.no_esc = true
        opts.search = ("%s%s"):format(new_query,
          search_query:match(opts.glob_separator .. ".*"))
      end
      search_query = new_query
      command = M.rg_insert_args(command, glob_args)
    end
  end

  -- filename takes precedence over directory
  -- filespec takes precedence over all and doesn't shellescape
  -- this is so user can send a file populating command instead
  local search_path = ""
  local print_filename_flags = " --with-filename" .. (is_rg and " --no-heading" or "")
  if opts.filespec and #opts.filespec > 0 then
    search_path = opts.filespec
  elseif opts.filename and #opts.filename > 0 then
    search_path = libuv.shellescape(opts.filename)
    command = M.rg_insert_args(command, print_filename_flags)
  elseif opts.search_paths then
    local search_paths = type(opts.search_paths) == "table"
        -- NOTE: deepcopy to avoid recursive shellescapes with `actions.grep_lgrep`
        and vim.deepcopy(opts.search_paths) or { tostring(opts.search_paths) }
    -- Make paths relative, note this will not work well with resuming if changing
    -- the cwd, this is by design for perf reasons as having to deal with full paths
    -- will result in more code rouets taken in `make_entry.file`
    for i, p in ipairs(search_paths) do
      search_paths[i] = libuv.shellescape(path.relative_to(path.normalize(p), uv.cwd()))
    end
    search_path = table.concat(search_paths, " ")
    if is_grep then
      -- grep requires adding `-r` to command as paths can be either file or directory
      command = M.rg_insert_args(command, print_filename_flags .. " -r")
    elseif #search_paths == 1 then
      command = M.rg_insert_args(command, print_filename_flags)
    end
  end

  search_query = search_query or ""
  if #search_query > 0 and not (no_esc or opts.no_esc) then
    -- For UI consistency, replace the saved search query with the regex
    opts.no_esc = true
    opts.search = utils.rg_escape(search_query)
    search_query = opts.search
  end

  if not opts._ctags_file then
    -- Auto add `--line-number` for grep and `--line-number --column` for rg
    -- NOTE: although rg's `--column` implies `--line-number` we still add
    -- `--line-number` since we remove `--column` when search regex is empty
    local bin = path.tail(command:match("[^%s]+"))
    local bin2flags = {
      grep = { { "--line-number", "-n" }, { "--recursive", "-r" } },
      rg = { { "--line-number", "-n" }, { "--column" } }
    }
    for _, flags in ipairs(bin2flags[bin] or {}) do
      local has_flag_group
      for _, f in ipairs(flags) do
        if command:match("^" .. utils.lua_regex_escape(f))
            or command:match("%s+" .. utils.lua_regex_escape(f))
        then
          has_flag_group = true
        end
      end
      if not has_flag_group then
        if not opts.silent then
          utils.info(
            "Added missing '%s' flag to '%s'. Add 'silent=true' to hide this message.",
            table.concat(flags, "|"), bin)
        end
        command = M.rg_insert_args(command, flags[1])
      end
    end
  end

  -- remove column numbers when search term is empty
  if not opts.no_column_hide and #search_query == 0 then
    command = command:gsub("%s%-%-column", "")
  end

  -- do not escape at all
  if not (no_esc == 2 or opts.no_esc == 2) then
    -- we need to use our own version of 'shellescape'
    -- that doesn't escape '\' on fish shell (#340)
    search_query = libuv.shellescape(search_query)
  end

  ---@param cmd string
  ---@param fzf_field_index string
  ---@return string
  local expand_query = function(cmd, fzf_field_index)
    if opts.contents and cmd:match("<query>") then
      return (cmd:gsub("<query>", fzf_field_index))
    else
      return ("%s %s"):format(cmd, fzf_field_index)
    end
  end

  -- construct the final command
  command = expand_query(command, search_query)
  command = ("%s %s"):format(command, search_path)

  -- piped command filter, used for filtering ctags
  if opts.filter and #opts.filter > 0 then
    command = ("%s | %s"):format(command, opts.filter)
  end
  command = M.fix_windows_cmd(command)

  return command
end


M.fix_windows_cmd = function(cmd)
  if not utils.__IS_WINDOWS or type(cmd) ~= "string" or not cmd:match("!") then
    return cmd
  end
  -- https://ss64.com/nt/syntax-esc.html
  -- This changes slightly if you are running with DelayedExpansion of variables:
  -- if any part of the command line includes an '!' then CMD will escape a second
  -- time, so ^^^^ will become ^
  -- replace in sections, only double the relevant pipe sections with !
  local escaped_cmd = {}
  for _, str in ipairs(utils.strsplit(cmd, "%s+|")) do
    if str:match("!") then
      str = str:gsub('[%(%)%%!%^<>&|"]', function(x)
        return "^" .. x
      end)
      -- make sure all ! are escaped at least twice
      str = str:gsub("[^%^]%^!", function(x)
        return x:sub(1, 1) .. "^" .. x:sub(2)
      end)
    end
    table.insert(escaped_cmd, str)
  end
  return table.concat(escaped_cmd, " |")
end

---@param opts table
---@param query string
---@param cmd string
---@return string
M.expand_query = function(opts, query, cmd)
  -- live_grep replace pattern with last argument
  local argvz = "<query>"
  if cmd:match(argvz) then
    -- The NEQ condition on Windows turned out to be a real pain in the butt
    -- so I decided to move the empty query test into our cmd proxy wrapper
    -- For obvious reasons this cannot work with `live_grep_native` and thus
    -- the NEQ condition remains for the "native" version
    if not opts.exec_empty_query and query == "" then
      -- query is always be the last argument
      cmd = utils.shell_nop()
      return cmd
    end

    -- For custom command transformations (#1927)
    opts.fn_transform_cmd = opts2.fn_transform_cmd

    -- did the caller request rg with glob support?
    -- manipulation needs to be done before the argv replacement
    if opts.fn_transform_cmd then
      local new_cmd, new_query = opts.fn_transform_cmd(query, cmd:gsub(argvz, ""), opts)
      cmd = new_cmd or cmd
      query = new_query or query
    elseif opts.rg_glob then
      local search_query, glob_args = M.glob_parse(query, opts)
      if glob_args then
        -- gsub doesn't like single % on rhs
        search_query = search_query:gsub("%%", "%%%%")
        -- reset argvz so it doesn't get replaced again below
        -- insert glob args before `-- {argvz}` or `-e {argvz}` repositioned
        -- at the end of the command preceding the search query (#781, #794)
        cmd = M.rg_insert_args(cmd, glob_args, argvz)
        query = search_query
      end
    end
    -- nifty hack to avoid having to double escape quotations
    -- see my comment inside 'live_grep' initial_command code
    cmd = cmd:gsub(argvz, libuv.shellescape(query))
  end
  return cmd
end

M.preprocess = function(opts)
  opts.cmd = M.fix_windows_cmd(opts.cmd)

  if opts.cwd_only and not opts.cwd then
    opts.cwd = uv.cwd()
  end

  if opts.file_icons then
    devicons.load()
  end

  if opts.git_icons then
    opts.diff_files = M.get_diff_files(opts)
  end

  -- formatter `to` function
  if opts.formatter and not opts._fmt then
    opts._fmt = opts._fmt or {}
    opts._fmt.to = opts2._fmt.to
    -- Attempt to load from string value `_to`
    if not opts._fmt.to then
      local _to = opts2._fmt._to
      if type(_to) == "string" then
        opts._fmt.to = loadstring(_to)()
      end
    end
  end

  return opts
end

M.postprocess = function(opts)
  if opts.file_icons == "mini" and devicons.PLUGIN and devicons.PLUGIN.update_state_mini then
    devicons.PLUGIN:update_state_mini()
  end
end

M.lcol = function(entry, opts)
  if not entry then return nil end
  local hl_colnr = utils.tbl_contains(opts._cached_hls or {}, "path_colnr")
      and opts.hls.path_colnr or "blue"
  local hl_linenr = utils.tbl_contains(opts._cached_hls or {}, "path_linenr")
      and opts.hls.path_linenr or "green"
  local filename = entry.filename or vim.api.nvim_buf_get_name(entry.bufnr)
  return string.format("%s:%s%s%s",
    -- uncomment to test URIs
    -- "file://" .. filename,
    filename, --utils.ansi_codes.magenta(filename),
    tonumber(entry.lnum) == nil and "" or (utils.ansi_codes[hl_linenr](tostring(entry.lnum)) .. ":"),
    tonumber(entry.col) == nil and "" or (utils.ansi_codes[hl_colnr](tostring(entry.col)) .. ":"),
    type(entry.text) ~= "string" and ""
    or (" " .. (opts and opts.trim_entry and vim.trim(entry.text) or entry.text)))
end

---@param x string
---@param opts table
---@return string? entry
M.file = function(x, opts)
  opts = opts or {}
  local ret = {}
  local icon, hl
  local colon_start_idx = 1
  if utils.__IS_WINDOWS then
    if string.byte(x, #x) == 13 then
      -- strip ^M added by the "dir /s/b" command
      x = x:sub(1, #x - 1)
    end
    if path.is_absolute(x) then
      -- ignore the first colon in the drive spec, e.g c:\
      colon_start_idx = 3
    end
  end
  local colon_idx = x:find(":", colon_start_idx, true) or 0
  local file_part = colon_idx > 1 and x:sub(1, colon_idx - 1) or x
  local rest_of_line = colon_idx > 1 and x:sub(colon_idx) or nil
  -- strip ansi coloring from path so we can use filters
  -- otherwise the ANSI escape sequence will get in the way
  -- TODO: we only support path modification without ANSI
  -- escape sequences, it becomes too expensive to modify
  -- and restore the path with escape sequences
  local stripped_filepath, file_is_ansi = (function()
    if opts.no_ansi_colors then
      return file_part, 0
    else
      return utils.strip_ansi_coloring(file_part)
    end
  end)()
  local filepath = stripped_filepath
  -- fd v8.3 requires adding '--strip-cwd-prefix' to remove
  -- the './' prefix, will not work with '--color=always'
  -- https://github.com/sharkdp/fd/blob/master/CHANGELOG.md
  if opts.strip_cwd_prefix then
    filepath = path.strip_cwd_prefix(filepath)
  end
  if opts.render_crlf then
    filepath = path.render_crlf(filepath)
  end
  -- make path relative
  if opts.cwd and #opts.cwd > 0 then
    filepath = path.relative_to(filepath, opts.cwd)
  end
  if path.is_absolute(filepath) then
    -- filter for cwd only
    if opts.cwd_only then
      local cwd = opts.cwd or uv.cwd()
      if not path.is_relative_to(filepath, cwd) then
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
    filepath = path.shorten(filepath, tonumber(opts.path_shorten),
      -- On Windows we want to shorten using the separator used by the `cwd` arg
      -- otherwise we might have issues "lenghening" as in the case of git which
      -- uses normalized paths (using /) for `rev-parse --show-toplevel` and `ls-files`
      utils.__IS_WINDOWS and opts.cwd and path.separator(opts.cwd))
  end
  if opts.git_icons then
    local diff_info = opts.diff_files
        and opts.diff_files[utils._if_win(path.normalize(origpath), origpath)]
    local indicators = diff_info and diff_info[1] or " "
    for i = 1, #indicators do
      icon = indicators:sub(i, i)
      local git_icon = config.globals.git.icons[icon]
      if git_icon then
        icon = git_icon.icon
        if opts.color_icons then
          -- diff_info[2] contains 'is_staged' var, only the first indicator can be "staged"
          local git_color = diff_info[2] and i == 1 and "green" or git_icon.color or "dark_grey"
          icon = utils.ansi_codes[git_color](icon)
        end
      end
      ret[#ret + 1] = icon
    end
    ret[#ret + 1] = utils.nbsp
  end
  if opts.file_icons then
    icon, hl = devicons.get_devicon(origpath)
    if hl and opts.color_icons then
      icon = utils.ansi_from_rgb(hl, icon)
    end
    ret[#ret + 1] = icon
    ret[#ret + 1] = utils.nbsp
  end
  local _fmt_postfix -- when using `path.filename_first` v2
  if opts._fmt and type(opts._fmt.to) == "function" then
    ret[#ret + 1], _fmt_postfix = opts._fmt.to(filepath, opts, { path = path, utils = utils })
  else
    ret[#ret + 1] = file_is_ansi > 0
        -- filename is ansi escape colored, replace the inner string (#819)
        -- escape `%` in path, since `string.gsub` also use it in target (#1443)
        and file_part:gsub(utils.lua_regex_escape(stripped_filepath), (filepath:gsub("%%", "%%%%")))
        or filepath
  end
  -- multiline is only enabled with grep-like output PATH:LINE:COL:
  if opts.multiline and rest_of_line then
    opts.multiline = tonumber(opts.multiline) or 1
    -- Sould match both colored and non colored versions of
    -- PATH:LINE:TEXT and PATH:LINE:COL:TEXT
    local ansi_num = "[%[%d;m]"
    local filespec = rest_of_line:match(string.format("^:%s-:%s-:", ansi_num, ansi_num))
        or rest_of_line:match(string.format("^:%s-:", ansi_num))
    if filespec then
      rest_of_line = filespec
          .. "\n"
          .. string.rep(" ", 4)
          .. rest_of_line:sub(#filespec + 1)
    end
  end
  ret[#ret + 1] = rest_of_line
  ret[#ret + 1] = _fmt_postfix
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
  -- different alignment fmt if string contains ansi coloring
  -- from rg/grep output when using `tags_grep_xxx`
  local align = utils.has_ansi_coloring(name) and 47 or 30
  local line, tag = text:match("(%d-);?(/.*/)")
  if not tag then
    -- lines with a tag located solely by line number contain nothing but the
    -- number at this point (e.g. using "ctags -R --excmd=number")
    line = text:match("%d+")
  end
  line = line and #line > 0 and tonumber(line)
  return string.format("%-" .. tostring(align) .. "s%s%s%s: %s",
    name,
    utils.nbsp,
    M.file(file, opts),
    not line and "" or ":" .. utils.ansi_codes.green(tostring(line)),
    utils.ansi_codes.blue(tag)
  ), line
end

M.git_status = function(x, opts)
  local function git_iconify(icon, staged)
    local git_icon = config.globals.git.icons[icon]
    if git_icon then
      icon = git_icon.icon
      if opts.color_icons then
        icon = utils.ansi_codes[staged and "green" or git_icon.color or "dark_grey"](icon)
      end
    end
    return icon
  end
  -- unrecognizable format, return
  if not x or #x < 4 then return x end
  -- strip ansi coloring or the pattern matching fails
  -- when git config has `color.status=always` (#706)
  x = utils.strip_ansi_coloring(x)
  -- `man git-status`
  -- we are guaranteed format of: XY <text>
  -- spaced files are wrapped with quotes
  -- remove both git markers and quotes
  local f1, f2 = x:sub(4):gsub([["]], ""), nil
  -- renames separate files with '->'
  if f1:match("%s%->%s") then
    f1, f2 = f1:match("(.*)%s%->%s(.*)")
  end
  f1 = f1 and M.file(f1, opts)
  -- accommodate 'file_ignore_patterns'
  if not f1 then return end
  f2 = f2 and M.file(f2, opts)
  local staged = git_iconify(x:sub(1, 1):gsub("?", " "), true)
  local unstaged = git_iconify(x:sub(2, 2))
  local entry = ("%s%s%s%s%s"):format(
    staged, utils.nbsp, unstaged, utils.nbsp .. utils.nbsp,
    (f2 and ("%s -> %s"):format(f1, f2) or f1))
  return entry
end

M.git_hunk = function(x, opts)
  local entry
  if not opts.__git_hunk_stats then
    opts.__git_hunk_stats = { i = math.huge / 2 }
  end
  -- local ref for easy access
  local S = opts.__git_hunk_stats
  do
    (function()
      local l = utils.strip_ansi_coloring(x)
      -- Skip the first 3 header lines, e.g:
      --    diff --git a/lua/fzf-lua/defaults.lua b/lua/fzf-lua/defaults.lua
      --    index 3354405..799e467 100644
      --    --- a/lua/fzf-lua/defaults.lua
      --    +++ b/lua/fzf-lua/defaults.lua
      if l:match("^diff") then S.i = 0 end
      if S.i < 3 then
        return
      end
      -- Extract filename from the "b-line", e.g:
      --  +++ b/lua/fzf-lua/defaults.lua
      -- NOTE: prefix can also appear as {i|w} (#2151)
      --  --- i/<file>
      --  +++ w/<file>
      if S.i == 3 then
        S.filename = l:match("^%+%+%+ %l/(.*)")
        return
      end
      -- Process only lines that start with + or -
      local byte = string.byte(l, 1)
      if byte == 43 or byte == 45 then
        entry = string.format("%s:%d:%s", M.file(S.filename, opts), S.line, x)
      elseif byte == 64 then
        -- Extract line number
        S.line = tonumber(l:match("^@@ %-%d+,%d+ %+(%d+),%d+ @@"))
      end
      -- Advance line number for non-modified or added lines
      if byte == 32 or byte == 43 then
        S.line = S.line + 1
      end
    end)()
  end
  -- Next line
  S.i = S.i + 1
  return entry
end

M.zoxide = function(x, opts)
  local score, dir = x:match("(%d+%.%d+)%s+(.-)$")
  if not score then return x end
  if opts.cwd then
    dir = path.relative_to(dir, opts.cwd)
  end
  local _fmt_postfix -- when using `path.filename_first` v2
  if opts._fmt and type(opts._fmt.to) == "function" then
    dir, _fmt_postfix = opts._fmt.to(dir, opts, { path = path, utils = utils })
  end
  return string.format("%8s\t%s%s", tostring(score), dir, _fmt_postfix or "")
end

return M
