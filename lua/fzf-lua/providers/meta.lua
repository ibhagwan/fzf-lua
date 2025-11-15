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
  ---@type fzf-lua.config.Profiles
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

  local pickers = type(t.pickers) == "table" and t.pickers
      or type(t.pickers) == "string" and utils.strsplit(t.pickers, "[,;]")
      or nil

  local opts = t
  t.pickers = nil

  -- Tells fzf_wrap to not start the fzf process
  opts._start = false

  local cmds = {}
  local opts_copy = vim.deepcopy(opts)
  for i, name in ipairs(pickers) do
    if FzfLua[name] then
      local def
      local function gen_def(n, o)
        local wrapped = { FzfLua[n](o) }
        return {
          name = n,
          opts = wrapped[3],
          contents = wrapped[2],
        }
      end
      -- Default picker opts set the tone for this picker options
      -- this way convert reload / exec_silent actions will use a consistent
      -- opts ref in the callbacks so we can later modify internal values
      def = gen_def(name, i == 1 and opts or opts_copy)
      if i == 1 then
        -- Override opts with the modified return opts and remove start suppression
        opts = def.opts
        opts._start = nil
      end
      -- Instantiate the previewer, nil check as opts isn't guaranteed if the
      -- picker isn't avilable, e.g. `tags` when no tags file exists
      if def.opts and def.opts.previewer then
        def.previewer = require("fzf-lua.previewer").new(def.opts.previewer, def.opts)
      end
      -- Add content (shell command) to cmd array
      table.insert(cmds, def.contents)
    else
      utils.warn("invalid picker '%s', ignoring.", name)
    end
  end

  -- _G.dump(cmds)
  local contents = table.concat(cmds, utils.__IS_WINDOWS and "&" or ";")

  return core.fzf_wrap(contents, opts)
end

M.global = function(opts)
  ---@type fzf-lua.config.Global
  opts = config.normalize_opts(opts, "global")
  if not opts then return end

  if opts.line_query and not utils.has(opts, "fzf", { 0, 59 }) then
    utils.warn("'global' requires fzf >= 0.59, reverting to files.")
    return FzfLua.files(opts)
  end

  if type(opts.pickers) == "function" then
    opts.pickers = opts.pickers()
  end

  opts._start = false    -- Tells fzf_wrap to not start the fzf process
  opts._normalized = nil -- We need to "normalize" again with the picker opts
  local pickers = {}
  local opts_copy = vim.deepcopy(opts)
  for _, t in ipairs(opts.pickers) do
    local name = t[1]
    if FzfLua[name] then
      local def
      local function gen_def(n, o)
        local wrapped = { FzfLua[n](o) }
        return {
          name = n,
          opts = wrapped[3],
          contents = wrapped[2],
        }
      end
      if not t.prefix then
        -- Default picker opts set the tone for this picker options
        -- this way convert reload / exec_silent actions will use a consistent
        -- opts ref in the callbacks so we can later modify internal values
        def = gen_def(name, opts)
        pickers[name] = def
        -- Override opts with the return opts and store a copy of `pickers[]`
        -- as we patch the opts when switching a picker in the change event
        opts = def.opts
        opts._start = nil -- remove the start suppression
        def.opts = vim.deepcopy(opts)
      else
        -- Each subsequent picker gets a fresh copy of the original opts
        -- (unmodified by the default picker)
        def = gen_def(name, t.opts
          and vim.tbl_deep_extend("force", {}, opts_copy, t.opts)
          or opts_copy)
        pickers[name] = def
      end
      -- Instantiate the previewer, opts isn't guaranteed if the picker
      -- isn't avilable, e.g. `tags` when not tags file exists
      if def.opts and def.opts.previewer then
        def.previewer = require("fzf-lua.previewer").new(def.opts.previewer, def.opts)
      end
    else
      utils.warn("invalid picker '%s', ignoring.", name)
    end
  end

  -- Test for default/starting picker
  local default_picker = opts.pickers[1] and pickers[opts.pickers[1][1]]
  if not default_picker or default_picker.prefix then
    utils.error("default picker not defined or has a prefix, aborting.")
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
        -- Patch the opts refs with important values for path parsing
        -- e.g. formatter, path_shorten, etc
        cur_picker = cur_picker or new_picker
        -- TODO: is there a better way to override the callback opts ref?
        opts.__alt_opts = new_picker.opts
        -- Attach a new previewer if exists
        local win = FzfLua.utils.fzf_winobj()
        if win
            and new_picker.previewer
            and new_picker.previewer ~= cur_picker.previewer
        then
          win:close_preview()
          win:attach_previewer(new_picker.previewer)
          win:redraw_preview()
        end
        reload = string.format("reload(%s)+", new_picker.contents)
        cur_sub = new_sub
        cur_picker = new_picker
      end
      return reload .. string.format("search(%s)", q:sub(cur_sub))
    end, opts, "{q}")
  end

  -- Insert at the start of the args table so `line_query` callback is first
  table.insert(opts._fzf_cli_args, 1, "--bind="
    .. libuv.shellescape("start:+transform:" .. transform_picker(true)))

  table.insert(opts._fzf_cli_args, 2, "--bind="
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
