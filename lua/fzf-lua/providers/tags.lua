if not pcall(require, "fzf") then
  return
end

local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local grep_cmd = nil

local get_grep_cmd = function()
  if vim.fn.executable("rg") == 1 then
    return "rg --line-number"
  end
  return "grep -n -P"
end

local fzf_tags = function(opts)
  opts.ctags_file = opts.ctags_file or "tags"

  if not vim.loop.fs_open(vim.fn.expand(opts.ctags_file, true), "r", 438) then
    utils.info("Tags file does not exists. Create one with ctags -R")
    return
  end

  -- get these here before we open fzf
  local cwd = vim.fn.expand(opts.cwd or vim.fn.getcwd())
  local current_file = vim.api.nvim_buf_get_name(0)

  local fzf_function = function (cb)

    local getlinenumber = function(t)
      if not grep_cmd then grep_cmd = get_grep_cmd() end
      local line = 1
      local filepath = path.join({cwd, t.file})
      local pattern = utils.rg_escape(t.text:match("/(.*)/"))
      -- do not escape '$' if it's the last pattern char
      -- as ctags uses '$' at the end of short patterns
      pattern = pattern:gsub("\\%$$", "%$")
      if not pattern or not filepath then return line end
      local cmd = string.format('%s "%s" %s',
        grep_cmd, pattern,
        vim.fn.shellescape(filepath))
      local out = vim.fn.system(cmd)
      if not utils.shell_error() then
        line = out:match("[^:]+")
      end
      -- if line == 1 then print(cmd) end
      return line
    end

    local add_tag = function(t, fzf_cb, co)
      local line = getlinenumber(t)
      local tag = string.format("%s:%s: %s %s",
        core.make_entry_file(opts, t.file),
        utils.ansi_codes.green(tostring(line)),
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
                }, cb, co)
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

  opts = core.set_fzf_line_args(opts)
  opts.fzf_fn = fzf_function
  return core.fzf_files(opts)
end

M.tags = function(opts)
  opts = config.normalize_opts(opts, config.globals.tags)
  if not opts then return end
  return fzf_tags(opts)
end

M.btags = function(opts)
  opts = config.normalize_opts(opts, config.globals.btags)
  if not opts then return end
  opts.current_buffer_only = true
  return fzf_tags(opts)
end

return M
