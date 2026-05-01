-- lua version of shellwords https://github.com/junegunn/fzf/blob/f7835825617bd38eb50349bd89fa2f39569c3068/src/options.go#L3854-L3857
local M = {}

local function isSpace(c)
  return c == " " or c == "\t" or c == "\r" or c == "\n"
end

local argNo = 0
local argSingle = 1
local argQuoted = 2

--- Parses a shell string into arguments similar to Go's shellwords.
--- @param line string
--- @return string[]? args
--- @return string? err
M.shellparse = function(line)
  if not line or type(line) ~= "string" then
    return {}
  end

  local args = {}
  local buf = ""
  local escaped, doubleQuoted, singleQuoted, backQuote, dollarQuote, comment =
      false, false, false, false, false, false

  local got = argNo

  local i = 1
  while i <= #line do
    local r = line:sub(i, i)
    local continue = false

    if comment then
      if r == "\n" then
        comment = false
      end
      continue = true
    end

    if not continue and escaped then
      if r == "t" then r = "\t" end
      if r == "n" then r = "\n" end
      buf = buf .. r
      escaped = false
      got = argSingle
      continue = true
    end

    if not continue and r == "\\" then
      if singleQuoted then
        buf = buf .. r
      else
        escaped = true
      end
      continue = true
    end

    if not continue and isSpace(r) then
      if singleQuoted or doubleQuoted or backQuote or dollarQuote then
        buf = buf .. r
      elseif got ~= argNo then
        args[#args + 1] = buf
        buf = ""
        got = argNo
      end
      continue = true
    end

    if not continue then
      if r == "`" then
        if not singleQuoted and not doubleQuoted and not dollarQuote then
          backQuote = not backQuote
        end
      elseif r == ")" then
        if not singleQuoted and not doubleQuoted and not backQuote then
          dollarQuote = not dollarQuote
        end
      elseif r == "(" then
        if not singleQuoted and not doubleQuoted and not backQuote then
          if not dollarQuote and buf:sub(-1) == "$" then
            dollarQuote = true
            buf = buf .. "("
            continue = true
          else
            return nil, "invalid command line string"
          end
        end
      elseif r == '"' then
        if not singleQuoted and not dollarQuote then
          if doubleQuoted then got = argQuoted end
          doubleQuoted = not doubleQuoted
          continue = true
        end
      elseif r == "'" then
        if not doubleQuoted and not dollarQuote then
          if singleQuoted then got = argQuoted end
          singleQuoted = not singleQuoted
          continue = true
        end
      elseif r == ";" or r == "&" or r == "|" or r == "<" or r == ">" then
        if not (escaped or singleQuoted or doubleQuoted or backQuote or dollarQuote) then
          if r == ">" and #buf > 0 then
            local c = buf:sub(1, 1)
            if c >= "0" and c <= "9" then
              got = argNo
            end
          end
          break
        end
      elseif r == "#" then
        -- ParseComment is true
        if #buf == 0 and not (escaped or singleQuoted or doubleQuoted) then
          comment = true
          continue = true
        end
      end
    end

    if not continue then
      got = argSingle
      buf = buf .. r
    end

    i = i + 1
  end

  if got ~= argNo then
    args[#args + 1] = buf
  end

  if escaped or singleQuoted or doubleQuoted or backQuote or dollarQuote then
    return nil, "invalid command line string"
  end

  return args
end

---@alias fzf-lua.FzfOpts { [string]: string }
---@param line string
---@return fzf-lua.FzfOpts
M.parse = function(line)
  local words = M.shellparse(line)
  if not words then return {} end
  local args = {}
  -- https://github.com/junegunn/fzf/blob/f7835825617bd38eb50349bd89fa2f39569c3068/src/options.go#L2618-L2622
  local i = 1
  while i <= #words do
    local word = words[i] ---@as string
    if word:sub(1, 2) == "--" then
      local field, value = word:match("^(.-)=(.*)$")
      if field then
        args[field] = value
      else -- space-separated: --key value (next token doesn't start with '-')
        local nxt = words[i + 1]
        if nxt and nxt:sub(1, 1) ~= "-" then
          args[word] = nxt
          i = i + 1
        else
          args[word] = true -- bare flag
        end
      end
    end
    i = i + 1
  end
  return args
end


local parsed ---@type fzf-lua.FzfOpts?
---@return fzf-lua.FzfOpts
M.get = function()
  if parsed then return parsed end
  local default_opts = os.getenv("FZF_DEFAULT_OPTS")
  local file = os.getenv("FZF_DEFAULT_OPTS_FILE")
  local content = file and require("fzf-lua.utils").read_file(file) or nil
  local opts1 = default_opts and M.parse(default_opts) or {}
  local opts2 = content and M.parse(content) or {}
  parsed = vim.tbl_deep_extend("keep", opts1, opts2)
  return parsed
end

return M
