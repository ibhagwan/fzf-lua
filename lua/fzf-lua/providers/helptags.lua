local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

M.helptags = function(opts)
  ---@type fzf-lua.config.Helptags
  opts = config.normalize_opts(opts, "helptags")
  if not opts then return end

  local contents = function(cb)
    opts.fallback = opts.fallback ~= false and true

    local langs = vim.split(vim.o.helplang, ",")
    if opts.fallback and not utils.tbl_contains(langs, "en") then
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
    local rtp = vim.o.runtimepath
    -- If using lazy.nvim, get all the lazy loaded plugin paths (#1296)
    local lazy = package.loaded["lazy.core.util"]
    if lazy and lazy.get_unloaded_rtp then
      local paths = lazy.get_unloaded_rtp("")
      rtp = rtp .. "," .. table.concat(paths, ",")
    end
    local all_files = vim.fn.globpath(rtp, "doc/*", true, true)
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
      local _, _, fn = utils.ansi_from_hl("Label", "foo")
      assert(fn)
      return function(s) return fn(s) end
    end)()

    local add_tag = function(t, fzf_cb, co)
      local w = 80 + string.len(t.tag) - vim.fn.strwidth(t.tag)
      local tag = string.format("%-" .. w .. "s %s%s%s", hl(t.tag), t.filename, utils.nbsp,
        t.filepath)
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

  return core.fzf_exec(contents, opts)
end

return M
