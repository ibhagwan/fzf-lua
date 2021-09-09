if not pcall(require, "fzf") then
  return
end

local fzf_helpers = require("fzf.helpers")
local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local last_search = {}

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

  -- do not escape at all
  if not (no_esc == 2 or opts.no_esc == 2) then
    search_query = vim.fn.shellescape(search_query)
  end

  return string.format('%s %s %s', command, search_query, search_path)
end

local function set_search_header(opts, type)
  if not opts then opts = {} end
  if opts.no_header then return opts end
  if not opts.cwd_header then opts.cwd_header = "cwd:" end
  if not opts.search_header then opts.search_header = "Searching for:" end
  local header_str
  local cwd_str = opts.cwd and ("%s %s"):format(opts.cwd_header, opts.cwd)
  local search_str = opts.search and #opts.search > 0 and
    ("%s %s"):format(opts.search_header, opts.search)
  -- 1: only search
  -- 2: only cwd
  -- otherwise, all
  if type == 1 then header_str = search_str or ''
  elseif type == 2 then header_str = cwd_str or ''
  else
    header_str = search_str or ''
    if #header_str>0 and cwd_str and #cwd_str>0 then
      header_str = header_str .. ", "
    end
    header_str = header_str .. (cwd_str or '')
  end
  if not header_str or #header_str==0 then return opts end
  opts._fzf_header_args = opts._fzf_header_args or ''
  opts._fzf_header_args = string.format([[%s --header=%s ]],
    opts._fzf_header_args,
    vim.fn.shellescape(header_str))
  return opts
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
  opts = set_search_header(opts)

  -- save the search query so the use can
  -- call the same search again
  last_search = {}
  last_search.no_esc = no_esc or opts.no_esc
  last_search.query = opts.search

  local command = get_grep_cmd(opts, opts.search, no_esc)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    {cmd = command, cwd = opts.cwd},
    function(x)
      return core.make_entry_file(opts, x)
    end)

  --[[ opts.cb_selected = function(_, x)
    return x
  end ]]

  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts)
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

  opts._live_query = opts.search or ''
  if opts.search and #opts.search>0 then
    -- save the search query so the use can
    -- call the same search again
    last_search = {}
    last_search.no_esc = true
    last_search.query = opts.search
    -- escape unless the user requested not to
    if not (no_esc or opts.no_esc) then
      opts._live_query = utils.rg_escape(opts.search)
    end
  end

  -- search query in header line
  opts = set_search_header(opts, 2)

  opts._cb_live_cmd = function(query)
    if query and #query>0 and not opts.do_not_save_last_search then
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

  core.fzf_files_interactive(opts)
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
  opts = set_search_header(opts, 2)

  -- fzf already adds single quotes around the placeholder when expanding
  -- for skim we surround it with double quotes or single quote searches fail
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')
  local initial_command = get_grep_cmd(opts , placeholder, 2)
  local reload_command = initial_command
  if not opts.exec_empty_query then
    reload_command =  ('[ -z %s ] || %s'):format(placeholder, reload_command)
  end
  if opts._is_skim then
    -- skim interactive mode does not need a piped command
    opts.fzf_fn = nil
    opts._fzf_cli_args = string.format(
        "--prompt='*%s' --cmd-prompt='%s' --cmd-query=%s -i -c %s",
        opts.prompt, opts.prompt,
        -- since we surrounded the skim placeholder with quotes
        -- we need to escape them in the initial query
        vim.fn.shellescape(utils.sk_escape(query)),
          vim.fn.shellescape(
            ("(cd %s && %s)"):format(
              vim.fn.shellescape(opts.cwd or '.'),
              reload_command)))
  else
    opts.fzf_fn = {}
    if opts.exec_empty_query or (opts.search and #opts.search > 0) then
      opts.fzf_fn = fzf_helpers.cmd_line_transformer(
        {cmd = initial_command:gsub(placeholder, vim.fn.shellescape(query)),
         cwd = opts.cwd},
        function(x)
          return core.make_entry_file(opts, x)
        end)
    end
    opts._fzf_cli_args = string.format('--phony --query=%s --bind=%s',
        vim.fn.shellescape(query),
        vim.fn.shellescape(("change:reload:%s"):format(
          ("(cd %s && %s || true)"):format(
            vim.fn.shellescape(opts.cwd or '.'),
            reload_command))))
  end

  -- we cannot parse any entries as they're not getting called
  -- past the initial command, until I can find a solution for
  -- that icons must be disabled
  opts.git_icons = false
  opts.file_icons = false

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

M.grep_curbuf = function(opts)
  if not opts then opts = {} end
  opts.rg_opts = config.globals.grep.rg_opts .. " --with-filename"
  opts.grep_opts = config.globals.grep.grep_opts .. " --with-filename"
  if opts.exec_empty_query == nil then
    opts.exec_empty_query = true
  end
  opts.filename = vim.api.nvim_buf_get_name(0)
  if #opts.filename > 0 then
    opts.filename = path.relative(opts.filename, vim.loop.cwd())
    return M.live_grep(opts)
  else
    utils.info("Rg current buffer requires actual file on disk")
    return
  end
end

return M
