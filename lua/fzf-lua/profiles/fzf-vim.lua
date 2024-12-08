local fzf_lua = require("fzf-lua")
local actions = fzf_lua.actions
local utils = fzf_lua.utils

local function cmd_exists(cmd)
  local ret = vim.fn.exists(":" .. cmd)
  if type(ret) == "number" and ret ~= 0 then
    return true
  end
end

local function setup_commands(no_override, prefix)
  local cmds = {
    ["Files"] = utils.create_user_command_callback("files", "cwd"),
    ["GFiles"] = utils.create_user_command_callback("git_files", "cwd", { ["?"] = "git_status" }),
    ["Buffers"] = utils.create_user_command_callback("buffers"),
    ["Colors"] = utils.create_user_command_callback("colorschemes"),
    ["Rg"] = utils.create_user_command_callback("grep", "search"),
    ["RG"] = utils.create_user_command_callback("live_grep", "search"),
    ["Lines"] = utils.create_user_command_callback("lines", "query"),
    ["BLines"] = utils.create_user_command_callback("blines", "query"),
    ["Tags"] = utils.create_user_command_callback("tags", "query"),
    ["BTags"] = utils.create_user_command_callback("btags", "query"),
    ["Changes"] = utils.create_user_command_callback("changes"),
    ["Marks"] = utils.create_user_command_callback("marks"),
    ["Jumps"] = utils.create_user_command_callback("jumps"),
    ["Commands"] = utils.create_user_command_callback("commands"),
    ["History"] = utils.create_user_command_callback("oldfiles", "query", {
      [":"] = "command_history",
      ["/"] = "search_history",
    }),
    ["Commits"] = utils.create_user_command_callback("git_commits", "query"),
    ["BCommits"] = utils.create_user_command_callback("git_bcommits", "query"),
    ["Maps"] = utils.create_user_command_callback("keymaps", "query"),
    ["Helptags"] = utils.create_user_command_callback("help_tags", "query"),
    ["Filetypes"] = utils.create_user_command_callback("filetypes", "query"),
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
  keymap = {
    builtin = {
      true,
      -- nvim registers <C-/> as <C-_>, use insert mode
      -- and press <C-v><C-/> should output ^_
      ["<C-_>"] = "toggle-preview",
    },
    fzf = {
      true,
      ["ctrl-/"] = "toggle-preview",
    },
  },
  actions = {
    files = {
      ["enter"] = actions.file_edit_or_qf,
      ["ctrl-x"] = actions.file_split,
      ["ctrl-v"] = actions.file_vsplit,
      ["ctrl-t"] = actions.file_tabedit,
      ["alt-q"] = actions.file_sel_to_qf,
      ["alt-l"] = actions.file_sel_to_ll,
    },
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
