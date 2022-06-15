local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

function M.get_last_search(_)
  local last_search = config.globals.tags._last_search or {}
  return last_search.query, last_search.no_esc
end

function M.set_last_search(_, query, no_esc)
  config.globals.tags._last_search = {
    query = query,
    no_esc = no_esc
  }
  if config.__resume_data then
    config.__resume_data.last_query = query
  end
end

local function get_tags_cmd(opts)
  local query, filter = nil, nil
  local bin, flags = nil, nil
  if vim.fn.executable("rg") == 1 then
    bin, flags = "rg", opts.rg_opts
  else
    bin, flags = "grep", opts.grep_opts
  end
  -- filename (i.e. btags) takes precedence over
  -- search query as we can't search for both
  if opts.filename and #opts.filename>0 then
    query = libuv.shellescape(opts.filename)
  elseif opts.search and #opts.search>0 then
    filter = ('%s -v "^!"'):format(bin)
    query = libuv.shellescape(opts.no_esc and opts.search or
      utils.rg_escape(opts.search))
  else
    query = '-v "^!_TAG_"'
  end
  return ("%s %s %s %s"):format(
      bin, flags, query,
      opts._ctags_file and vim.fn.shellescape(opts._ctags_file) or ''
    ), filter
end

local function tags(opts)

  -- we need this for 'actions.grep_lgrep'
  opts.__MODULE__ = opts.__MODULE__ or M
  opts.__module__ = opts.__module__ or 'tags'

  -- signal actions this is a ctag
  opts._ctag = true
  opts.ctags_file = opts.ctags_file and vim.fn.expand(opts.ctags_file) or "tags"
  opts._ctags_file = opts.ctags_file
  if not path.starts_with_separator(opts._ctags_file) and opts.cwd then
    opts._ctags_file = path.join({opts.cwd, opts.ctags_file})
  end

  if not vim.loop.fs_stat(opts._ctags_file) then
    utils.info(("Tags file ('%s') does not exists. Create one with ctags -R")
      :format(opts._ctags_file))
    return
  end

  if opts.line_field_index == nil then
    -- if caller did not specify the line field index
    -- grep the first tag with '-m 1' and test for line presence
    local cmd = get_tags_cmd({
      rg_opts = "-m 1",
      grep_opts = "-m 1",
      _ctags_file = opts._ctags_file
    })
    local ok, lines, err = pcall(utils.io_systemlist, cmd)
    if ok and err == 0 and lines and not vim.tbl_isempty(lines) then
      local tag, line = make_entry.tag(opts, lines[1])
      if tag and not line then
        -- tags file does not contain lines
        -- remove preview offset field index
        opts.line_field_index = 0
      end
    end
  end

  -- prevents 'file|git_icons=false' from overriding processing
  opts.requires_processing = true
  opts._fn_transform = make_entry.tag                            -- multiprocess=false
  opts._fn_transform_str = [[return require("make_entry").tag]]  -- multiprocess=true

  if opts.lgrep then
    -- live_grep requested by caller ('tags_live_grep')
    local _, filter = get_tags_cmd({ search = 'dummy' })
    opts.filter = (opts.filter == nil) and filter or opts.filter
    -- rg globs are meaningless here since we searching
    -- a single file
    opts.rg_glob = false
    opts.filename = opts._ctags_file
    if opts.multiprocess then
      return require'fzf-lua.providers.grep'.live_grep_mt(opts)
    else
      -- 'live_grep_st' uses different signature '_fn_transform'
      opts._fn_transform = function(x)
        return make_entry.tag(opts, x)
      end
      return require'fzf-lua.providers.grep'.live_grep_st(opts)
    end
  else
    -- generate the command and pipe filter if needed
    -- since we cannot use include and exclude in the
    -- same grep command we need to use a pipe to filter
    local cmd, filter = get_tags_cmd(opts)
    opts.raw_cmd = opts.cmd or cmd
    opts.filter = (opts.filter == nil) and filter or opts.filter
    if opts.filter and #opts.filter>0 then
      opts.raw_cmd = ("%s | %s"):format(opts.raw_cmd, opts.filter)
    end
    return require'fzf-lua.providers.grep'.grep(opts)
  end
end

M.tags = function(opts)
  opts = config.normalize_opts(opts, config.globals.tags)
  if not opts then return end
  return tags(opts)
end

M.btags = function(opts)
  opts = config.normalize_opts(opts, config.globals.btags)
  if not opts then return end
  opts.filename = vim.api.nvim_buf_get_name(0)
  if not opts.filename or #opts.filename==0 then
    utils.info("'btags' is not available for unnamed buffers.")
    return
  end
  -- tags use relative paths
  opts.filename = path.relative(opts.filename, opts.cwd or vim.loop.cwd())
  return tags(opts)
end

M.grep = function(opts)
  opts = opts or {}

  if not opts.search and opts.resume then
    opts.search, opts.no_esc = M.get_last_search(opts)
    opts.search = opts.search or opts.resume_search_default
  end

  if not opts.search then
    opts.search = utils.input(opts.input_prompt or 'Grep For> ')
  end

  return M.tags(opts)
end

M.live_grep = function(opts)
  opts = config.normalize_opts(opts, config.globals.tags)
  if not opts then return end
  opts.lgrep = true
  opts.__FNCREF__ = utils.__FNCREF__()
  return tags(opts)
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

return M
