local uv = vim.uv or vim.loop
local fzf = require("fzf-lua")
return {
  desc     = "hide interface instead of abort",
  keymap   = {
    builtin = {
      true,
      -- NOTE: we use a custom <Esc> callback that also sends esc to fzf
      -- so we can store the last query on the execute-silent callback
      -- ["<Esc>"] = "hide",
      ["<M-Esc>"] = "abort"
    }
  },
  defaults = {
    enrich = function(opts)
      -- Do not hide if resume is disabled (#2425)
      if opts.no_resume or opts.no_hide then return opts end
      if opts._is_fzf_tmux then
        fzf.utils.warn("'hide' profile cannot work with tmux, ignoring.")
        return opts
      end
      opts.actions = opts.actions or {}
      if fzf.utils.has(opts, "sk") then
        -- `execute-silent` actions are bugged with skim
        -- Set esc to hide since we aren't using the custom callback
        opts.actions["esc"] = false
        opts.keymap.builtin["<Esc>"] = "hide"
        return opts
      end
      local histfile = opts.fzf_opts and opts.fzf_opts["--history"]
      opts.winopts = opts.winopts or {}
      local _on_create = opts.winopts.on_create
      opts.winopts.on_create = function(e)
        -- While we can use `keymap.builtin.<esc>` (to hide) this is better
        -- as it captures the query when execute-silent action is called as
        -- we add "{q}" as the first field index similar to `--print-query`
        vim.keymap.set({ "t", "n" }, "<Esc>", function()
          -- We hide the window first which happens instantly
          -- and then send <Esc> directly to the term channel
          fzf.hide()
          vim.api.nvim_chan_send(vim.bo[e.bufnr].channel, "\x1b")
        end, { buffer = e.bufnr, nowait = true })
        -- Call the users' on_create?
        if type(_on_create) == "function" then
          _on_create(e)
        end
      end
      opts.actions["esc"] = {
        fn = fzf.actions.dummy_abort,
        desc = "hide",
        -- NOTE: we add this so esc action isn't converted in the
        -- `tbl_map` below preventing fzf history append on esc
        -- exec_silent = true,
      }
      for k, act in pairs(opts.actions) do
        act = type(act) == "function" and { fn = act } or act
        act = type(act) == "table" and type(act[1]) == "function"
            and { fn = act[1], reuse = true } or act
        assert(type(act) == "table" and type(act.fn) == "function" or not act)
        if type(act) == "table" and
            not act.exec_silent
            and not act.reload
            and not act.noclose
            and not act.reuse
            -- ignore `false` actions (#2407)
            and not k:match("^_")
        then
          local fn = act.fn
          act.exec_silent = true
          act.desc = act.desc or fzf.config.get_action_helpstr(fn)
          act.fn = function(...)
            fzf.hide()
            fn(...)
            -- As the process never terminates fzf history is never written
            -- manually append to the fzf history file if needed
            local o = select(2, ...)
            if histfile and type(o.last_query) == "string" and #o.last_query > 0 then
              local fd = uv.fs_open(histfile, "a", -1)
              if fd then
                uv.fs_write(fd, o.last_query .. "\n", nil, function(_)
                  uv.fs_close(fd)
                end)
              end
            end
          end
        end
        opts.actions[k] = act
      end
      -- Hijack the resize event to reload buffer/tab list on unhide
      FzfLua.win.on_SIGWINCH(opts, "win.unhide", function()
        if type(opts._contents) == "string"
            and (opts._resume_reload == true
              or type(opts._resume_reload) == "function" and opts._resume_reload(opts))
        then
          return string.format("reload:%s", opts._contents)
        end
      end)
      return opts
    end,
  },
}
