local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"

local M = {}

M.metatable = function(opts)
  opts = config.normalize_opts(opts, config.globals.builtin)
  if not opts then return end

  if not opts.metatable then opts.metatable = getmetatable("").__index end

  local prev_act = shell.action(function(args)
    -- TODO: retreive method help
    local help = ""
    return string.format("%s:%s", args[1], help)
  end, nil, opts.debug)

  local methods = {}
  for k, _ in pairs(opts.metatable) do
    if not opts.metatable_exclude or opts.metatable_exclude[k] == nil then
      table.insert(methods, k)
    end
  end

  table.sort(methods, function(a, b) return a < b end)

  opts.fzf_opts["--preview"] = prev_act
  opts.fzf_opts["--preview-window"] = "hidden:down:10"
  opts.fzf_opts["--no-multi"] = ""

  -- builtin is excluded from global resume
  -- as the behavior might confuse users (#267)
  opts.global_resume = false

  core.fzf_exec(methods, opts)
end

local function ls(dir, fn)
  local handle = vim.loop.fs_scandir(dir)
  while handle do
    local name, t = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    local fname = path.join({ dir, name })

    -- HACK: type is not always returned due to a bug in luv,
    -- so fecth it with fs_stat instead when needed.
    -- see https://github.com/folke/lazy.nvim/issues/306
    fn(fname, name, t or vim.loop.fs_stat(fname).type)
  end
end

M.profiles = function(opts)
  opts = config.normalize_opts(opts, config.globals.profiles)
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
            local res = utils.load_profile(fname, profile, true)
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
