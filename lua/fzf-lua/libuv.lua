---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

local sysname = uv.os_uname().sysname
local _is_win = sysname:match("Windows") and true or false

local M = {}

local base64 = require("fzf-lua.lib.base64")
local serpent = require("fzf-lua.lib.serpent")

---@param pid integer
---@param signal integer|string?
---@return boolean
M.process_kill = function(pid, signal)
  if not pid or not tonumber(pid) then return false end
  if type(uv.os_getpriority(pid)) == "number" then
    uv.kill(pid, signal or 9)
    return true
  end
  return false
end

---@param obj table
---@param b64? boolean
---@return string, boolean -- boolean used for ./scripts/headless_fd.sh
M.serialize = function(obj, b64)
  local str = serpent.line(obj, { name = "_", comment = false, sortkeys = false })
  str = b64 ~= false and base64.encode(str) or str
  return "return [==[" .. str .. "]==]", (b64 ~= false and true or false)
end

---@param str string
---@param b64? boolean
---@return table|any
M.deserialize = function(str, b64)
  local res = assert(loadstring(str))()
  if type(res) == "table" then return res --[[@as table]] end -- ./scripts/headless_fd.sh
  res = b64 ~= false and base64.decode(res) or res
  -- safe=false enable call function
  local ok, obj = serpent.load(res, { safe = false })
  assert(ok, vim.inspect(obj))
  return obj
end

---@param fn_str any
---@return function?
M.load_fn = function(fn_str)
  if type(fn_str) ~= "string" then return end
  local fn_loaded = nil
  local fn = loadstring(fn_str)
  if fn then fn_loaded = fn() end
  if type(fn_loaded) ~= "function" then
    fn_loaded = nil
  end
  return fn_loaded
end

M.is_escaped = function(s, is_win)
  local m
  -- test spec override
  if is_win == nil then is_win = _is_win end
  if is_win then
    m = s:match([[^".*"$]]) or s:match([[^%^".*%^"$]])
  else
    m = s:match([[^'.*'$]]) or s:match([[^".*"$]])
  end
  return m ~= nil
end

-- our own version of vim.fn.shellescape compatible with fish shells
--   * don't double-escape '\' (#340)
--   * if possible, replace surrounding single quote with double
-- from ':help shellescape':
--    If 'shell' contains "fish" in the tail, the "\" character will
--    be escaped because in fish it is used as an escape character
--    inside single quotes.
--
-- for windows, we assume we want to keep all quotes as literals
-- to avoid the quotes being stripped when run from fzf actions
-- we therefore have to escape the quotes with backslashes and
-- for nested quotes we double the backslashes due to windows
-- quirks, further reading:
-- https://stackoverflow.com/questions/6714165/powershell-stripping-double-quotes-from-command-line-arguments
-- https://learn.microsoft.com/en-us/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way
--
-- this function is a better fit for utils but we're
-- trying to avoid having any 'require' in this file
---@param s string
---@param win_style integer|string? 1=classic, 2=caret
---@return string
M.shellescape = function(s, win_style)
  if _is_win or win_style then
    if tonumber(win_style) == 1 then
      --
      -- "classic" CommandLineToArgvW backslash escape
      --
      s = s:gsub([[\-"]], function(x)
        -- Quotes found in string. From the above stackoverflow link:
        --
        -- (2n) + 1 backslashes followed by a quotation mark again produce n backslashes
        -- followed by a quotation mark literal ("). This does not toggle the "in quotes"
        -- mode.
        --
        -- to produce (2n)+1 backslashes we use the following `string.rep` calc:
        -- (#x-1) * 2 + 1 - (#x-1) == #x
        -- which translates to prepending the string with number of escape chars
        -- (\) equal to its own length, this in turn is an **always odd** number
        --
        -- "     ->  \"          (0->1)
        -- \"    ->  \\\"        (1->3)
        -- \\"   ->  \\\\\"      (2->5)
        -- \\\"  ->  \\\\\\\"    (3->7)
        -- \\\\" ->  \\\\\\\\\"  (4->9)
        --
        x = string.rep([[\]], #x) .. x
        return x
      end)
      s = s:gsub([[\+$]], function(x)
        -- String ends with backslashes. From the above stackoverflow link:
        --
        -- 2n backslashes followed by a quotation mark again produce n backslashes
        -- followed by a begin/end quote. This does not become part of the parsed
        -- argument but toggles the "in quotes" mode.
        --
        --   c:\foo\  -> "c:\foo\"    // WRONG
        --   c:\foo\  -> "c:\foo\\"   // RIGHT
        --   c:\foo\\ -> "c:\foo\\"   // WRONG
        --   c:\foo\\ -> "c:\foo\\\\" // RIGHT
        --
        -- To produce equal number of backslashes without converting the ending quote
        -- to a quote literal, double the backslashes (2n), **always even** number
        x = string.rep([[\]], #x * 2)
        return x
      end)
      return [["]] .. s .. [["]]
    else
      --
      -- CMD.exe caret+backslash escape, after lot of trial and error
      -- this seems to be the winning logic, a combination of v1 above
      -- and caret escaping special chars
      --
      -- The logic is as follows
      --   (1) all escaped quotes end up the same \^"
      --   (1) if quote was prepended with backslash or backslash+caret
      --       the resulting number of backslashes will be 2n + 1
      --   (2) if caret exists between the backslash/quote combo, move it
      --       before the backslash(s)
      --   (4) all cmd special chars are escaped with ^
      --
      --   NOTE: explore "tests/libuv_spec.lua" to see examples of quoted
      --      combinations and their expecetd results
      --
      local escape_inner = function(inner)
        inner = inner:gsub([[\-%^?"]], function(x)
          -- although we currently only transfer 1 caret, the below
          -- can handle any number of carets with the regex [[\-%^-"]]
          local carets = x:match("%^+") or ""
          x = carets .. string.rep([[\]], #x - #(carets)) .. x:gsub("%^+", "")
          return x
        end)
        -- escape all windows metacharacters but quotes
        -- ( ) % ! ^ < > & | ; "
        -- TODO: should % be escaped with ^ or %?
        inner = inner:gsub('[%(%)%%!%^<>&|;%s"]', function(x)
          return "^" .. x
        end)
        -- escape backslashes at the end of the string
        inner = inner:gsub([[\+$]], function(x)
          x = string.rep([[\]], #x * 2)
          return x
        end)
        return inner
      end
      s = escape_inner(s)
      if s:match("!") and tonumber(win_style) == 2 then
        --
        -- https://ss64.com/nt/syntax-esc.html
        -- This changes slightly if you are running with DelayedExpansion of variables:
        -- if any part of the command line includes an '!' then CMD will escape a second
        -- time, so ^^^^ will become ^
        --
        -- NOTE: we only do this on demand (currently only used in "libuv_spec.lua")
        --
        s = escape_inner(s)
      end
      s = [[^"]] .. s .. [[^"]]
      return s
    end
  end
  local shell = vim.o.shell
  if not shell or not shell:match("fish$") then
    return vim.fn.shellescape(s)
  else
    local ret = nil
    vim.o.shell = "sh"
    if s and not s:match([["]]) and not s:match([[\]]) then
      -- if the original string does not contain double quotes,
      -- replace surrounding single quote with double quotes,
      -- temporarily replace all single quotes with double
      -- quotes and restore after the call to shellescape.
      -- NOTE: we use '({s:gsub(...)})[1]' to extract the
      -- modified string without the multival # of changes,
      -- otherwise the number will be sent to shellescape
      -- as {special}, triggering an escape for ! % and #
      ret = vim.fn.shellescape(({ s:gsub([[']], [["]]) })[1])
      ret = [["]] .. ret:gsub([["]], [[']]):sub(2, #ret - 1) .. [["]]
    else
      ret = vim.fn.shellescape(s)
    end
    vim.o.shell = shell
    return ret
  end
end

-- Windows fzf oddities, fzf's {q} will send escaped blackslahes,
-- but only when the backslash prefixes another character which
-- isn't a backslash, test with:
-- fzf --disabled --height 30% --preview-window up --preview "echo {q}"
M.unescape_fzf = function(s, fzf_version, is_win)
  if is_win == nil then is_win = _is_win end
  if not is_win then return s end
  if tonumber(fzf_version) and tonumber(fzf_version) >= 0.52 then return s end
  local ret = s:gsub("\\+[^\\]", function(x)
    local bslash_num = #x:match([[\+]])
    return string.rep([[\]],
      bslash_num == 1 and bslash_num or math.floor(bslash_num / 2)) .. x:sub(-1)
  end)
  return ret
end

-- with live_grep, we use a modified "reload" command as our
-- FZF_DEFAULT_COMMAND and due to the above oddity with fzf
-- doing weird extra escaping with {q},  we use this to simulate
-- {q} being sent via the reload action as the initial command
-- TODO: better solution for these stupid hacks (upstream issues?)
M.escape_fzf = function(s, fzf_version, is_win)
  if is_win == nil then is_win = _is_win end
  if not is_win then return s end
  if tonumber(fzf_version) and tonumber(fzf_version) >= 0.52 then return s end
  local ret = s:gsub("\\+[^\\]", function(x)
    local bslash_num = #x:match([[\+]])
    return string.rep([[\]], bslash_num * 2) .. x:sub(-1)
  end)
  return ret
end

-- `vim.fn.escape`
-- (1) On *NIX: double the backslashes as they will be reduced by expand
-- (2) ... other issues we will surely find with special chars
M.expand = function(s)
  if not _is_win then
    s = s:gsub([[\]], [[\\]])
  end
  return vim.fn.expand(s)
end

return M
