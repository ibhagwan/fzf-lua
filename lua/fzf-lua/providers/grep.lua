local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"
local make_entry = require "fzf-lua.make_entry"

local M = {}

---@param opts table
---@param search_query string
---@param no_esc boolean|number
---@return string?
local get_grep_cmd = function(opts, search_query, no_esc)
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

  -- save a copy of the command for `actions.toggle_ignore`
  -- TODO: both `get_grep_cmd` and `get_files_cmd` need to
  -- be reworked into a table of arguments
  opts._cmd = command

  if opts.rg_glob and not command:match("^rg") then
    opts.rg_glob = false
    utils.warn("'--glob|iglob' flags require 'rg', ignoring 'rg_glob' option.")
  end

  if opts.rg_glob then
    local new_query, glob_args = make_entry.glob_parse(search_query, opts)
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
      command = make_entry.rg_insert_args(command, glob_args)
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
    command = make_entry.rg_insert_args(command, print_filename_flags)
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
      command = make_entry.rg_insert_args(command, print_filename_flags .. " -r")
    end
  end

  search_query = search_query or ""
  if #search_query > 0 and not (no_esc or opts.no_esc) then
    -- For UI consistency, replace the saved search query with the regex
    opts.no_esc = true
    opts.search = utils.rg_escape(search_query)
    search_query = opts.search
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

  -- construct the final command
  command = ("%s %s %s"):format(command, search_query, search_path)

  -- piped command filter, used for filtering ctags
  if opts.filter and #opts.filter > 0 then
    command = ("%s | %s"):format(command, opts.filter)
  end

  return command
end

M.grep = function(opts)
  opts = config.normalize_opts(opts, "grep")
  if not opts then return end

  -- we need this for `actions.grep_lgrep`
  opts.__ACT_TO = opts.__ACT_TO or M.live_grep

  if not opts.search and not opts.raw_cmd then
    -- resume implies no input prompt
    if opts.resume then
      opts.search = ""
    else
      -- if user did not provide a search term prompt for one
      local search = utils.input(opts.input_prompt)
      -- empty string is not falsy in lua, abort if the user cancels the input
      if search then
        opts.search = search
        -- save the search query for `resume=true`
        opts.__call_opts.search = search
      else
        return
      end
    end
  end

  -- get the grep command before saving the last search
  -- in case the search string is overwritten by 'rg_glob'
  opts.cmd = get_grep_cmd(opts, opts.search, opts.no_esc)
  if not opts.cmd then return end

  local contents = core.mt_cmd_wrapper(vim.tbl_deep_extend("force", opts,
    -- query was already parsed for globs inside 'get_grep_cmd'
    -- no need for our external headless instance to parse again
    { rg_glob = false }))

  -- by redirecting the error stream to stdout
  -- we make sure a clear error message is displayed
  -- when the user enters bad regex expressions
  if type(contents) == "string" then
    contents = contents .. " 2>&1"
  end

  -- search query in header line
  opts = core.set_header(opts, opts.headers or { "actions", "cwd", "search" })
  opts = core.set_fzf_field_index(opts)
  core.fzf_exec(contents, opts)
end

local function normalize_live_grep_opts(opts)
  -- disable treesitter as it collides with cmd regex highlighting
  opts = opts or {}
  opts._treesitter = false

  opts = config.normalize_opts(opts, "grep")
  if not opts then return end

  -- we need this for `actions.grep_lgrep`
  opts.__ACT_TO = opts.__ACT_TO or M.grep

  -- used by `actions.toggle_ignore', normalize_opts sets `__call_fn`
  -- to the calling function  which will resolve to this fn), we need
  -- to deref one level up to get to `live_grep_{mt|st}`
  opts.__call_fn = utils.__FNCREF2__()

  -- prepend prompt with "*" to indicate "live" query
  opts.prompt = type(opts.prompt) == "string" and opts.prompt or ""
  if opts.live_ast_prefix ~= false then
    opts.prompt = opts.prompt:match("^%*") and opts.prompt or ("*" .. opts.prompt)
  end

  -- when using live_grep there is no "query", the prompt input
  -- is a regex expression and should be saved as last "search"
  -- this callback overrides setting "query" with "search"
  opts.__resume_set = function(what, val, o)
    if what == "query" then
      config.resume_set("search", val, { __resume_key = o.__resume_key })
      config.resume_set("no_esc", true, { __resume_key = o.__resume_key })
      utils.map_set(config, "__resume_data.last_query", val)
      -- also store query for `fzf_resume` (#963)
      utils.map_set(config, "__resume_data.opts.query", val)
      -- store in opts for convenience in action callbacks
      o.last_query = val
    else
      config.resume_set(what, val, { __resume_key = o.__resume_key })
    end
  end
  -- we also override the getter for the quickfix list name
  opts.__resume_get = function(what, o)
    return config.resume_get(
      what == "query" and "search" or what,
      { __resume_key = o.__resume_key })
  end

  -- when using an empty string grep (as in 'grep_project') or
  -- when switching from grep to live_grep using 'ctrl-g' users
  -- may find it confusing why is the last typed query not
  -- considered the last search so we find out if that's the
  -- case and use the last typed prompt as the grep string
  if not opts.search or #opts.search == 0 and (opts.query and #opts.query > 0) then
    -- fuzzy match query needs to be regex escaped
    opts.no_esc = nil
    opts.search = opts.query
    -- also replace in `__call_opts` for `resume=true`
    opts.__call_opts.query = nil
    opts.__call_opts.no_esc = nil
    opts.__call_opts.search = opts.query
  end

  -- interactive interface uses 'query' parameter
  opts.query = opts.search or ""
  if opts.search and #opts.search > 0 then
    -- escape unless the user requested not to
    if not opts.no_esc then
      opts.query = utils.rg_escape(opts.search)
    end
  end

  return opts
end

-- single threaded version
M.live_grep_st = function(opts)
  opts = normalize_live_grep_opts(opts)
  if not opts then return end

  assert(not opts.multiprocess)

  opts.fn_reload = function(query)
    -- can be nil when called as fzf initial command
    query = query or ""
    opts.no_esc = nil
    return get_grep_cmd(opts, query, true)
  end

  if opts.requires_processing or opts.git_icons or opts.file_icons then
    opts.fn_transform = opts.fn_transform or
        function(x)
          return make_entry.file(x, opts)
        end
    opts.fn_preprocess = opts.fn_preprocess or
        function(o)
          return make_entry.preprocess(o)
        end
  end

  -- search query in header line
  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = core.set_fzf_field_index(opts)
  core.fzf_exec(nil, opts)
end

-- multi threaded (multi-process actually) version
M.live_grep_mt = function(opts)
  opts = normalize_live_grep_opts(opts)
  if not opts then return end

  assert(opts.multiprocess)

  -- when using glob parsing, we must use the external
  -- headless instance for processing the query. This
  -- prevents 'file|git_icons=false' from overriding
  -- processing inside 'core.mt_cmd_wrapper'
  if opts.rg_glob then
    opts.requires_processing = true
  end

  -- signal to preprocess we are looking to replace {argvz}
  opts.argv_expr = true

  -- this will be replaced by the appropriate fzf
  -- FIELD INDEX EXPRESSION by 'fzf_exec'
  opts.cmd = get_grep_cmd(opts, core.fzf_query_placeholder, 2)
  if not opts.cmd then return end

  local command = core.mt_cmd_wrapper(opts)

  -- signal 'fzf_exec' to set 'change:reload' parameters
  -- or skim's "interactive" mode (AKA "live query")
  opts.fn_reload = command

  -- search query in header line
  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = core.set_fzf_field_index(opts)
  core.fzf_exec(nil, opts)
end

M.live_grep_glob_st = function(opts)
  if vim.fn.executable("rg") ~= 1 then
    utils.warn("'--glob|iglob' flags requires 'rg' (https://github.com/BurntSushi/ripgrep)")
    return
  end

  -- 'rg_glob = true' enables glob
  -- processing in 'get_grep_cmd'
  opts = opts or {}
  opts.rg_glob = true
  return M.live_grep_st(opts)
end

M.live_grep_glob_mt = function(opts)
  if vim.fn.executable("rg") ~= 1 then
    utils.warn("'--glob|iglob' flags requires 'rg' (https://github.com/BurntSushi/ripgrep)")
    return
  end

  -- 'rg_glob = true' enables the glob processing in
  -- 'make_entry.preprocess', only supported with multiprocess
  opts = opts or {}
  opts.rg_glob = true
  return M.live_grep_mt(opts)
end

M.live_grep_native = function(opts)
  -- backward compatibility, by setting git|files icons to false
  -- we force 'mt_cmd_wrapper' to pipe the command as is, so fzf
  -- runs the command directly in the 'change:reload' event
  opts = opts or {}
  opts.git_icons = false
  opts.file_icons = false
  opts.path_shorten = false
  opts.formatter = false
  opts.rg_glob = false
  opts.multiprocess = true
  return M.live_grep_mt(opts)
end

M.live_grep = function(opts)
  opts = config.normalize_opts(opts, "grep")
  if not opts then return end

  if opts.multiprocess then
    return M.live_grep_mt(opts)
  else
    return M.live_grep_st(opts)
  end
end

M.live_grep_glob = function(opts)
  opts = config.normalize_opts(opts, "grep")
  if not opts then return end

  if opts.multiprocess then
    return M.live_grep_glob_mt(opts)
  else
    return M.live_grep_glob_st(opts)
  end
end

M.live_grep_resume = function(opts)
  if not opts then opts = {} end
  opts.resume = true
  return M.live_grep(opts)
end

M.grep_last = function(opts)
  if not opts then opts = {} end
  opts.resume = true
  return M.grep(opts)
end

M.grep_cword = function(opts)
  if not opts then opts = {} end
  opts.no_esc = true
  -- match whole words only (#968)
  opts.search = [[\b]] .. utils.rg_escape(vim.fn.expand("<cword>")) .. [[\b]]
  return M.grep(opts)
end

M.grep_cWORD = function(opts)
  if not opts then opts = {} end
  opts.no_esc = true
  -- match neovim's WORD, match only surrounding space|SOL|EOL
  opts.search = [[(^|\s)]] .. utils.rg_escape(vim.fn.expand("<cWORD>")) .. [[($|\s)]]
  return M.grep(opts)
end

M.grep_visual = function(opts)
  if not opts then opts = {} end
  opts.search = utils.get_visual_selection()
  return M.grep(opts)
end

M.grep_project = function(opts)
  if not opts then opts = {} end
  if not opts.search then opts.search = "" end
  -- by default, do not include filename in search
  opts.fzf_opts = opts.fzf_opts or {}
  if opts.fzf_opts["--delimiter"] == nil then
    opts.fzf_opts["--delimiter"] = ":"
  end
  if opts.fzf_opts["--nth"] == nil then
    opts.fzf_opts["--nth"] = "3.."
  end
  return M.grep(opts)
end

M.grep_curbuf = function(opts, lgrep)
  -- call `normalize_opts` here as we want to store all previous
  -- options in the resume data store under the key "bgrep"
  -- 3rd arg is an override for resume data store lookup key
  opts = config.normalize_opts(opts, "grep_curbuf", "bgrep")
  if not opts then return end

  opts.filename = vim.api.nvim_buf_get_name(core.CTX().bufnr)
  if #opts.filename == 0 or not uv.fs_stat(opts.filename) then
    utils.info("Rg current buffer requires file on disk")
    return
  else
    opts.filename = path.relative_to(opts.filename, uv.cwd())
  end

  -- Persist call options so we don't revert to global grep on `grep_lgrep`
  opts.__call_opts = vim.tbl_deep_extend("keep",
    opts.__call_opts or {}, config.globals.grep_curbuf)
  opts.__call_opts.filename = opts.filename

  if lgrep then
    return M.live_grep(opts)
  else
    opts.search = opts.search or ""
    return M.grep(opts)
  end
end

M.lgrep_curbuf = function(opts)
  -- 2nd arg implies `opts.lgrep=true`
  return M.grep_curbuf(opts, true)
end

local files_from_qf = function(loclist)
  local dedup = {}
  for _, l in ipairs(loclist and vim.fn.getloclist(0) or vim.fn.getqflist()) do
    local fname = l.filename or vim.api.nvim_buf_get_name(l.bufnr)
    if fname and #fname > 0 then
      dedup[fname] = true
    end
  end
  return vim.tbl_keys(dedup)
end

local grep_list = function(opts, lgrep, loclist)
  if type(opts) == "function" then
    opts = opts()
  elseif not opts then
    opts = {}
  end
  opts.search_paths = files_from_qf(loclist)
  if utils.tbl_isempty(opts.search_paths) then
    utils.info((loclist and "Location" or "Quickfix")
      .. " list is empty or does not contain valid file buffers.")
    return
  end
  opts.exec_empty_query = opts.exec_empty_query == nil and true
  opts = config.normalize_opts(opts, "grep")
  if not opts then return end
  if lgrep then
    return M.live_grep(opts)
  else
    opts.search = opts.search or ""
    return M.grep(opts)
  end
end

M.grep_quickfix = function(opts)
  return grep_list(opts, false, false)
end

M.lgrep_quickfix = function(opts)
  return grep_list(opts, true, false)
end

M.grep_loclist = function(opts)
  return grep_list(opts, false, true)
end

M.lgrep_loclist = function(opts)
  return grep_list(opts, true, true)
end

return M
