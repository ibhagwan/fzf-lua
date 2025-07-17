local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
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

  return core.fzf_exec(methods, opts)
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

  if opts.load then
    -- silent = [2]
    require("fzf-lua").setup({ opts.load, false })
    return
  end

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

M.combine = function(t)
  t = t or {}
  t.pickers = type(t.pickers) == "table" and type(t.pickers)
      or type(t.pickers) == "string" and utils.strsplit(t.pickers, "[,;]")
      or nil

  -- First picker options set the tone
  local opts1 = (function()
    if t.pickers and t.pickers[1] then
      local ok, opts = pcall(config.normalize_opts, t, t.pickers[1])
      return ok and opts
    end
  end)()
  if not opts1 then
    utils.warn("Must specify at least one valid picker")
    return
  end

  -- Let fzf_wrap know to NOT start the coroutine
  opts1._start = false

  local cmds, opts = (function()
    local ret, opts = {}, nil
    for _, p in ipairs(t.pickers --[[@as table]]) do
      -- local ok, msg, cmd, o = pcall(FzfLua[p], opts1)
      -- if not ok or not cmd then
      local _, cmd, o = FzfLua[p](opts1)
      if not cmd or not o then
        -- utils.warn(string.format("Error loading picker '%s', ignoring.\nError: %s", p, msg))
        utils.warn(string.format("Error loading picker '%s', ignoring.", p))
      else
        table.insert(ret, cmd)
        -- NOTE: we use the [first picker] modified opts after picker setup
        -- as pickers can modify opts / add important parts
        if not opts then opts = o end
      end
    end
    return ret, opts
  end)()
  if not opts then return end

  -- Let fzf_wrap know to START the coroutine
  opts._start = nil

  -- _G.dump(cmds)
  local contents = table.concat(cmds, utils.__IS_WINDOWS and "&" or ";")

  return core.fzf_wrap(contents, opts)
end

M.global = function(opts)
  opts = config.normalize_opts(opts, "global")
  if not opts then return end

  if opts.line_query and not utils.has(opts, "fzf", { 0, 59 }) then
    utils.warn("'global' requires fzf >= 0.59, reverting to files.")
    return FzfLua.files(opts)
  end

  -- Tells fzf_wrap to not start the fzf process
  opts._start = false
  local pickers = {}
  local opts_copy = vim.deepcopy(opts)
  for _, t in ipairs(opts.pickers) do
    local name = t[1]
    if FzfLua[name] then
      if not t.prefix then
        -- Default picker opts set the tone for this picker options
        -- this way convert reload / exec_silent actions will use a consistent
        -- opts ref in the callbacks so we can later modify internal values
        pickers[name] = { FzfLua[name](opts) }
        -- Override opts with the return opts and store a copy of `pickers[]`
        -- as we patch the opts when switching a picker in the change event
        opts = pickers[name][3]
        opts._start = nil -- remove the start suppression
        pickers[name][3] = vim.deepcopy(opts)
      else
        -- Each subsequent picker gets a fresh copy of the original opts
        -- (unmodified by the default picker)
        pickers[name] = { FzfLua[name](opts_copy) }
      end
    else
      utils.warn(string.format("invalid picker '%s', ignoring.", name))
    end
  end

  -- Test for default/starting picker
  local default_picker = opts.pickers[1] and pickers[opts.pickers[1][1]]
  if not default_picker or default_picker.prefix then
    utils.err("default picker not defined or has a prefix, aborting.")
    return
  end

  ---@param q string?
  ---@return table?, integer?
  local get_picker = function(q)
    if type(q) == "string" and #q > 0 then
      for _, t in ipairs(opts.pickers) do
        local name = t[1]
        if t.prefix and #t.prefix > 0 and q:match("^" .. utils.lua_regex_escape(t.prefix)) then
          return pickers[name], #t.prefix + 1
        end
      end
    end
    return default_picker, 1
  end


  local cur_picker, cur_sub

  local transform_picker = function(start)
    return FzfLua.shell.stringify_data(function(args, _, _)
      local q = args[1]
      local new_picker, new_sub = get_picker(q)
      assert(new_picker)
      local reload = ""
      if start or new_picker and new_picker ~= cur_picker then
        -- New picker requested, reload the contents and transform
        -- the search string to exclude the picker prefix
        cur_sub = new_sub
        cur_picker = new_picker
        -- Patch the opts refs with important values for path parsing
        -- e.g. formatter, path_shorten, etc
        -- TODO: is there a better way to override the callback opts ref?
        opts.__alt_opts = new_picker[3]
        reload = string.format("reload(%s)+", new_picker[2])
      end
      return reload .. string.format("search(%s)", q:sub(cur_sub))
    end, opts, "{q}")
  end

  table.insert(opts._fzf_cli_args, "--bind="
    .. libuv.shellescape("start:+transform:" .. transform_picker(true)))

  table.insert(opts._fzf_cli_args, "--bind="
    .. libuv.shellescape("change:+transform:" .. transform_picker(false)))

  if opts.header ~= false then
    local header = {}
    for _, t in pairs(opts.pickers) do
      table.insert(header, string.format("<%s> %s",
        utils.ansi_from_hl(opts.hls.header_bind, t.prefix or "default"),
        utils.ansi_from_hl(opts.hls.header_text, t.desc or t[1])))
    end

    opts.header = table.concat(header, "|")
  end

  return core.fzf_wrap(utils.shell_nop(), opts)
end

return M
