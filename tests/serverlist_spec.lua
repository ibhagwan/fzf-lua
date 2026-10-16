---@diagnostic disable: unused-local, unused-function, unused
-- Serverlist unit + lifecycle tests. Everything runs in-process (no fzf
-- UI): pure helpers are asserted directly, server discovery/kill/connect
-- run against disposable `--listen` siblings spawned below.
local helpers = require("fzf-lua.test.helpers")
local eq = helpers.expect.equality

local fzf = require("fzf-lua")
local utils = fzf.utils
local actions = require("fzf-lua.actions")
local providers = require("fzf-lua.providers.nvim")

-- Flat, fail-fast bounds (no scaling multiplier): every wait below is
-- strictly bounded so a slow/broken environment fails loudly instead of
-- burning the CI job timeout with cascaded long polls. Spawning a stock
-- headless nvim takes ~1s locally; 30s is generous even for a cold box.
local function wait_until(fn, timeout)
  return vim.wait(timeout or 5000, fn, 50)
end

local sibling_seq = 0
---@param extra string[]? extra argv, e.g. `{ "--embed" }`
---@param name string? explicit listen address (must match discovery scan)
---@return integer jobid, string addr
local function spawn_sibling(extra, name)
  sibling_seq = sibling_seq + 1
  local addr = name
  if not addr then
    -- NOTE: names must match the discovery scan (`nvim*`) yet must NOT
    -- contain `fzf-lua` (own-infra filter) or `nvim-term-` (pty filter)
    if utils.__IS_WINDOWS then
      addr = ([[\\.\pipe\nvim-srv-test-%d-%d]]):format(vim.fn.getpid(), sibling_seq)
    else
      -- on unix only `nvim*` listeners under the run dir are discovered
      -- (`serverlist()` is not authoritative), so listen there
      local rundir = vim.fn.stdpath("run")
      vim.fn.mkdir(rundir, "p")
      addr = ("%s/nvim-srv-test-%d-%d.sock"):format(rundir, vim.fn.getpid(), sibling_seq)
    end
  end
  -- NOTE: `--embed` siblings also get `--listen` so the address is known
  -- and dialable; exclusion below is then proven by filtering (not absence)
  assert(vim.fn.executable(vim.v.progpath) == 1,
    "nvim binary not executable: " .. tostring(vim.v.progpath))
  local cmd = { vim.v.progpath, "--headless", "--clean", "--noplugin", "--listen", addr }
  for _, a in ipairs(extra or {}) do table.insert(cmd, a) end
  local jobid = vim.fn.jobstart(cmd)
  assert(jobid > 0, "spawn sibling failed")
  if not wait_until(function()
    local ok, info = utils.rpcexec_timed(addr, "nvim_get_chan_info", 0)
    return ok and info and info.id ~= nil
  end, 30000) then
    -- don't leak the dud: reap it before failing loudly
    pcall(vim.fn.jobstop, jobid)
    if not utils.__IS_WINDOWS then pcall(vim.fn.delete, addr) end
    error("sibling never became responsive: " .. addr)
  end
  return jobid, addr
end

local function quit_sibling(jobid, addr)
  pcall(utils.rpcexec_timed, addr, "nvim_exec2", "qa!", {})
  pcall(vim.fn.jobstop, jobid)
  wait_until(function()
    local ok = utils.rpcexec_timed(addr, "nvim_get_chan_info", 0)
    return not ok
  end, 15000)
  if not utils.__IS_WINDOWS then pcall(vim.fn.delete, addr) end
end

-- run fn with a disposable sibling, guaranteeing cleanup (quit+reap)
-- even when fn raises: a leaked live sibling keeps handles that can
-- stall process exit (and the CI step with it) on a later failure
---@param extra string[]?
---@param name string?
---@param fn fun(jobid: integer, addr: string)
local function with_sibling(extra, name, fn)
  local jobid, addr = spawn_sibling(extra, name)
  local ok, err = pcall(fn, jobid, addr)
  quit_sibling(jobid, addr)
  if not ok then error(err) end
end

-- compare by backslash form: nightly reports pipes slash-normalized
-- (`//./pipe/...`, dials the same pipe) while stable uses `\\.\pipe\`
local function list_has_addr(list, want)
  for _, p in ipairs(list) do
    if p == want or p:gsub("/", "\\") == want then return true end
  end
  return false
end

---@param addr string
local function serverlist_entry(addr)
  return ("somecwd 1K 0.0%%%s%s"):format(utils.nbsp, utils.ansi_codes.grey(addr))
end

describe("serverlist parse_entry", function()
  local orig_is_windows = utils.__IS_WINDOWS
  it("parses plain entries", function()
    utils.__IS_WINDOWS = false
    eq(utils.serverlist_parse_entry(serverlist_entry("/tmp/nvim.1.0")), "/tmp/nvim.1.0")
    utils.__IS_WINDOWS = orig_is_windows
  end)
  it("returns nil without delimiter or input", function()
    eq(utils.serverlist_parse_entry(nil), nil)
    eq(utils.serverlist_parse_entry("no delimiter here"), nil)
  end)
  it("trims surrounding whitespace and CR", function()
    utils.__IS_WINDOWS = false
    eq(utils.serverlist_parse_entry(serverlist_entry("/tmp/x") .. " \r"), "/tmp/x")
    utils.__IS_WINDOWS = orig_is_windows
  end)
  it("windows: keeps healthy pipes, repairs eaten backslash", function()
    utils.__IS_WINDOWS = true
    eq(utils.serverlist_parse_entry(serverlist_entry([[\\.\pipe\nvim.1.0]])),
      [[\\.\pipe\nvim.1.0]])
    -- fzf/cmd round trip eats one leading backslash (`\\` -> `\`)
    eq(utils.serverlist_parse_entry(serverlist_entry([[\.\pipe\nvim.1.0]])),
      [[\\.\pipe\nvim.1.0]])
    utils.__IS_WINDOWS = orig_is_windows
  end)
  it("unix: leaves backslashes untouched", function()
    utils.__IS_WINDOWS = false
    eq(utils.serverlist_parse_entry(serverlist_entry([[\\.\pipe\nvim.1.0]])),
      [[\\.\pipe\nvim.1.0]])
    utils.__IS_WINDOWS = orig_is_windows
  end)
end)

describe("serverlist escape_invisible", function()
  it("byte-escapes control bytes, passes the rest", function()
    eq(utils.escape_invisible("a\rb"), "a<0D>b")
    eq(utils.escape_invisible([[\.\pipe\nvim.1.0]]), [[\.\pipe\nvim.1.0]])
    eq(utils.escape_invisible("x\27[0my"), "x<1B>[0my")
  end)
end)

describe("serverlist screenshot_to_plaintext", function()
  it("converts terminal dumps to plain rows, keeps SGR", function()
    local shot = vim.fn.tempname()
    local fd = assert(io.open(shot, "wb"))
    fd:write("24,80\r\n\27[?25l\27[H\27[2J\27[0;36mcyan-row\27[0m   \r\27[Bplain   \r\27[B\27[1mbold\27[0m")
    fd:close()
    eq(utils.screenshot_to_plaintext(shot), true)
    local lines = vim.fn.readfile(shot)
    -- rows keep dumper padding so they fill the preview width
    eq(lines, { "\27[0;36mcyan-row\27[0m   ", "plain   ", "\27[1mbold\27[0m" })
    vim.fn.delete(shot)
  end)
  it("rejects empty and missing files", function()
    local shot = vim.fn.tempname()
    vim.fn.writefile({}, shot)
    eq(utils.screenshot_to_plaintext(shot), false)
    vim.fn.delete(shot)
    eq(utils.screenshot_to_plaintext(shot .. ".nope"), false)
  end)
end)

describe("serverlist discovery", function()
  it("exposes the test seam", function()
    eq(type(providers._discover_servers), "function")
  end)
  it("lists a live sibling and drops it once dead", function()
    with_sibling(nil, nil, function(jobid, addr)
      local function found()
        local res = {}
        providers._discover_servers():each(function(p) res[#res + 1] = p end)
        return res
      end
      -- surface seam errors loudly: if this raises, the case fails with a
      -- traceback instead of looking like an empty result inside wait_until
      found()
      if not wait_until(function() return list_has_addr(found(), addr) end, 20000) then
        error(("sibling missing from discovery: %s (nightly=%s, discovered=%s, serverlist=%s %s)"):format(
          addr, tostring(vim.fn.has("nvim-0.13") == 1),
          vim.inspect(found()), type(vim.fn.serverlist()), vim.inspect(vim.fn.serverlist())))
      end
      quit_sibling(jobid, addr)
      assert(wait_until(function() return not list_has_addr(found(), addr) end, 20000),
        "dead sibling still discovered: " .. addr)
    end)
  end)
  it("lists idle --embed backends", function()
    -- an `--embed` backend with no UI is indistinguishable from a detached
    -- user session (same argv, empty UI list), so it stays listed everywhere
    with_sibling({ "--embed" }, nil, function(_, addr)
      local function found()
        local res = {}
        providers._discover_servers():each(function(p) res[#res + 1] = p end)
        return res
      end
      -- sanity: the embed backend is alive and dialable
      eq(utils.server_probe(addr), true)
      if not wait_until(function() return list_has_addr(found(), addr) end, 20000) then
        error(("embed sibling missing from discovery: %s discovered=%s"):format(
          addr, vim.inspect(found())))
      end
    end)
  end)
  it("unix: lists responsive nvim-term- sockets", function()
    if utils.__IS_WINDOWS then return end
    sibling_seq = sibling_seq + 1
    local rundir = vim.fn.stdpath("run")
    vim.fn.mkdir(rundir, "p")
    local addr = ("%s/nvim-term-test-%d-%d.sock"):format(rundir, vim.fn.getpid(), sibling_seq)
    with_sibling(nil, addr, function()
      local function found()
        local res = {}
        providers._discover_servers():each(function(p) res[#res + 1] = p end)
        return res
      end
      if not wait_until(function() return list_has_addr(found(), addr) end, 15000) then
        error(("nvim-term sibling missing from unix discovery (regression): %s discovered=%s"):format(
          addr, vim.inspect(found())))
      end
    end)
  end)
  it("ignores stale addresses", function()
    local stale = utils.__IS_WINDOWS and [[\\.\pipe\nvim-srv-test-stale]]
        or (vim.fn.tempname() .. "-nvim-srv-test-stale.sock")
    local res = {}
    providers._discover_servers({ stale }):each(function(p) res[#res + 1] = p end)
    eq(list_has_addr(res, stale), false)
  end)
end)

describe("serverlist preview", function()
  it("renders settled multi-row dumps", function()
    with_sibling(nil, nil, function(_, addr)
      assert(utils.rpcexec_timed(addr, "nvim_exec_lua", [=[
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "AAA-first-row", "BBB-second-row" })
        return true
      ]=], {}))
      local previewer = require("fzf-lua.previewer.fzf")
      local shot = vim.fn.tempname()
      local pv = previewer.nvim_server:new({}, { _screenshot = shot })
      -- the dump keeps streaming after act returns on slow machines (and on
      -- unix only the shell `sleep` covers that); a single act may also hit
      -- a transient gatekeeper miss, exactly like a live preview refresh
      -- would, so retry a few times before calling it a failure
      local function converted_rows()
        if not utils.screenshot_to_plaintext(shot) then return {} end
        local ok, lines = pcall(vim.fn.readfile, shot)
        return ok and lines or {}
      end
      local function rows_ok()
        local lines = converted_rows()
        -- rows keep dumper padding (prefix match, never exact)
        return lines[1] and lines[1]:match("^AAA%-first%-row")
          and lines[2] and lines[2]:match("^BBB%-second%-row")
      end
      assert(wait_until(function()
        for _ = 1, 3 do
          local cmd = pv:cmdline(nil).fn({ serverlist_entry(addr) }, 24, 80)
          assert(type(cmd) == "string", "preview returned no command")
          if rows_ok() then return true end
          -- pumping wait (not sleep): deferred screenshot work runs while
          -- waiting, then the next act retries like a preview refresh would
          vim.wait(1000, function() return rows_ok() end, 50)
        end
        return rows_ok()
      end, 30000), "preview rows wrong")
      vim.fn.delete(shot)
    end)
  end)
end)

describe("serverlist actions", function()
  -- capture user-visible messages instead of echoing them (keeps CI logs
  -- clean); restored after each case
  local notes, orig_notify ---@type table?, function?
  local function capture_on()
    orig_notify = utils.notify
    notes = {}
    utils.notify = function(lvl, ...)
      local ok, msg = pcall(string.format, ...)
      notes[#notes + 1] = { lvl = lvl, msg = ok and msg or tostring(select(1, ...)) }
    end
  end
  local function capture_off() utils.notify = orig_notify end
  local function noted(pat)
    for _, n in ipairs(assert(notes)) do
      if n.msg:match(pat) then return n end
    end
  end
  -- run with notifications captured; always restore, so a failing case
  -- can't leak the stub into later specs sharing this process
  local function with_notes(fn)
    capture_on()
    local ok, err = pcall(fn)
    capture_off()
    if not ok then error(err) end
  end
  it("kill terminates a live sibling, tolerates stale entries", function()
    with_notes(function()
      with_sibling(nil, nil, function(_, addr)
        actions.serverlist_kill({ serverlist_entry(addr) })
        assert(wait_until(function() return not utils.server_probe(addr) end, 15000),
          "sibling survived kill: " .. addr)
        assert(noted("Killed 1 server"), "missing kill confirmation")
        -- stale entries must not raise (previously a silent assert)
        eq(pcall(actions.serverlist_kill, { serverlist_entry(addr) }), true)
        assert(noted("already exited"), "missing already-exited note")
      end)
      -- empty selection must warn loudly instead of silently no-op
      eq(pcall(actions.serverlist_kill, {}), true)
      assert(noted("no selection"), "missing no-selection warning")
      -- unparseable entries must reach the callback as noaddr (vim.iter
      -- :map() would drop nils and hide them)
      eq(pcall(actions.serverlist_kill, { "garbage-without-delimiter" }), true)
      assert(noted("no server address"), "missing noaddr warning")
    end)
  end)
  it("kill reports mixed outcomes on both sides", function()
    with_notes(function()
      with_sibling(nil, nil, function(_, addr)
        local stale = utils.__IS_WINDOWS and [[\\.\pipe\nvim-srv-test-stale]]
            or (vim.fn.tempname() .. "-nvim-srv-test-stale.sock")
        actions.serverlist_kill({ serverlist_entry(addr), serverlist_entry(stale) })
        assert(wait_until(function() return not utils.server_probe(addr) end, 15000),
          "sibling survived kill: " .. addr)
        assert(noted("Killed 1 server"), "missing kill confirmation in mixed run")
        assert(noted("already exited"), "missing already-exited note in mixed run")
      end)
    end)
  end)
  it("connect guards unreachable and self targets", function()
    with_notes(function()
      local stale = utils.__IS_WINDOWS and [[\\.\pipe\nvim-srv-test-stale]]
          or (vim.fn.tempname() .. "-nvim-srv-test-stale.sock")
      -- must not throw (and must not detach our UI into the void)
      eq(pcall(actions.serverlist_connect, { serverlist_entry(stale) }), true)
      assert(noted("unreachable"), "missing unreachable warning")
      eq(pcall(actions.serverlist_connect, {}), true)
      -- self-connect is a no-op (never `:detach` ourselves)
      local self_entry = serverlist_entry(vim.v.servername)
      eq(pcall(actions.serverlist_connect, { self_entry }), true)
      assert(noted("Already attached"), "missing already-attached note")
    end)
  end)
end)
