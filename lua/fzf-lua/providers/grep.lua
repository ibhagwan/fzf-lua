local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local get_grep_cmd = make_entry.get_grep_cmd

M.grep = function(opts)
  ---@type fzf-lua.config.Grep
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

  if utils.has(opts, "fzf") and not opts.prompt and opts.search and #opts.search > 0 then
    opts.prompt = utils.ansi_from_hl(opts.hls.live_prompt, opts.search) .. " > "
  end

  -- get the grep command before saving the last search
  -- in case the search string is overwritten by 'rg_glob'
  opts.cmd = get_grep_cmd(opts, opts.search, opts.no_esc)
  if not opts.cmd then return end

  -- query was already parsed for globs inside 'get_grep_cmd'
  -- no need for our external headless instance to parse again
  opts.rg_glob = false

  -- search query in header line
  if type(opts._headers) == "table" then table.insert(opts._headers, "search") end
  opts = core.set_title_flags(opts, { "cmd" })
  opts = core.set_fzf_field_index(opts)
  return core.fzf_exec(opts.cmd, opts)
end

local function normalize_live_grep_opts(opts)
  -- disable treesitter as it collides with cmd regex highlighting
  opts = opts or {}
  opts._treesitter = false

  ---@type fzf-lua.config.Grep
  opts = config.normalize_opts(opts, "grep")
  if not opts then return end

  -- we need this for `actions.grep_lgrep`
  opts.__ACT_TO = opts.__ACT_TO or M.grep

  -- used by `actions.toggle_ignore', normalize_opts sets `__call_fn`
  -- to the calling function  which will resolve to this fn), we need
  -- to deref one level up to get to `live_grep_{mt|st}`
  opts.__call_fn = utils.__FNCREF2__()

  -- NOTE: no longer used since we hl the query with `FzfLuaLivePrompt`
  -- prepend prompt with "*" to indicate "live" query
  -- opts.prompt = type(opts.prompt) == "string" and opts.prompt or "> "
  -- if opts.live_ast_prefix ~= false then
  --   opts.prompt = opts.prompt:match("^%*") and opts.prompt or ("*" .. opts.prompt)
  -- end

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

M.live_grep = function(opts)
  opts = normalize_live_grep_opts(opts)
  if not opts then return end

  -- register opts._cmd, toggle_ignore/title_flag/--fixed-strings
  local cmd0 = get_grep_cmd(opts, core.fzf_query_placeholder, 2)

  -- if multiprocess is optional (=1) and no prpocessing is required
  -- use string contents (shell command), stringify_mt will use the
  -- command as is without the neovim headless wrapper
  local contents
  if opts.multiprocess == 1
      and not opts.fn_transform
      and not opts.fn_preprocess
      and not opts.fn_postprocess
  then
    contents = cmd0
  else
    -- since we're using function contents force multiprocess if optional
    opts.multiprocess = opts.multiprocess == 1 and true or opts.multiprocess
    contents = function(s, o)
      return FzfLua.make_entry.lgrep(s, o)
    end
  end

  -- search query in header line
  opts = core.set_title_flags(opts, { "cmd", "live" })
  opts = core.set_fzf_field_index(opts)
  core.fzf_live(contents, opts)
end

M.live_grep_native = function(opts)
  -- set opts before normalize so they're saved in `__call_opts` for resume
  -- nullifies fn_{pre|post|transform}, forces no wrap shell.stringify_mt
  opts = vim.tbl_deep_extend("force", opts or {}, {
    multiprocess = 1,
    git_icons = false,
    file_icons = false,
    file_ignore_patterns = false,
    strip_cwd_prefix = false,
    render_crlf = false,
    path_shorten = false,
    formatter = false,
    multiline = false,
    rg_glob = false,
  })

  opts = normalize_live_grep_opts(opts)
  if not opts then return end

  -- verify settings for shell command with multiprocess native fallback
  assert(opts.multiprocess == 1
    and not opts.fn_transform
    and not opts.fn_preprocess
    and not opts.fn_postprocess)

  M.live_grep(opts)
end

M.live_grep_glob = function(opts)
  vim.deprecate(
    [['live_grep_glob']],
    [[':FzfLua live_grep' or ':lua FzfLua.live_grep()' (glob parsing enabled by default)]],
    "Jan 2026", "FzfLua"
  )
  if vim.fn.executable("rg") ~= 1 then
    utils.warn("'--glob|iglob' flags requires 'rg' (https://github.com/BurntSushi/ripgrep)")
    return
  end

  -- 'rg_glob = true' enables the glob processing in
  -- 'make_entry.preprocess', only supported with multiprocess
  opts = opts or {}
  opts.rg_glob = true
  return M.live_grep(opts)
end


M.live_grep_resume = function(opts)
  vim.deprecate(
    [['live_grep_resume']],
    [[':FzfLua live_grep resume=true' or ':lua FzfLua.live_grep({resume=true})']],
    "Jan 2026", "FzfLua"
  )
  opts = opts or {}
  opts.resume = true
  return M.live_grep(opts)
end

M.grep_last = function(opts)
  vim.deprecate(
    [['grep_last']],
    [[':FzfLua grep resume=true' or ':lua FzfLua.grep({resume=true})']],
    "Jan 2026", "FzfLua"
  )
  opts = opts or {}
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
  ---@type fzf-lua.config.GrepCurbuf
  opts = config.normalize_opts(opts, "grep_curbuf", "bgrep")
  if not opts then return end

  opts.filename = vim.api.nvim_buf_get_name(utils.CTX().bufnr)
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
  ---@type fzf-lua.config.Grep
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
