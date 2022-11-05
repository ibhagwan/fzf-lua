-- Modified from Telescope 'command.lua'
local builtin = require "fzf-lua"
local utils = require "fzf-lua.utils"
local command = {}

local arg_value = {
  ["nil"] = nil,
  ['""'] = "",
  ['"'] = "",
}

local bool_type = {
  ["false"] = false,
  ["true"] = true,
}

-- convert command line string arguments to
-- lua number boolean type and nil values
local function convert_user_opts(user_opts)
  local _switch = {
    ["boolean"] = function(key, val)
      if val == "false" then
        user_opts[key] = false
        return
      end
      user_opts[key] = true
    end,
    ["number"] = function(key, val)
      user_opts[key] = tonumber(val)
    end,
    ["string"] = function(key, val)
      if arg_value[val] ~= nil then
        user_opts[key] = arg_value[val]
        return
      end

      if bool_type[val] ~= nil then
        user_opts[key] = bool_type[val]
      end
    end,
  }

  local _switch_metatable = {
    __index = function(_, k)
      utils.info(string.format("Type of %s does not match", k))
    end,
  }

  setmetatable(_switch, _switch_metatable)

  for key, val in pairs(user_opts) do
    _switch["string"](key, val)
  end
end

-- receive the viml command args
-- it should output a table value like
-- {
--   cmd = 'files',
--   opts = {
--      cwd = '***',
-- }
local function run_command(args)
  local user_opts = args or {}
  if next(user_opts) == nil or not user_opts.cmd then
    utils.info("missing command args")
    return
  end

  local cmd = user_opts.cmd
  local opts = user_opts.opts or {}

  if next(opts) ~= nil then
    convert_user_opts(opts)
  end

  if builtin[cmd] then
    builtin[cmd](opts)
  else
    utils.info(string.format("invalid command '%s'", cmd))
  end
end

function command.load_command(cmd, ...)
  local args = { ... }
  if cmd == nil then
    run_command { cmd = "builtin" }
    return
  end

  local user_opts = {}
  user_opts["cmd"] = cmd
  user_opts.opts = {}

  for _, arg in ipairs(args) do
    local param = vim.split(arg, "=")
    user_opts.opts[param[1]] = param[2]
  end

  run_command(user_opts)
end

return command
