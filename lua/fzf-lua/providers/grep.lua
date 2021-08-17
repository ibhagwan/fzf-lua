if not pcall(require, "fzf") then
  return
end

local fzf_helpers = require("fzf.helpers")
local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

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
  elseif opts.cwd and #opts.cwd>0 then
    search_path = vim.fn.shellescape(opts.cwd)
  end

  if search_query == nil then search_query = ''
  elseif not no_esc then
    search_query = '"' .. utils.rg_escape(search_query) .. '"'
  end

  return string.format('%s %s %s', command, search_query, search_path)
end

local function set_search_header(opts)
  if not opts then opts = {} end
  if opts.no_header then return opts end
  if not opts.search or #opts.search==0 then return opts end
  if not opts.search_header then opts.search_header = "Searching for:" end
  opts.fzf_cli_args = opts.fzf_cli_args or ''
  opts.fzf_cli_args = string.format([[%s --header="%s %s"]],
    opts.fzf_cli_args, opts.search_header, opts.search:gsub('"', '\\"'))
  return opts
end

M.grep = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)

  if opts.continue_last_search or opts.repeat_last_search then
    opts.search = config._grep_last_search
  end

  -- if user did not provide a search term
  -- provide an input prompt
  if not opts.search or #opts.search == 0 then
    opts.search = vim.fn.input(opts.input_prompt)
  end

  if not opts.search or #opts.search == 0 then
    utils.info("Please provide a valid search string")
    return
  end

  -- search query in header line
  opts = set_search_header(opts)

  -- save the search query so the use can
  -- call the same search again
  config._grep_last_search = opts.search

  local command = get_grep_cmd(opts, opts.search)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    command,
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


M.live_grep_sk = function(opts)

  -- "'{}'" opens sk with an empty search_query showing all files
  --  "{}"  opens sk without executing an empty string query
  --  the problem is the latter doesn't support escaped chars
  -- TODO: how to open without a query with special char support
  local sk_args = get_grep_cmd(opts , "'{}'", true)

  opts._fzf_cli_args = string.format("--cmd-prompt='%s' -i -c %s",
      opts.prompt,
      vim.fn.shellescape(sk_args))

  opts.git_icons = false
  opts.file_icons = false
  opts.fzf_fn = nil --function(_) end
  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts)
  opts.search = nil
end

M.live_grep = function(opts)

  opts = config.normalize_opts(opts, config.globals.grep)

  if opts.continue_last_search or opts.repeat_last_search then
    opts.search = config._grep_last_search
  end

  if opts.search and #opts.search>0 then
    -- save the search query so the use can
    -- call the same search again
    config._grep_last_search = opts.search
  end

  -- HACK: support skim (rust version of fzf)
  opts.fzf_bin = opts.fzf_bin or config.globals.fzf_bin
  if opts.fzf_bin and opts.fzf_bin:find('sk')~=nil then
    return M.live_grep_sk(opts)
  end

  -- use {q} as a placeholder for fzf
  local initial_command = get_grep_cmd(opts, opts.search)
  local reload_command = get_grep_cmd(opts, "{q}", true) .. " || true"

  opts._fzf_cli_args = string.format('--phony --query="%s" --bind=%s',
      utils._if(opts.search and #opts.search>0,
        utils.rg_escape(opts.search), ''),
      vim.fn.shellescape(string.format("change:reload:%s", reload_command)))

  -- TODO:
  -- this is not getting called past the initial command
  -- until we fix that we cannot use icons as they interfere
  -- with the extension parsing
  opts.git_icons = false
  opts.file_icons = false

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    initial_command,
    function(x)
      return core.make_entry_file(opts, x)
    end)

  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts)
  opts.search = nil
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
