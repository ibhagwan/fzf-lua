local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local last_search = {}

local M = {}

local get_grep_cmd = function(opts, search_query, no_esc)
  if opts.cmd_fn and type(opts.cmd_fn) == 'function' then
    return opts.cmd_fn(opts, search_query, no_esc)
  end
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

  -- filename takes precedence over directory
  -- filespec takes precedence over all and doesn't shellescape
  -- this is so user can send a file populating command instead
  local search_path = ''
  if opts.filespec and #opts.filespec>0 then
    search_path = opts.filespec
  elseif opts.filename and #opts.filename>0 then
    search_path = vim.fn.shellescape(opts.filename)
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
    search_query = vim.fn.shellescape(search_query)
  end

  return string.format('%s %s %s', command, search_query, search_path)
end

M.grep = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  local no_esc = false
  if opts.continue_last_search or opts.repeat_last_search then
    no_esc = last_search.no_esc
    opts.search = last_search.query
  end

  -- if user did not provide a search term
  -- provide an input prompt
  if not opts.search then
    opts.search = vim.fn.input(opts.input_prompt) or ''
  end

  --[[ if not opts.search or #opts.search == 0 then
    utils.info("Please provide a valid search string")
    return
  end ]]

  -- search query in header line
  opts = core.set_header(opts)

  -- save the search query so the use can
  -- call the same search again
  last_search = {}
  last_search.no_esc = no_esc or opts.no_esc
  last_search.query = opts.search

  opts.cmd = get_grep_cmd(opts, opts.search, no_esc)
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts, contents)
  opts.search = nil
end

M.live_grep = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  local no_esc = false
  if opts.continue_last_search or opts.repeat_last_search then
    no_esc = last_search.no_esc
    opts.search = last_search.query
  end

  opts.query = opts.search or ''
  if opts.search and #opts.search>0 then
    -- save the search query so the use can
    -- call the same search again
    last_search = {}
    last_search.no_esc = true
    last_search.query = opts.search
    -- escape unless the user requested not to
    if not (no_esc or opts.no_esc) then
      opts.query = utils.rg_escape(opts.search)
    end
  end

  -- search query in header line
  opts = core.set_header(opts, 2)

  opts._reload_command = function(query)
    if query and not (opts.save_last_search == false) then
      last_search = {}
      last_search.no_esc = true
      last_search.query = query
    end
    -- can be nill when called as fzf initial command
    query = query or ''
    -- TODO: need to empty filespec
    -- fix this collision, rename to _filespec
    opts.no_esc = nil
    opts.filespec = nil
    return get_grep_cmd(opts, query, true)
  end

  if opts.experimental and (opts.git_icons or opts.file_icons) then
    opts._fn_transform = function(x)
      return core.make_entry_file(opts, x)
    end
  end

  opts = core.set_fzf_line_args(opts)
  opts = core.set_fzf_interactive_cmd(opts)
  core.fzf_files(opts)
end

M.live_grep_native = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)
  if not opts then return end

  local no_esc = false
  if opts.continue_last_search or opts.repeat_last_search then
    no_esc = last_search.no_esc
    opts.search = last_search.query
  end

  local query = opts.search or ''
  if opts.search and #opts.search>0 then
    -- save the search query so the use can
    -- call the same search again
    last_search = {}
    last_search.no_esc = no_esc or opts.no_esc
    last_search.query = opts.search
    -- escape unless the user requested not to
    if not (no_esc or opts.no_esc) then
      query = utils.rg_escape(opts.search)
    end
  end

  -- search query in header line
  opts = core.set_header(opts, 2)

  -- we do not process any entries in the 'native' version as
  -- fzf runs the command directly in the 'change:reload' event
  -- since the introduction of 'libuv.spawn_stdio' with '--headless'
  -- we can now run the command externally with minimal overhead
  if not opts.multiprocess then
    opts.git_icons = false
    opts.file_icons = false
  end

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
    --   * spawn_stdio then relaces it with vim.fn.argv(1)
    initial_command = initial_command:gsub(placeholder, "{argv1}")
      .. " " .. placeholder
  end
  local reload_command = initial_command
  if not opts.exec_empty_query then
    reload_command =  ('[ -z %s ] || %s'):format(placeholder, reload_command)
  end
  if opts._is_skim then
    -- skim interactive mode does not need a piped command
    opts.fzf_fn = nil
    opts.fzf_opts['--prompt'] = '*' .. opts.prompt
    opts.fzf_opts['--cmd-prompt'] = vim.fn.shellescape(opts.prompt)
    -- since we surrounded the skim placeholder with quotes
    -- we need to escape them in the initial query
    opts.fzf_opts['--cmd-query'] = vim.fn.shellescape(utils.sk_escape(query))
    opts._fzf_cli_args = string.format("-i -c %s",
          vim.fn.shellescape(reload_command))
  else
    opts.fzf_fn = {}
    if opts.exec_empty_query or (opts.search and #opts.search > 0) then
      -- must empty opts.cmd first
      opts.cmd = nil
      opts.cmd = get_grep_cmd(opts , opts.search, false)
      opts.fzf_fn = core.mt_cmd_wrapper(opts)
    end
    opts.fzf_opts['--phony'] = ''
    opts.fzf_opts['--query'] = vim.fn.shellescape(query)
    opts._fzf_cli_args = string.format('--bind=%s',
        vim.fn.shellescape(("change:reload:%s"):format(
          ("%s || true"):format(reload_command))))
  end

  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts)
  opts.search = nil
end

M.live_grep_sk = function(opts)
  if not opts then opts = {} end
  opts.fzf_bin = "sk"
  M.live_grep(opts)
end

M.live_grep_fzf = function(opts)
  if not opts then opts = {} end
  opts.fzf_bin = "fzf"
  M.live_grep(opts)
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

M.live_grep_glob = function(opts)
  if not opts then opts = {} end
  if vim.fn.executable("rg") ~= 1 then
    utils.warn("'--glob|iglob' flags requires 'rg' (https://github.com/BurntSushi/ripgrep)")
    return
  end
  opts.cmd_fn = function(opts, query, no_esc)

    local glob_arg, glob_str = "", ""
    local search_query = query or ""
    if query:find(opts.glob_separator) then
      search_query, glob_str = query:match("(.*)"..opts.glob_separator.."(.*)")
      for _, s in ipairs(utils.strsplit(glob_str, "%s")) do
        glob_arg = glob_arg .. (" %s %s")
          :format(opts.glob_flag, vim.fn.shellescape(s))
      end
    end

    -- copied over from get_grep_cmd
    local search_path = ''
    if opts.filespec and #opts.filespec>0 then
      search_path = opts.filespec
    elseif opts.filename and #opts.filename>0 then
      search_path = vim.fn.shellescape(opts.filename)
    end

    if not (no_esc or opts.no_esc) then
      search_query = utils.rg_escape(search_query)
    end

    -- do not escape at all
    if not (no_esc == 2 or opts.no_esc == 2) then
      search_query = vim.fn.shellescape(search_query)
    end

    local cmd = ("rg %s %s -- %s %s")
      :format(opts.rg_opts, glob_arg, search_query, search_path)
    return cmd
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
  return M.grep(opts)
end

M.grep_curbuf = function(opts)
  if not opts then opts = {} end
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
      opts.search = ''
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
