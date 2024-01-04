local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"


local M = {}

local fzf_fn = function(cb)
  local opts = {}
  opts.lang = config.globals.helptags.lang or vim.o.helplang
  opts.fallback = utils._if(config.globals.helptags.fallback ~= nil,
    config.globals.helptags.fallback, true)

  local langs = vim.split(opts.lang, ",")
  if opts.fallback and not vim.tbl_contains(langs, "en") then
    table.insert(langs, "en")
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
        tag_files[lang] = { file }
      end
    end
  end

  local help_files = {}
  local all_files = vim.fn.globpath(vim.o.runtimepath, "doc/*", 1, 1)
  for _, fullpath in ipairs(all_files) do
    local file = path.tail(fullpath)
    if file == "tags" then
      add_tag_file("en", fullpath)
    elseif file:match("^tags%-..$") then
      local lang = file:sub(-2)
      add_tag_file(lang, fullpath)
    else
      help_files[file] = fullpath
    end
  end

  local hl = (function()
    local a, b, fn = utils.ansi_from_hl("Label", "foo")
    return function(s) return fn(s) end
  end)()

  local add_tag = function(t, fzf_cb, co)
    local tag = string.format("%-80s %s %s", hl(t.tag), t.filename, t.filepath)
    fzf_cb(tag, function()
      coroutine.resume(co)
    end)
  end

  coroutine.wrap(function()
    local co = coroutine.running()
    local tags_map = {}
    local delimiter = string.char(9)
    for _, lang in ipairs(langs) do
      for _, file in ipairs(tag_files[lang] or {}) do
        local lines = vim.split(utils.read_file(file), "\n")
        for _, line in ipairs(lines) do
          -- TODO: also ignore tagComment starting with ';'
          if not line:match "^!_TAG_" then
            local fields = vim.split(line, delimiter)
            if #fields == 3 and not tags_map[fields[1]] then
              add_tag({
                tag = fields[1],
                filename = fields[2],
                filepath = help_files[fields[2]],
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
    cb(nil)
  end)()
end


M.helptags = function(opts)
  opts = config.normalize_opts(opts, "helptags")
  if not opts then return end
  core.fzf_exec(fzf_fn, opts)
end

return M
