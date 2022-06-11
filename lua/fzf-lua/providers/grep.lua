local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"
local make_entry = require "fzf-lua.make_entry"

local function get_last_search(opts)
  if opts.__MODULE__ and opts.__MODULE__.get_last_search then
    return opts.__MODULE__.get_last_search(opts)
  end
  local last_search = config.globals.grep._last_search or {}
  return last_search.query, last_search.no_esc
end

local function set_last_search(opts, query, no_esc)
  if opts.__MODULE__ and opts.__MODULE__.set_last_search then
    opts.__MODULE__.set_last_search(opts, query, no_esc)
    return
  end
  config.globals.grep._last_search = {
    query = query,
    no_esc = no_esc
  }
  if config.__resume_data then
    config.__resume_data.last_query = query
  end
end

local function set_live_grep_prompt(prompt)
  -- prefix all live_grep prompts with an asterisk
  return prompt:match("^%*") and prompt or '*'..prompt
end

local M = {}

local get_grep_cmd = function(opts, search_query, no_esc)
  if opts.raw_cmd and #opts.raw_cmd>0 then
    return opts.raw_cmd
  end
  local command = nil
  if opts.cmd and #opts.cmd > 0 then
    command = opts.cmd
  elseif vim.fn.executable("rg") == 1 then
    command = string.format("rg %s", opts.rg_opts)
  else
    command = string.format("grep %s", opts.grep_opts)
  end

  if opts.rg_glob and not command:match("^rg") then
    opts.rg_glob = false
    utils.warn("'--glob|iglob' flags require 'rg', ignoring 'rg_glob' option.")
  end

  if opts.rg_glob then
    local new_query, glob_args = make_entry.glob_parse(opts, search_query)
    if glob_args then
      -- since the search string mixes both the query and
      -- glob separators we cannot used unescaped strings
      if not (no_esc or opts.no_esc) then
        new_query = utils.rg_escape(new_query)
        opts.no_esc = true
        opts.search = ("%s%s"):format(new_query,
          search_query:match(opts.glob_separator..".*"))
      end
      search_query = new_query
      command = ("%s %s"):format(command, glob_args)
    end
  end

  -- filename takes precedence over directory
  -- filespec takes precedence over all and doesn't shellescape
  -- this is so user can send a file populating command instead
  local search_path = ''
  if opts.filespec and #opts.filespec>0 then
    search_path = opts.filespec
  elseif opts.filename and #opts.filename>0 then
    search_path = libuv.shellescape(opts.filename)
  end

  search_query = search_query or ''
  if not (no_esc or opts.no_esc) then
    search_query = utils.rg_escape(search_query)
  end

  -- remove column numbers when search term is empty
  if not opts.no_column_hide and #search_query==0 then
    command = command:gsub("%s%-%-column", "")
  end

  -- do not escape at all
  if not (no_esc == 2 or opts.no_esc == 2) then
    -- we need to use our own version of 'shellescape'
    -- that doesn't escape '\' on fish shell (#340)
    search_query = libuv.shellescape(search_query)
  end

  -- construct the final command
  command = ('%s %s %s'):format(command, search_query, search_path)

  -- piped command filter, used for filtering ctags
  if opts.filter and #opts.filter>0 then
    command = ("%s | %s"):format(command, opts.filter)
  end

  return command
end

M.grep = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  -- we need this for 'actions.grep_lgrep'
  opts.__MODULE__ = opts.__MODULE__ or M

  local no_esc = false
  if not opts.search and
    (opts.continue_last_search or opts.repeat_last_search) then
    opts.search, no_esc = get_last_search(opts)
    opts.search = opts.search or opts.continue_last_search_default
  end

  -- if user did not provide a search term
  -- provide an input prompt
  if not opts.search and not opts.raw_cmd then
    opts.search = utils.input(opts.input_prompt) or ''
  end

  -- search query in header line
  opts = core.set_header(opts, opts.headers or {"actions","cwd","search"})

  -- get the grep command before saving the last search
  -- incase the search string is overwritten by 'rg_glob'
  opts.cmd = get_grep_cmd(opts, opts.search, no_esc)

  -- save the search query so we
  -- can call the same search again
  set_last_search(opts, opts.search, no_esc or opts.no_esc)

  local contents = core.mt_cmd_wrapper(vim.tbl_deep_extend("force", opts,
    -- query was already parsed for globs inside 'get_grep_cmd'
    -- no need for our external headless instance to parse again
    { rg_glob = false }))

  -- by redirecting the error stream to stdout
  -- we make sure a clear error message is displayed
  -- when the user enters bad regex expressions
  if type(contents) == 'string' then
    contents = contents .. " 2>&1"
  end

  -- when using an empty string grep (as in 'grep_project') or
  -- when switching from grep to live_grep using 'ctrl-g' users
  -- may find it confusing why is the last typed query not
  -- considered the last search so we find out if that's the
  -- case and use the last typed prompt as the grep string
  opts.fn_post_fzf = function(o, _)
    local last_search, _ = get_last_search(o)
    local last_query = config.__resume_data and config.__resume_data.last_query
    if not last_search or #last_search==0
       and (last_query and #last_query>0) then
      set_last_search(opts, last_query)
    end
  end

  opts = core.set_fzf_field_index(opts)
  core.fzf_files(opts, contents)
end

-- single threaded version
M.live_grep_st = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  -- we need this for 'actions.grep_lgrep'
  opts.__MODULE__ = opts.__MODULE__ or M
  opts.prompt = set_live_grep_prompt(opts.prompt)

  assert(not opts.multiprocess)

  local no_esc = false
  if not opts.search and
    (opts.continue_last_search or opts.repeat_last_search) then
    opts.search, no_esc = get_last_search(opts)
  end

  opts.query = opts.search or ''
  if opts.search and #opts.search>0 then
    -- escape unless the user requested not to
    if not (no_esc or opts.no_esc) then
      opts.query = utils.rg_escape(opts.search)
    end
    -- save the search query so the use can
    -- call the same search again
    set_last_search(opts, opts.query, true)
  end

  -- search query in header line
  opts = core.set_header(opts, opts.headers or {"actions","cwd"})

  opts._reload_command = function(query)
    if query and not (opts.save_last_search == false) then
      set_last_search(opts, query, true)
    end
    -- can be nil when called as fzf initial command
    query = query or ''
    opts.no_esc = nil
    return get_grep_cmd(opts, query, true)
  end

  if opts.requires_processing or opts.git_icons or opts.file_icons then
    opts._fn_transform = opts._fn_transform
      or function(x)
        return core.make_entry_file(opts, x)
      end
  end

  -- see notes for this section in 'live_grep_mt'
  if not opts._is_skim then
    opts.save_query = true
    opts.fn_post_fzf = function(o, _)
      local last_search, _ = get_last_search(o)
      local last_query = config.__resume_data and config.__resume_data.last_query
      if not opts.exec_empty_query
        and last_search ~= last_query then
        set_last_search(opts, last_query or '')
      end
    end
  end

  -- disable global resume
  -- conflicts with 'change:reload' event
  opts.global_resume_query = false
  opts.__FNCREF__ = opts.__FNCREF__ or utils.__FNCREF__()
  opts = core.set_fzf_field_index(opts)
  opts = core.set_fzf_interactive_cmd(opts)
  core.fzf_files(opts)
end


-- multi threaded (multi-process actually) version
M.live_grep_mt = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  -- we need this for 'actions.grep_lgrep'
  opts.__MODULE__ = opts.__MODULE__ or M
  opts.__module__ = opts.__module__ or 'grep'
  opts.prompt = set_live_grep_prompt(opts.prompt)

  -- when using glob parsing we must use the external
  -- headless instance for processing the query, this
  -- prevents 'file|git_icons=false' from overriding
  -- processing inside 'core.mt_cmd_wrapper'
  if opts.rg_glob then
    opts.requires_processing = true
  end

  assert(opts.multiprocess)

  local no_esc = false
  if not opts.search and
    (opts.continue_last_search or opts.repeat_last_search) then
    opts.search, no_esc = get_last_search(opts)
  end

  local query = opts.search or ''
  if opts.search and #opts.search>0 then
    -- escape unless the user requested not to
    if not (no_esc or opts.no_esc) then
      query = utils.rg_escape(opts.search)
    end
    -- save the search query so the use can
    -- call the same search again
    set_last_search(opts, query, true)
  end

  -- search query in header line
  opts = core.set_header(opts, opts.headers or {"actions","cwd"})

  -- signal to preprocess we are looking to replace {argvz}
  opts.argv_expr = true

  -- fzf already adds single quotes around the placeholder when expanding
  -- for skim we surround it with double quotes or single quote searches fail
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')
  opts.cmd = get_grep_cmd(opts , placeholder, 2)
  local initial_command = core.mt_cmd_wrapper(opts)
  if initial_command ~= opts.cmd then
    -- this means mt_cmd_wrapper wrapped the command
    -- since now the `rg` command is wrapped inside
    -- the shell escaped '--headless .. --cmd' we won't
    -- be able to search single quotes as it will break
    -- the escape sequence so we use a nifty trick
    --   * replace the placeholder with {argv1}
    --   * re-add the placeholder at the end of the command
    --   * preprocess then relaces it with vim.fn.argv(1)
    -- NOTE: since we cannot guarantee the positional index
    -- of arguments (#291) we use the last argument instead
    initial_command = initial_command:gsub(placeholder, "{argvz}")
      .. " " .. placeholder
  end
  -- by redirecting the error stream to stdout
  -- we make sure a clear error message is displayed
  -- when the user enters bad regex expressions
  initial_command = initial_command .. " 2>&1"
  local reload_command = initial_command
  if not opts.exec_empty_query then
    reload_command =  ('[ -z %s ] || %s'):format(placeholder, reload_command)
  end
  if opts._is_skim then
    -- skim interactive mode does not need a piped command
    opts.fzf_fn = nil
    opts.fzf_opts['--prompt'] = opts.prompt:match("[^%*]+")
    opts.fzf_opts['--cmd-prompt'] = vim.fn.shellescape(opts.prompt)
    opts.prompt = nil
    -- since we surrounded the skim placeholder with quotes
    -- we need to escape them in the initial query
    opts.fzf_opts['--cmd-query'] = libuv.shellescape(utils.sk_escape(query))
    opts._fzf_cli_args = string.format("-i -c %s",
          vim.fn.shellescape(reload_command))
  else
    opts.fzf_fn = {}
    if opts.exec_empty_query or (opts.search and #opts.search > 0) then
      opts.fzf_fn = initial_command:gsub(placeholder,
        libuv.shellescape(query:gsub("%%", "%%%%")))
    end
    opts.fzf_opts['--phony'] = ''
    opts.fzf_opts['--query'] = libuv.shellescape(query)
    opts._fzf_cli_args = string.format('--bind=%s',
        vim.fn.shellescape(("change:reload:%s"):format(
          ("%s || true"):format(reload_command))))
  end

  -- when running 'live_grep' with 'exec_empty_query=false' (default)
  -- an empty typed query will not be saved as the 'neovim --headless'
  -- command isn't executed resulting in '_last_search.query' never
  -- cleared, always having a minimum of one characer.
  -- this signals 'core.fzf' to add the '--print-query' flag and
  -- handle the typed query on process exit using 'opts.fn_save_query'
  -- due to a skim bug this doesn't work when used in conjucntion with
  -- the '--interactive' flag, the line with the typed query is printed
  -- to stdout but is always empty
  -- to understand this issue, run 'live_grep', type a query and then
  -- delete it and press <C-i> to switch to 'grep', instead of an empty
  -- search the last typed character will be used as the search string
  if not opts._is_skim then
    opts.save_query = true
    opts.fn_post_fzf = function(o, _)
      local last_search, _ = get_last_search(o)
      local last_query = config.__resume_data and config.__resume_data.last_query
      if not opts.exec_empty_query
        and last_search ~= last_query then
        set_last_search(opts, last_query or '')
      end
    end
  end

  -- disable global resume
  -- conflicts with 'change:reload' event
  opts.global_resume_query = false
  opts.__FNCREF__ = opts.__FNCREF__ or utils.__FNCREF__()
  opts = core.set_fzf_field_index(opts)
  core.fzf_files(opts)
  opts.search = nil
end

M.live_grep_glob_st = function(opts)

  if vim.fn.executable("rg") ~= 1 then
    utils.warn("'--glob|iglob' flags requires 'rg' (https://github.com/BurntSushi/ripgrep)")
    return
  end

  -- 'rg_glob = true' enables glob
  -- processsing in 'get_grep_cmd'
  opts = opts or {}
  opts.rg_glob = true
  return M.live_grep_st(opts)
end

M.live_grep_glob_mt = function(opts)

  if vim.fn.executable("rg") ~= 1 then
    utils.warn("'--glob|iglob' flags requires 'rg' (https://github.com/BurntSushi/ripgrep)")
    return
  end

  -- 'rg_glob = true' enables the glob processsing in
  -- 'make_entry.preprocess', only supported with multiprocess
  opts = opts or {}
  opts.rg_glob = true
  return M.live_grep_mt(opts)
end

M.live_grep_native = function(opts)

  -- backward compatibility, by setting git|files icons to false
  -- we forces mt_cmd_wrapper to pipe the command as is so fzf
  -- runs the command directly in the 'change:reload' event
  opts = opts or {}
  opts.git_icons = false
  opts.file_icons = false
  opts.rg_glob = false
  -- disable ctrl-g switch by default
  if not opts.actions or not opts.actions["ctrl-g"] then
    opts.actions = opts.actions or {}
    opts.actions["ctrl-g"] = false
  end
  opts.__FNCREF__ = utils.__FNCREF__()
  return M.live_grep_mt(opts)
end

M.live_grep = function(opts)
  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  opts.__FNCREF__ = opts.__FNCREF__ or utils.__FNCREF__()

  if opts.multiprocess then
    return M.live_grep_mt(opts)
  else
    return M.live_grep_st(opts)
  end
end

M.live_grep_glob = function(opts)
  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  opts.__FNCREF__ = opts.__FNCREF__ or utils.__FNCREF__()

  if opts.multiprocess then
    return M.live_grep_glob_mt(opts)
  else
    return M.live_grep_glob_st(opts)
  end
end

M.live_grep_resume = function(opts)
  if not opts then opts = {} end
  if not opts.search then
    opts.continue_last_search =
      (opts.continue_last_search == nil and
      opts.repeat_last_search == nil and true) or
      (opts.continue_last_search or opts.repeat_last_search)
  end
  return M.live_grep(opts)
end

M.grep_last = function(opts)
  if not opts then opts = {} end
  opts.continue_last_search = true
  return M.grep(opts)
end

M.grep_cword = function(opts)
  if not opts then opts = {} end
  opts.search = vim.fn.expand("<cword>")
  return M.grep(opts)
end

M.grep_cWORD = function(opts)
  if not opts then opts = {} end
  opts.search = vim.fn.expand("<cWORD>")
  return M.grep(opts)
end

M.grep_visual = function(opts)
  if not opts then opts = {} end
  opts.search = utils.get_visual_selection()
  return M.grep(opts)
end

M.grep_project = function(opts)
  if not opts then opts = {} end
  if not opts.search then opts.search = '' end
  -- by default, do not include filename in search
  if not opts.fzf_opts or opts.fzf_opts["--nth"] == nil then
    opts.fzf_opts = opts.fzf_opts or {}
    opts.fzf_opts["--nth"] = '2..'
  end
  return M.grep(opts)
end

M.grep_curbuf = function(opts)
  -- we can't call 'normalize_opts' here because it will override
  -- 'opts.__call_opts' which will confuse 'actions.grep_lgrep'
  if type(opts) == 'function' then
    opts = opts()
  elseif not opts then
    opts = {}
  end
  -- rg globs are meaningless here since we searching
  -- a single file
  opts.rg_glob = false
  opts.rg_opts = config.globals.grep.rg_opts .. " --with-filename"
  opts.grep_opts = config.globals.grep.grep_opts .. " --with-filename"
  if opts.exec_empty_query == nil then
    opts.exec_empty_query = true
  end
  opts.fzf_opts = vim.tbl_extend("keep",
    opts.fzf_opts or {}, config.globals.blines.fzf_opts)
  opts.filename = vim.api.nvim_buf_get_name(0)
  if #opts.filename > 0 and vim.loop.fs_stat(opts.filename) then
    opts.filename = path.relative(opts.filename, vim.loop.cwd())
    if opts.lgrep then
      return M.live_grep(opts)
    else
      opts.search = opts.search or ''
      return M.grep(opts)
    end
  else
    utils.info("Rg current buffer requires file on disk")
    return
  end
end

M.lgrep_curbuf = function(opts)
  if not opts then opts = {} end
  opts.lgrep = true
  return M.grep_curbuf(opts)
end

return M
