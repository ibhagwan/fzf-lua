local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

M.metatable = function(opts)
  if not opts then return end

  if not opts.metatable then opts.metatable = getmetatable("").__index end

  local methods = {}
  for k, _ in pairs(opts.metatable) do
    if not opts.metatable_exclude or opts.metatable_exclude[k] == nil then
      table.insert(methods, k)
    end
  end

  table.sort(methods, function(a, b) return a < b end)

  opts.preview = function(args)
    local options_md = require("fzf-lua.cmd").options_md()
    return type(options_md) == "table" and options_md[args[1]:lower()] or ""
  end

  opts.fzf_opts["--preview-window"] = "hidden:down:10"

  -- builtin is excluded from global resume
  -- as the behavior might confuse users (#267)
  opts.no_resume = true

  core.fzf_exec(methods, opts)
end

---@param dir string
---@param fn fun(fname: string, name: string, type: string)
local function ls(dir, fn)
  local handle = uv.fs_scandir(dir)
  while handle do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local fname = path.join({ dir, name })

    -- HACK: type is not always returned due to a bug in luv,
    -- so fecth it with fs_stat instead when needed.
    -- see https://github.com/folke/lazy.nvim/issues/306
    fn(fname, name, t or uv.fs_stat(fname).type)
  end
end

M.profiles = function(opts)
  opts = config.normalize_opts(opts, "profiles")
  if not opts then return end

  local dirs = {
    path.join({ vim.g.fzf_lua_directory, "profiles" })
  }

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()

      for _, d in ipairs(dirs) do
        ls(d, function(fname, name, type)
          local ext = path.extension(fname)
          if type == "file" and ext == "lua" then
            local profile = name:sub(1, #name - 4)
            local res = utils.load_profile_fname(fname, profile, true)
            if res then
              local entry = string.format("%s:%-30s%s", fname,
                utils.ansi_codes.yellow(profile), res.desc or "")
              cb(entry, function(err)
                coroutine.resume(co)
                if err then cb(nil) end
              end)
              coroutine.yield()
            end
          end
        end)
      end
      -- done
      cb(nil)
    end)()
  end

  return core.fzf_exec(contents, opts)
end

return M
