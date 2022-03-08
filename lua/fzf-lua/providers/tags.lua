local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local function get_tags_cmd(opts, flags)
  local query = nil
  local cmd = "grep"
  if vim.fn.executable("rg") == 1 then
    cmd = "rg"
  end
  if opts.search and #opts.search>0 then
    query = libuv.shellescape(opts.no_esc and opts.search or
      utils.rg_escape(opts.search))
  elseif opts._curr_file and #opts._curr_file>0 then
    query = vim.fn.shellescape(opts._curr_file)
  else
    query = "-v '^!_TAG_'"
  end
  return ("%s %s %s %s"):format(cmd, flags or '', query,
    vim.fn.shellescape(opts._ctags_file))
end

local function tags(opts)

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
    local cmd = get_tags_cmd({ _ctags_file = opts._ctags_file }, "-m 1")
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
    opts.prompt = opts.prompt:match("^*") and opts.prompt or '*' .. opts.prompt
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
  end

  opts._curr_file = opts._curr_file and
    path.relative(opts._curr_file, opts.cwd or vim.loop.cwd())
  opts.cmd = opts.cmd or get_tags_cmd(opts)
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_header(opts)
  opts = core.set_fzf_field_index(opts)
  return core.fzf_files(opts, contents)
end

M.tags = function(opts)
  opts = config.normalize_opts(opts, config.globals.tags)
  if not opts then return end
  return tags(opts)
end

M.btags = function(opts)
  opts = config.normalize_opts(opts, config.globals.btags)
  if not opts then return end
  opts._curr_file = vim.api.nvim_buf_get_name(0)
  if not opts._curr_file or #opts._curr_file==0 then
    utils.info("'btags' is not available for unnamed buffers.")
    return
  end
  return tags(opts)
end

M.grep = function(opts)
  opts = opts or {}

  if not opts.search then
    opts.search = vim.fn.input(opts.input_prompt or 'Grep For> ')
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
