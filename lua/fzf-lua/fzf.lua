-- slimmed down version of nvim-fzf's 'raw_fzf', changes include:
-- DOES NOT SUPPORT WINDOWS
-- does not close the pipe before all writes are complete
-- option to not add '\n' on content function callbacks
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/lua/fzf.lua
local uv = vim.uv or vim.loop

local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"

local M = {}

-- workaround to a potential 'tempname' bug? (#222)
-- neovim doesn't guarantee the existence of the
-- parent temp dir potentially failing `mkfifo`
-- https://github.com/neovim/neovim/issues/1432
-- https://github.com/neovim/neovim/pull/11284
local function tempname()
  local tmpname = vim.fn.tempname()
  local parent = vim.fn.fnamemodify(tmpname, ":h")
  -- parent must exist for `mkfifo` to succeed
  -- if the neovim temp dir was deleted or the
  -- tempname already exists, we use 'os.tmpname'
  if not uv.fs_stat(parent) or uv.fs_stat(tmpname) then
    tmpname = os.tmpname()
    -- 'os.tmpname' touches the file which
    -- will also fail `mkfifo`, delete it
    vim.fn.delete(tmpname)
  end
  return tmpname
end

-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. The latter can use coroutines for async
-- behavior.
---@param contents string?
---@param fzf_cli_args string[]
---@param opts table
---@return table selected
---@return integer exit_code
function M.raw_fzf(contents, fzf_cli_args, opts)
  assert(not contents or type(contents) == "string",
    "contents must be of type string: " .. tostring(contents))
  if not coroutine.running() then
    error("[Fzf-lua] function must be called inside a coroutine.")
  end

  if not opts then opts = {} end
  local cmd = { opts.fzf_bin or "fzf" }
  local outputtmpname = tempname()

  -- we use a temporary env $FZF_DEFAULT_COMMAND instead of piping
  -- the command to fzf, this way fzf kills the command when it exits.
  -- This is especially important with our shell helper as io.write fails
  -- to select when the pipe is broken (EPIPE) so the neovim headless
  -- instance never terminates which hangs fzf on exit
  local FZF_DEFAULT_COMMAND = (function()
    if not contents then return nil end
    if #contents == 0 then
      contents = utils.shell_nop()
    end
    if opts.silent_fail ~= false then
      contents = contents .. " || " .. utils.shell_nop()
    end
    return contents
  end)()

  utils.tbl_join(cmd, fzf_cli_args or {})

  local function get_EOL(flag)
    for _, f in ipairs(cmd) do
      if f:match("%-%-" .. flag) then
        return "\0"
      end
    end
    return "\n"
  end

  -- local readEOL = get_EOL("read0")
  local printEOL = get_EOL("print0")

  table.insert(cmd, ">")
  table.insert(cmd, libuv.shellescape(outputtmpname))

  if not opts.is_fzf_tmux then
    -- A pesky bug I fixed upstream and was merged in 0.11/0.10.2:
    -- <C-c> in term buffers was making neovim freeze, as a workaround in older
    -- versions (not perfect could still hang) we map <C-c> to <Esc> locally
    -- https://github.com/neovim/neovim/issues/20726
    -- https://github.com/neovim/neovim/pull/30056
    if not utils.__HAS_NVIM_0102 then
      vim.keymap.set("t", "<C-c>", "<Esc>", { buffer = 0 })
    end

    -- A more robust way of entering TERMINAL mode "t". We had quite a few issues
    -- sending `feedkeys|startinsert` after the term job is started, this approach
    -- seems more consistent as it triggers when entering terminal normal mode "nt"
    -- NOTE: **DO NOT USE** seems to cause valrious issues see #1672
    -- vim.api.nvim_create_autocmd("ModeChanged", {
    --   once = true,
    --   buffer = 0,
    --   callback = function(e)
    --     if e.match:match(":nt") then
    --       vim.defer_fn(function()
    --         -- Prevents inserting "i" when spamming `ctrl-g` in `grep_lgrep`
    --         -- Also verify we're not already in TERMINAL mode, could happen
    --         -- if the user has an autocmd for TermOpen with `startinsert`
    --         if vim.api.nvim_buf_is_valid(e.buf)
    --             and vim.api.nvim_get_mode().mode ~= "t"
    --         then
    --           vim.cmd("startinsert")
    --         end
    --       end, 0)
    --     end
    --   end
    -- })
  end

  if opts.debug and type(opts.debug) ~= "number" then
    utils.info("FZF_DEFAULT_COMMAND: %s", tostring(FZF_DEFAULT_COMMAND))
    utils.info("fzf cmd: %s", table.concat(cmd, " "))
  end

  local co = coroutine.running()
  local jobstart = opts.is_fzf_tmux and vim.fn.jobstart or utils.termopen
  local shell_cmd = utils.__IS_WINDOWS
      -- MSYS2 comes with "/usr/bin/cmd" that precedes "cmd.exe" (#1396)
      and { "cmd.exe", "/d", "/e:off", "/f:off", "/v:off", "/c" }
      or { "sh", "-c" }
  if opts.pipe_cmd then
    if FZF_DEFAULT_COMMAND then
      table.insert(cmd, 1, string.format("(%s) | ", FZF_DEFAULT_COMMAND))
      FZF_DEFAULT_COMMAND = nil
    end
    table.insert(shell_cmd, table.concat(cmd, " "))
  elseif utils.__IS_WINDOWS then
    utils.tbl_join(shell_cmd, cmd)
  else
    table.insert(shell_cmd, table.concat(cmd, " "))
  end
  -- This obscure option makes jobstart fail with: "The syntax of the command is incorrect"
  -- temporarily set to `false`, for more info see `:help shellslash` (#1055)
  local nvim_opt_shellslash = utils.__WIN_HAS_SHELLSLASH and vim.o.shellslash
  if nvim_opt_shellslash then vim.o.shellslash = false end
  jobstart(shell_cmd, {
    cwd = opts.cwd,
    pty = true,
    env = {
      ["SHELL"] = shell_cmd[1],
      -- Nullify "NVIM_LISTEN_ADDRESS", will cause issues if already in use (#2253)
      ["NVIM_LISTEN_ADDRESS"] = "",
      ["FZF_DEFAULT_COMMAND"] = FZF_DEFAULT_COMMAND,
      ["SKIM_DEFAULT_COMMAND"] = FZF_DEFAULT_COMMAND,
      ["FZF_LUA_SERVER"] = vim.g.fzf_lua_server,
      -- sk --tmux didn't pass all environemnt variable (https://github.com/skim-rs/skim/issues/732)
      ["SKIM_FZF_LUA_SERVER"] = vim.g.fzf_lua_server,
      ["VIMRUNTIME"] = vim.env.VIMRUNTIME,
      ["FZF_DEFAULT_OPTS"] = (function()
        -- Newer style `--preview-window` options in FZF_DEFAULT_OPTS such as:
        --   --preview-window "right,50%,hidden,<60(up,70%,hidden)"
        -- prevents our previewer from working properly, since there is never
        -- a reason to inherit `preview-window` options it can be safely stripped
        -- from FZF_DEFAULT_OPTS (#1107)
        local default_opts = os.getenv("FZF_DEFAULT_OPTS")
        if not default_opts then return end
        local patterns = { "--preview-window" }
        for _, p in ipairs(patterns) do
          -- remove flag end of string
          default_opts = default_opts:gsub(utils.lua_regex_escape(p) .. "[=%s]+[^%-]+%s-$", "")
          -- remove flag start/mid of string
          default_opts = default_opts:gsub(utils.lua_regex_escape(p) .. "[=%s]+.-%s+%-%-", " --")
        end
        return default_opts
      end)(),
      -- Nullify user's RG config as this can cause conflicts
      -- with fzf-lua's rg opts (#1266)
      ["RIPGREP_CONFIG_PATH"] = type(opts.RIPGREP_CONFIG_PATH) == "string"
          and libuv.expand(opts.RIPGREP_CONFIG_PATH) or "",
      -- Prevents spamming rust logs with skim (#1959)
      ["RUST_LOG"] = "",
    },
    on_exit = function(_, rc, _)
      local output = {}
      local f = io.open(outputtmpname)
      if f then
        output = vim.split(f:read("*a"), printEOL)
        -- `file:read("*a")` appends an empty string on EOL
        output[#output] = nil
        f:close()
      end
      -- Windows only, restore `shellslash` if was true before `jobstart`
      if nvim_opt_shellslash then vim.o.shellslash = nvim_opt_shellslash end
      vim.fn.delete(outputtmpname)
      if #output == 0 then output = nil end
      coroutine.resume(co, output, rc)
    end
  })

  -- fzf-tmux spawns outside neovim, don't set filetype/insert mode
  if not opts.is_fzf_tmux then
    vim.bo.filetype = "fzf"

    local fzfwin = utils.fzf_winobj()
    if fzfwin then fzfwin:update_statusline() end

    -- See note in "ModeChanged" above
    if vim.api.nvim_get_mode().mode == "t" then
      -- Called from another fzf-win most likely
      utils.feed_keys_termcodes("i")
    else
      vim.cmd [[startinsert]]
    end
  end

  return coroutine.yield()
end

return M
