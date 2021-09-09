if not pcall(require, "fzf") then
  return
end

local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"


local M = {}

local fzf_function = function (cb)
  local opts = {}
  opts.lang = config.globals.helptags.lang or vim.o.helplang
  opts.fallback = utils._if(config.globals.helptags.fallback ~= nil, config.globals.helptags.fallback, true)

  local langs = vim.split(opts.lang, ',', true)
  if opts.fallback and not vim.tbl_contains(langs, 'en') then
    table.insert(langs, 'en')
  end
  local langs_map = {}
  for _, lang in ipairs(langs) do
    langs_map[lang] = true
  end

  local tag_files = {}
  local function add_tag_file(lang, file)
    if langs_map[lang] then
      if tag_files[lang] then
        table.insert(tag_files[lang], file)
      else
        tag_files[lang] = {file}
      end
    end
  end

  local help_files = {}
  local all_files = vim.fn.globpath(vim.o.runtimepath, 'doc/*', 1, 1)
  for _, fullpath in ipairs(all_files) do
    local file = path.tail(fullpath)
    if file == 'tags' then
      add_tag_file('en', fullpath)
    elseif file:match('^tags%-..$') then
      local lang = file:sub(-2)
      add_tag_file(lang, fullpath)
    else
      help_files[file] = fullpath
    end
  end

  local add_tag = function(t, fzf_cb, co)
    --[[ local tag = string.format("%-58s\t%s",
      utils.ansi_codes.blue(t.name),
      utils._if(t.name and #t.name>0, path.basename(t.name), '')) ]]
    local tag = utils.ansi_codes.magenta(t.name)
    fzf_cb(tag, function()
      coroutine.resume(co)
    end)
  end

  coroutine.wrap(function ()
    local co = coroutine.running()
    local tags_map = {}
    local delimiter = string.char(9)
    for _, lang in ipairs(langs) do
      for _, file in ipairs(tag_files[lang] or {}) do
        local lines = vim.split(utils.read_file(file), '\n', true)
        for _, line in ipairs(lines) do
          -- TODO: also ignore tagComment starting with ';'
          if not line:match'^!_TAG_' then
            local fields = vim.split(line, delimiter, true)
            if #fields == 3 and not tags_map[fields[1]] then
              add_tag({
                name = fields[1],
                filename = help_files[fields[2]],
                cmd = fields[3],
                lang = lang,
              }, cb, co)
              tags_map[fields[1]] = true
              -- pause here until we call coroutine.resume()
              coroutine.yield()
            end
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


M.helptags = function(opts)

  opts = config.normalize_opts(opts, config.globals.helptags)
  if not opts then return end

  coroutine.wrap(function ()

    -- local prev_act = action(function (args) end)

    opts.nomulti = true
    opts.preview_window = 'hidden:right:0'
    opts._fzf_cli_args = "--nth 1"

    local selected = core.fzf(opts, fzf_function)

    if not selected then return end

    actions.act(opts.actions, selected)

  end)()

end

return M
