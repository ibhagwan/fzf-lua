local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

-- For AsyncDownloadManager
local Object = require "fzf-lua.class"
local uv = vim.loop

local function get_current_colorscheme()
  if vim.g.colors_name then
    return vim.g.colors_name
  else
    return "default"
  end
end

local M = {}

M.colorschemes = function(opts)
  opts = config.normalize_opts(opts, "colorschemes")
  if not opts then return end

  local current_colorscheme = get_current_colorscheme()
  local current_background = vim.o.background
  local colors = opts.colors or vim.fn.getcompletion("", "color")

  local lazy = package.loaded["lazy.core.util"]
  if lazy and lazy.get_unloaded_rtp then
    local paths = lazy.get_unloaded_rtp("")
    local all_files = vim.fn.globpath(table.concat(paths, ","), "colors/*", 1, 1)
    for _, f in ipairs(all_files) do
      table.insert(colors, vim.fn.fnamemodify(f, ":t:r"))
    end
  end

  if type(opts.ignore_patterns) == "table" then
    colors = vim.tbl_filter(function(x)
      for _, p in ipairs(opts.ignore_patterns) do
        if x:match(p) then
          return false
        end
      end
      return true
    end, colors)
  end

  -- make sure active colorscheme is first entry (#1045)
  for i, c in ipairs(colors) do
    if c == current_colorscheme then
      table.remove(colors, i)
      table.insert(colors, 1, c)
      break
    end
  end

  if opts.live_preview then
    -- must add ':nohidden' or fzf ignores the preview action
    opts.fzf_opts["--preview-window"] = "nohidden:right:0"
    opts.preview = shell.raw_action(function(sel)
      if opts.live_preview and sel then
        vim.cmd("colorscheme " .. sel[1])
        if type(opts.cb_preview) == "function" then
          opts.cb_preview(sel, opts)
        end
      end
    end, nil, opts.debug)
  end

  opts.fn_selected = function(selected, o)
    -- reset color scheme if live_preview is enabled
    -- and nothing or non-default action was selected
    if opts.live_preview and (not selected or #selected[1] > 0) then
      vim.cmd("colorscheme " .. current_colorscheme)
      vim.o.background = current_background
    end

    if selected then
      actions.act(opts.actions, selected, o)
    end

    -- setup fzf-lua's own highlight groups
    utils.setup_highlights()

    if type(opts.cb_exit) == "function" then
      opts.cb_exit(selected, opts)
    end
  end

  core.fzf_exec(colors, opts)
end

M.highlights = function(opts)
  opts = config.normalize_opts(opts, "highlights")
  if not opts then return end

  local contents = function(cb)
    local highlights = vim.fn.getcompletion("", "highlight")

    local function add_entry(hl, co)
      -- translate the highlight using ansi escape sequences
      local x = utils.ansi_from_hl(hl, hl)
      cb(x, function(err)
        if co then coroutine.resume(co) end
        if err then
          -- error, close fzf pipe
          cb(nil)
        end
      end)
      if co then coroutine.yield() end
    end

    local function populate(entries, fn, co)
      for _, e in ipairs(entries) do
        fn(e, co)
      end

      cb(nil, function()
        if co then coroutine.resume(co) end
      end)
    end

    local coroutinify = (opts.coroutinify == nil) and false or opts.coroutinify

    if not coroutinify then
      populate(highlights, add_entry)
    else
      coroutine.wrap(function()
        -- Unable to coroutinify, hl functions fail inside coroutines with:
        -- E5560: vimL function must not be called in a lua loop callback
        -- and using 'vim.schedule'
        -- attempt to yield across C-call boundary
        populate(highlights,
          function(x, co)
            vim.schedule(function()
              add_entry(x, co)
            end)
          end,
          coroutine.running())
        coroutine.yield()
      end)()
    end
  end

  opts.fn_selected = function(selected)
    if selected[1] == 'enter' then
      vim.cmd('hi ' .. selected[2])
      vim.api.nvim_exec2('hi ' .. selected[2], {})
    end
  end

  core.fzf_exec(contents, opts)
end


local AsyncDownloadManager = Object:extend()

function AsyncDownloadManager:new(opts)
  self.path = opts.path
  self.dl_status = tonumber(opts.dl_status)
  self.max_threads = tonumber(opts.max_threads) > 0 and tonumber(opts.max_threads) or 5
  local stat, _ = uv.fs_stat(self.path)
  if stat and stat.type ~= "directory" then
    utils.warn(string.format(
      [["%s" already exists and is not a directory (type:%s)]], self.path, stat.type))
    return
  end
  if not stat then
    if vim.fn.mkdir(self.path, "p") ~= 1 then
      utils.warn(string.format([[Unable to create cache directory "%s"]], self.path))
      return
    end
  end
  if not self:load_db(opts.db) then
    return
  end
  self.job_ids = {}
  self.job_stack = {}
  return self
end

function AsyncDownloadManager:destruct()
  for id, _ in pairs(self.job_ids) do
    vim.fn.jobstop(tonumber(id))
  end
end

function AsyncDownloadManager:jobwait_all(co)
  local jobs = {}
  for id, _ in pairs(self.job_ids) do
    table.insert(jobs, tonumber(id))
  end
  if #jobs > 0 then
    vim.fn.jobwait(jobs)
    if co then coroutine.resume(co) end
  end
end

function AsyncDownloadManager:load_db(db)
  -- store db ref and update package params
  self.db = db
  for k, p in pairs(self.db or {}) do
    if type(p.url) ~= "string" then
      utils.warn(string.format("package %s: missing 'url'", k))
      return false
    end
    if type(p.colorschemes) ~= "table" or utils.tbl_isempty(p.colorschemes) then
      utils.warn(string.format("package %s: missing or empty 'colorschemes'", k))
      return false
    end
    local github_url = "https://github.com/"
    p.dir = p.dir or k
    p.path = path.normalize(path.join({ self.path, p.dir }))
    p.package = p.package or k
    p.disp_name = p.disp_name or k
    p.disp_url = p.disp_url or p.url
    p.disp_url = p.disp_url:gsub("^" .. github_url, "")
    if not p.url:match("^https://") then
      p.url = github_url .. p.url
    end
    if type(p.colorschemes[1]) == "string" then
      p.colorschemes[1] = { name = p.colorschemes[1] }
    end
    for i, v in ipairs(p.colorschemes) do
      p.colorschemes[i].disp_name = v.disp_name or p.disp_name
      if not v.name and not v.lua and not v.vim then
        utils.warn(string.format(
          "package %s: colorschemes[%d], must contain at least 'name|lua|vim'", k, i))
        return false
      end
    end
    self.db[k] = p
  end
  -- caller requested a download filter
  if self.dl_status == 0 or self.dl_status == 1 then
    for k, _ in pairs(self.db or {}) do
      local downloaded = self:downloaded(k)
      if self.dl_status == 0 and downloaded
          or self.dl_status == 1 and not downloaded then
        self.db[k] = nil
      end
    end
  end
  return true
end

function AsyncDownloadManager:downloaded(plugin)
  local info = plugin and self.db[plugin]
  if not info then return end
  local stat = uv.fs_stat(info.path)
  return stat and stat.type == "directory"
end

function AsyncDownloadManager:downloading(plugin)
  local info = plugin and self.db[plugin]
  return info and info.job_id
end

function AsyncDownloadManager:get(plugin)
  return plugin and self.db[plugin] or nil
end

function AsyncDownloadManager:set_once_on_exit(plugin, fn)
  if not plugin or not self.db[plugin] then return end
  self.db[plugin].on_exit = function(...)
    fn(...)
    self.db[plugin].on_exit = nil
  end
end

function AsyncDownloadManager:jobwait(plugin)
  local info = plugin and self.db[plugin]
  if not info or not info.job_id then return end
  vim.fn.jobwait({ info.job_id })
end

function AsyncDownloadManager:delete(plugin)
  if not plugin or not self.db[plugin] then return end
  if self:downloaded(plugin) then
    vim.fn.delete(self.db[plugin].path, "rf")
  end
end

function AsyncDownloadManager:queue(plugin, job_args)
  if utils.tbl_count(self.job_ids) < self.max_threads then
    self:jobstart(plugin, job_args)
  else
    table.insert(self.job_stack, { plugin, job_args })
    -- while in queue, mark plugin as "downloading"
    self.db[plugin].job_id = true
  end
end

function AsyncDownloadManager:dequeue()
  if #self.job_stack > 0 then
    local plugin, job_args = unpack(table.remove(self.job_stack, #self.job_stack))
    self:jobstart(plugin, job_args)
  end
end

function AsyncDownloadManager:jobstart(plugin, job_args)
  if not plugin then return end
  local info = plugin and self.db[plugin]
  local msg = string.format("%s %s (%s)",
    job_args[1][2] == "clone" and "Cloning" or "Updating", info.disp_name, info.dir)
  local job_id
  job_args[2] = vim.tbl_extend("keep", job_args[2] or {},
    {
      on_exit = function(_, rc, _)
        utils.info(string.format("%s [job_id:%d] finished with exit code %s", plugin, job_id, rc))
        if type(info.on_exit) == "function" then
          -- this calls `coroutine.resume` and resumes fzf's reload input stream
          info.on_exit(_, rc, _)
        end
        self.job_ids[tostring(job_id)] = nil
        self.db[plugin].job_id = nil
        -- dequeue the next job
        self:dequeue()
      end
    })
  job_id = vim.fn.jobstart(unpack(job_args))
  if job_id == 0 then
    utils.warn("jobstart: invalid args")
  elseif job_id == -1 then
    utils.warn(string.format([[jobstart: "%s" is not executable]], job_args[1]))
  else
    -- job started successfully
    utils.info(string.format("%s [path:%s] [job_id:%d]...",
      msg, path.HOME_to_tilde(info.path), job_id))
    self.job_ids[tostring(job_id)] = { plugin = plugin, args = job_args }
    self.db[plugin].job_id = job_id
  end
end

function AsyncDownloadManager:update(plugin)
  local info = plugin and self.db[plugin]
  if not info then return end
  if self:downloaded(plugin) then
    -- git pull
    self:queue(plugin, {
      ---@format disable-next
      { "git",          "pull", "--rebase" },
      { cwd = info.path }
    })
  else
    -- git clone
    self:queue(plugin, {
      -- { "git", "clone", "--depth=1", info.url, info.dir }  -- shallow clone
      { "git", "clone", "--filter", "tree:0", info.url, info.path } -- treeless clone
    })
  end
end

M.apply_awesome_theme = function(dbkey, idx, opts)
  assert(dbkey, "colorscheme dbkey is nil")
  assert(opts._adm, "async download manager is nil")
  local p = opts._adm:get(dbkey)
  assert(p, "colorscheme package is nil")
  assert(tonumber(idx) > 0, "colorscheme index is invalid")
  local cs = p.colorschemes[tonumber(idx)]
  -- TODO: should we check `package.loaded[...]` before packadd?
  local ok, out = pcall(function() vim.cmd("packadd " .. p.dir) end)
  if not ok then
    utils.warn(string.format("Unable to packadd  %s: %s", p.dir, tostring(out)))
    return
  end
  if cs.vim then
    ok, out = pcall(vim.api.nvim_exec2, cs.vim, { output = true })
  elseif cs.lua then
    ok, out = pcall(function() loadstring(cs.lua)() end)
  else
    ok, out = pcall(function() vim.cmd("colorscheme " .. cs.name) end)
  end
  if not ok then
    utils.warn(string.format("Unable to apply colorscheme %s: %s", cs.disp_name, tostring(out)))
  end
end

M.awesome_colorschemes = function(opts)
  opts = config.normalize_opts(opts, "awesome_colorschemes")
  if not opts then return end

  opts._cur_colorscheme = get_current_colorscheme()
  opts._cur_background = vim.o.background

  local dbfile = vim.fn.expand(opts.dbfile)
  if not path.is_absolute(dbfile) then
    dbfile = path.normalize(path.join({ vim.g.fzf_lua_directory, opts.dbfile })) or dbfile
  end

  local json_string = utils.read_file(dbfile)
  if not json_string or #json_string == 0 then
    utils.warn(string.format("Unable to load json db (%s)", opts.dbfile))
    return
  end

  local ok, json_db = pcall(vim.json.decode, json_string)
  if not ok then
    utils.warn(string.format("Json decode failed: %s", json_db))
    return
  end

  -- save a ref for action
  opts._apply_awesome_theme = M.apply_awesome_theme

  opts._packpath = type(opts.packpath) == "function"
      and opts.packpath() or tostring(opts.packpath)

  opts._adm = AsyncDownloadManager:new({
    db = json_db,
    dl_status = opts.dl_status,
    max_threads = opts.max_threads,
    path = path.join({ opts._packpath, "pack", "fzf-lua", "opt" })
  })
  -- Error creating cache directory
  if not opts._adm then return end

  opts.func_async_callback = false
  opts.__fn_reload = function(_)
    return function(cb)
      -- use coroutine & vim.schedule to avoid
      -- E5560: vimL function must not be called in a lua loop callback
      coroutine.wrap(function()
        local co = coroutine.running()

        -- make sure our cache is in packpath
        vim.opt.packpath:append(opts._packpath)

        -- since resume uses deepcopy having multiple db's is going to
        -- create all sorts of voodoo issues when running resume
        -- HACK: find a better solution (singleton?)
        if config.__resume_data and type(config.__resume_data.opts) == "table" then
          config.__resume_data.opts._adm.db = opts._adm.db
        end

        local sorted = vim.tbl_keys(json_db)
        table.sort(sorted)

        for _, dbkey in ipairs(sorted) do
          local downloaded = opts._adm:downloaded(dbkey)
          local info = opts._adm:get(dbkey)
          for i, cs in ipairs(info.colorschemes) do
            if opts._adm:downloading(dbkey) then
              -- downloading, set `on_exit` callback and wait for resume
              opts._adm:set_once_on_exit(dbkey, function(_, _, _)
                coroutine.resume(co)
              end)
              coroutine.yield()
            end
            vim.schedule(function()
              local icon = not downloaded
                  and opts.icons[1]           -- download icon
                  or i == 1 and opts.icons[2] -- colorscheme (package) icon
                  or opts.icons[3]            -- colorscheme (variant) noicon
              local entry = string.format("%s:%d:%s  %s %s",
                dbkey,
                i,
                icon,
                cs.disp_name,
                i == 1 and string.format("(%s)", info.disp_url) or "")
              cb(entry, function()
                coroutine.resume(co)
              end)
            end)
            coroutine.yield()
          end
        end

        -- done
        cb(nil)
      end)()
    end
  end

  local prev_act_id
  if opts.live_preview then
    opts.fzf_opts["--preview-window"] = "nohidden:right:0"
    opts.preview, prev_act_id = shell.raw_action(function(sel)
      if opts.live_preview and sel then
        local dbkey, idx = sel[1]:match("^(.-):(%d+):")
        if opts._adm:downloaded(dbkey) then
          -- some colorschemes choose a different theme based on dark|light bg
          -- restore to the original background when interface was opened
          -- wrap in pcall as some colorschemes have bg triggers that can fail
          pcall(function() vim.o.background = opts._cur_background end)
          M.apply_awesome_theme(dbkey, idx, opts)
          if type(opts.cb_preview) == "function" then
            opts.cb_preview(sel, opts)
          end
        else
          vim.cmd("colorscheme " .. opts._cur_colorscheme)
          vim.o.background = opts._cur_background
        end
      end
    end, "{}", opts.debug)
  end

  -- build the "reload" cmd and remove '-- {+}' from the initial cmd
  local reload, id = shell.reload_action_cmd(opts, "{+}")
  local contents = reload:gsub("%-%-%s+{%+}$", "")
  opts.__reload_cmd = reload

  opts._fn_pre_fzf = function()
    shell.set_protected(id)
    if prev_act_id then
      shell.set_protected(prev_act_id)
    end
  end

  opts.fn_selected = function(sel, o)
    -- do not remove our cache path from packpath
    -- or packadd in `apply_awesome_theme` fails
    -- vim.opt.packpath:remove(o._packpath)

    -- cleanup AsyncDownloadManager
    o._adm:destruct()

    -- reset color scheme if live_preview is enabled
    -- and nothing or non-default action was selected
    if o.live_preview and (not sel or #sel[1] > 0) then
      vim.cmd("colorscheme " .. o._cur_colorscheme)
      vim.o.background = o._cur_background
    end

    if sel then
      actions.act(o.actions, sel, o)
    end

    -- setup fzf-lua's own highlight groups
    utils.setup_highlights()

    if type(o.cb_exit) == "function" then
      o.cb_exit(sel, o)
    end
  end

  opts = core.set_header(opts, opts.headers or { "actions" })
  return core.fzf_exec(contents, opts)
end

return M
