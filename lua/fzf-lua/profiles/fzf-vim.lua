local fzf_lua = require("fzf-lua")
local actions = fzf_lua.actions

local function cmd_exists(cmd)
  local ret = vim.fn.exists(":" .. cmd)
  if type(ret) == "number" and ret ~= 0 then
    return true
  end
end

local function setup_commands(no_override, prefix)
  local cb_create = function(provider, arg, altmap)
    local function fzflua_opts(o)
      local ret = {}
      -- fzf.vim's bang version of the commands opens fullscreen
      if o.bang then ret.winopts = { fullscreen = true } end
      return ret
    end
    return function(o)
      local prov = provider
      local opts = fzflua_opts(o) -- setup bang!
      if type(o.fargs[1]) == "string" then
        local farg = o.fargs[1]
        for c, p in pairs(altmap or {}) do
          -- fzf.vim hijacks the first character of the arg
          -- to setup special commands postfixed with `?:/`
          -- "GFiles?", "History:" and "History/"
          if farg:sub(1, 1) == c then
            prov = p
            -- we still allow using args with alt
            -- providers by removing the "?:/" prefix
            farg = #farg > 1 and vim.trim(farg:sub(2))
            break
          end
        end
        if arg and farg and #farg > 0 then
          opts[arg] = vim.trim(farg)
        end
      end
      fzf_lua[prov](opts)
    end
  end

  local cmds = {
    ["Files"] = cb_create("files", "cwd"),
    ["GFiles"] = cb_create("git_files", "cwd", { ["?"] = "git_status" }),
    ["Buffers"] = cb_create("buffers"),
    ["Colors"] = cb_create("colorschemes"),
    ["Rg"] = cb_create("grep", "search"),
    ["RG"] = cb_create("live_grep", "search"),
    ["Lines"] = cb_create("lines", "query"),
    ["BLines"] = cb_create("blines", "query"),
    ["Tags"] = cb_create("tags", "query"),
    ["BTags"] = cb_create("btags", "query"),
    ["Changes"] = cb_create("changes"),
    ["Marks"] = cb_create("marks"),
    ["Jumps"] = cb_create("jumps"),
    ["History"] = cb_create("oldfiles", "query", {
      [":"] = "command_history",
      ["/"] = "search_history",
    }),
    ["Commits"] = cb_create("git_commits", "query"),
    ["BCommits"] = cb_create("git_bcommits", "query"),
    ["Maps"] = cb_create("keymaps", "query"),
    ["Helptags"] = cb_create("help_tags", "query"),
    ["Filetypes"] = cb_create("filetypes", "query"),
  }

  for cmd, cb in pairs(cmds) do
    cmd = (prefix or "") .. cmd
    if not cmd_exists(cmd) or no_override ~= true then
      pcall(vim.api.nvim_del_user_command, cmd)
      vim.api.nvim_create_user_command(cmd, cb, { bang = true, nargs = "?" })
    end
  end
end

return {
  fn_load = setup_commands,
  desc = "fzf.vim defaults",
  winopts = {
    height = 0.59,
    width = 0.90,
    row = 0.48,
    col = 0.45,
    preview = {
      hidden = "hidden",
      vertical = "up:45%",
    },
  },
  hls = {
    border = "FloatBorder",
    help_border = "FloatBorder",
    preview_border = "FloatBorder",
  },
  fzf_opts = {
    -- nullify fzf-lua's settings to inherit from FZF_DEFAULT_OPTS
    ["--info"] = false,
    ["--layout"] = false,
  },
  fzf_colors = vim.g.fzf_colors,
  keymap = {
    builtin = {
      ["<F1>"]     = "toggle-help",
      ["<F2>"]     = "toggle-fullscreen",
      ["<F3>"]     = "toggle-preview-wrap",
      -- nvim registers <C-/> as <C-_>, use insert mode
      -- and press <C-v><C-/> should output ^_
      ["<C-_>"]    = "toggle-preview",
      ["<F5>"]     = "toggle-preview-ccw",
      ["<F6>"]     = "toggle-preview-cw",
      ["<S-down>"] = "preview-page-down",
      ["<S-up>"]   = "preview-page-up",
      ["<S-left>"] = "preview-page-reset",
    },
    fzf = {
      ["ctrl-z"]     = "abort",
      ["ctrl-u"]     = "unix-line-discard",
      ["ctrl-f"]     = "half-page-down",
      ["ctrl-b"]     = "half-page-up",
      ["ctrl-a"]     = "beginning-of-line",
      ["ctrl-e"]     = "end-of-line",
      ["alt-a"]      = "toggle-all",
      ["f3"]         = "toggle-preview-wrap",
      ["ctrl-/"]     = "toggle-preview",
      ["shift-down"] = "preview-page-down",
      ["shift-up"]   = "preview-page-up",
    },
  },
  actions = {
    files = {
      ["default"] = actions.file_edit_or_qf,
      ["ctrl-x"] = actions.file_split,
      ["ctrl-v"] = actions.file_vsplit,
      ["ctrl-t"] = actions.file_tabedit,
      ["alt-q"] = actions.file_sel_to_qf,
      ["alt-l"] = actions.file_sel_to_ll,
    },
    buffers = {
      ["default"] = actions.buf_edit,
      ["ctrl-x"] = actions.buf_split,
      ["ctrl-v"] = actions.buf_vsplit,
      ["ctrl-t"] = actions.buf_tabedit,
    }
  },
  files = {
    cmd = os.getenv("FZF_DEFAULT_COMMAND"),
    cwd_prompt = true,
    cwd_prompt_shorten_len = 1,
  },
  grep = {
    git_icons = false,
    exec_empty_query = true,
  },
}
