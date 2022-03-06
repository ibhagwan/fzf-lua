local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local grep_cmd = nil

local get_grep_cmd = function()
  if vim.fn.executable("rg") == 1 then
    return {"rg", "--line-number"}
  end
  return {"grep", "-n", "-P"}
end

local fzf_tags = function(opts)
  opts.ctags_file = opts.ctags_file and vim.fn.expand(opts.ctags_file) or "tags"

  if not vim.loop.fs_open(opts.ctags_file, "r", 438) then
    utils.info("Tags file does not exists. Create one with ctags -R")
    return
  end

  -- get these here before we open fzf
  local cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())
  local current_file = vim.api.nvim_buf_get_name(0)

  local contents = function (cb)

    --[[ local read_line = function(file)
      local line
      local handle = io.open(file, "r")
      if handle then
        line = handle and handle:read("*line")
        handle:close()
      end
      return line
    end

    local _file2ff = {}
    local string_byte = string.byte
    local fileformat = function(file)
      local ff = _file2ff[file]
      if ff then return ff end
      local line = read_line(file)
      -- dos ends with \13
      -- mac ends with \13\13
      -- unix ends with \62
      -- char(13) == ^M
      if line and string_byte(line, #line) == 13 then
        if #line>1 and string_byte(line, #line-1) == 13 then
          ff = 'mac'
        else
          ff = 'dos'
        end
      else
        ff = 'unix'
      end
      _file2ff[file] = ff
      return ff
    end --]]

    local getlinenumber = function(t)
      if not grep_cmd then grep_cmd = get_grep_cmd() end
      local line = 1
      local filepath = path.join({cwd, t.file})
      local pattern = utils.rg_escape(t.text:match("/^?(.*)/"))
      if not pattern or not filepath then return line end
      -- ctags uses '$' at the end of short patterns
      -- 'rg|grep' does not match these properly when
      -- 'fileformat' isn't set to 'unix', when set to
      -- 'dos' we need to prepend '$' with '\r$' with 'rg'
      -- it is simpler to just ignore it compleley.
      --[[ local ff = fileformat(filepath)
      if ff == 'dos' then
        pattern = pattern:gsub("\\%$$", "\\r%$")
      else
        pattern = pattern:gsub("\\%$$", "%$")
      end --]]
      -- equivalent pattern to `rg --crlf`
      -- see discussion in #219
      pattern = pattern:gsub("\\%$$", "\\r??%$")
      local cmd = utils.tbl_deep_clone(grep_cmd)
      table.insert(cmd, pattern)
      table.insert(cmd, filepath)
      local out = utils.io_system(cmd)
      if not utils.shell_error() then
        line = out:match("[^:]+")
      end
      -- if line == 1 then print(cmd) end
      return line
    end

    local add_tag = function(t, fzf_cb, co, no_line)
      local line = not no_line and getlinenumber(t)
      local tag = string.format("%s%s: %s %s",
        core.make_entry_file(opts, t.file),
        not line and "" or ":"..utils.ansi_codes.green(tostring(line)),
        utils.ansi_codes.magenta(t.name),
        utils.ansi_codes.green(t.text))
      fzf_cb(tag, function()
        coroutine.resume(co)
      end)
    end

    coroutine.wrap(function ()
      local co = coroutine.running()
      local lines = vim.split(utils.read_file(opts.ctags_file), '\n', true)
      for _, line in ipairs(lines) do
        if not line:match'^!_TAG_' then
          local name, file, text = line:match("^(.*)\t(.*)\t(/.*/)")
          if name and file and text then
            if not opts.current_buffer_only or
              current_file == path.join({cwd, file}) then
              -- without vim.schedule `add_tag` would crash
              -- at any `vim.fn...` call
              vim.schedule(function()
                add_tag({
                    name = name,
                    file = file,
                    text = text,
                  }, cb, co,
                  -- unless we're using native previewer
                  -- do not need to extract the line number
                  not opts.previewer
                  or opts.previewer == 'builtin'
                  or type(opts.previewer) == 'table')
              end)
              -- pause here until we call coroutine.resume()
              coroutine.yield()
            end
          end
        end
      end
      -- done, we can't call utils.delayed_cb here
      -- because sleep() messes up the coroutine
      -- cb(nil, function() coroutine.resume(co) end)
      utils.delayed_cb(cb, function() coroutine.resume(co) end)
      coroutine.yield()
    end)()
  end

  -- signal actions this is a ctag
  opts._ctag = true
  opts = core.set_header(opts, 2)
  opts = core.set_fzf_field_index(opts)
  return core.fzf_files(opts, contents)
end

M.tags_old = function(opts)
  opts = config.normalize_opts(opts, config.globals.tags)
  if not opts then return end
  return fzf_tags(opts)
end

M.btags_old = function(opts)
  opts = config.normalize_opts(opts, config.globals.btags)
  if not opts then return end
  opts.fzf_opts = vim.tbl_extend("keep",
    opts.fzf_opts or {}, config.globals.blines.fzf_opts)
  opts.current_buffer_only = true
  return fzf_tags(opts)
end

local function get_tags_cmd(opts)
  local query = nil
  local cmd = "grep"
  if vim.fn.executable("rg") == 1 then
    cmd = "rg"
  end
  if opts.search and #opts.search>0 then
    if not opts.no_esc then
      opts.search = utils.rg_escape(opts.search)
    end
    query = vim.fn.shellescape(opts.search)
  elseif opts._curr_file and #opts._curr_file>0 then
    query = vim.fn.shellescape(opts._curr_file)
  else
    query = "-v '^!_TAG_'"
  end
  return ("%s %s %s"):format(cmd, query,
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

  -- prevents 'file|git_icons=false' from overriding processing
  opts.requires_processing = true
  opts._fn_transform = make_entry.tag                            -- multiprocess=false
  opts._fn_transform_str = [[return require("make_entry").tag]]  -- multiprocess=true

  if opts.lgrep then
    -- live_grep requested by caller ('tags_live_grep')
    opts.prompt = '*' .. opts.prompt
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
