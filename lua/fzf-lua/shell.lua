-- for testing, copied from:
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/lua/fzf/actions.lua
local uv = vim.loop
local path = require "fzf-lua.path"

local M = {}

local _counter = 0
local _registry = {}

function M.register_func(fn)
  _counter = _counter + 1
  _registry[_counter] = fn
  return _counter
end

function M.get_func(counter)
  return _registry[counter]
end

-- creates a new address to listen to messages from actions. This is important,
-- if the user is using a custom fixed $NVIM_LISTEN_ADDRESS. Different neovim
-- instances will then use the same path as the address and it causes a mess,
-- i.e. actions stop working on the old instance. So we create our own (random
-- path) RPC server for this instance if it hasn't been started already.
local action_server_address = nil

function M.raw_async_action(fn, fzf_field_expression)

  if not fzf_field_expression then
    fzf_field_expression = "{+}"
  end

  local receiving_function = function(pipe_path, ...)
    local pipe = uv.new_pipe(false)
    local args = {...}
    uv.pipe_connect(pipe, pipe_path, function(err)
      vim.schedule(function ()
        fn(pipe, unpack(args))
      end)
    end)
  end

  if not action_server_address then
    action_server_address = vim.fn.serverstart()
  end

  local id = M.register_func(receiving_function)

  -- this is for windows WSL and AppImage users, their nvim path isn't just
  -- 'nvim', it can be something else
  local nvim_command = vim.v.argv[1]

  local action_string = string.format("%s --headless --clean --cmd %s %s %s %s",
    vim.fn.shellescape(nvim_command),
    vim.fn.shellescape("luafile " .. path.join{vim.g.fzf_lua_directory, "shell_helper.lua"}),
    vim.fn.shellescape(action_server_address),
    id,
    fzf_field_expression)
  return action_string, id
end

function M.async_action(fn, fzf_field_expression)
  local action_string, id = M.raw_async_action(fn, fzf_field_expression)
  return vim.fn.shellescape(action_string), id
end

function M.raw_action(fn, fzf_field_expression)

  local receiving_function = function(pipe, ...)
    local ret = fn(...)

    local on_complete = function(err)
      -- We are NOT asserting, in case fzf closes the pipe before we can send
      -- the preview.
      -- assert(not err)
      uv.close(pipe)
    end

    if type(ret) == "string" then
      uv.write(pipe, ret, on_complete)
    elseif type(ret) == nil then
      on_complete()
    elseif type(ret) == "table" then
      if not vim.tbl_isempty(ret) then
        uv.write(pipe, vim.tbl_map(function(x) return x.."\n" end, ret), on_complete)
      else
        on_complete()
      end
    else
      uv.write(pipe, tostring(ret) .. "\n", on_complete)
    end
  end

  return M.raw_async_action(receiving_function, fzf_field_expression)
end

function M.action(fn, fzf_field_expression)
  local action_string, id = M.raw_action(fn, fzf_field_expression)
  return vim.fn.shellescape(action_string), id
end

-- set to 'true' to use 'nvim-fzf'
-- set to 'false' for debugging using the local version
if false then
  M.action = require("fzf.actions").action
  M.raw_action = require("fzf.actions").raw_action
  M.async_action = require("fzf.actions").async_action
  M.raw_async_action = require("fzf.actions").raw_async_action
end

return M
