#!/usr/bin/env -S nvim -l
-- Generate OPTIONS.md from EmmyLua annotations in defaults.lua
-- Run with: nvim -l scripts/gen_options.lua
--
-- This script parses EmmyLua type annotations using emmylua_doc_cli
-- and generates a comprehensive OPTIONS.md document.
--
-- The script preserves the static header/intro sections from the original
-- OPTIONS.md and only regenerates the dynamic options sections.

local script_path = debug.getinfo(1, "S").source:gsub("^@", "")
local root_dir = vim.fn.fnamemodify(script_path, ":h:h:p")
local options_file = root_dir .. "/OPTIONS.md"

-- Read original OPTIONS.md to preserve static content
local original_content = {}
local original_file = io.open(options_file, "r")
if original_file then
  for line in original_file:lines() do
    original_content[#original_content + 1] = line
  end
  original_file:close()
end

-- Find markers in original content
local function find_line(pattern, start_idx)
  start_idx = start_idx or 1
  for i = start_idx, #original_content do
    if original_content[i]:match(pattern) then
      return i
    end
  end
  return nil
end

-- Run emmylua_doc_cli
local obj = vim.system({ "sh", "-c", [[
  emmylua_doc_cli lua/fzf-lua/ --output-format json --output stdout
]] }):wait()

if obj.code ~= 0 then
  print("Error running emmylua_doc_cli: " .. (obj.stderr or "unknown error"))
  return
end

vim.opt.rtp:append(root_dir)
local defaults = require("fzf-lua.defaults").defaults

local res = vim.json.decode(obj.stdout or "{}")

-- Build type map
local tymap = {}
vim.iter(res.types or {}):each(function(ty)
  tymap[ty.name] = ty
end)

-- Get literal value from defaults table
local function get_default_value(path_parts)
  local val = defaults
  for _, part in ipairs(path_parts) do
    if type(val) ~= "table" then return nil end
    val = val[part]
  end
  if type(val) == "function" then
    local info = debug.getinfo(val)
    return string.format("<function:%d>", info.linedefined)
  end
  return val
end

-- Format value for display
local function format_value(v)
  if v == nil then return "nil" end
  if type(v) == "string" then return string.format("%s", v) end
  if type(v) == "boolean" or type(v) == "number" then return tostring(v) end
  if type(v) == "table" then
    local s = vim.inspect(v, { newline = "", indent = "" })
    if #s > 60 then s = s:sub(1, 57) .. "..." end
    return s
  end
  return tostring(v)
end

-- Fix type display
local function fix_typ(typ)
  if not typ then return "unknown" end
  typ = typ:gsub("%?$", "")
  typ = typ:gsub("^%((.+)%)$", "%1")
  return typ
end

-- Check if field is inherited from base class
local function is_field_inherit(ty, field_name)
  for _, base in ipairs(ty.bases or {}) do
    local base_ty = tymap[base]
    if base_ty then
      for _, f in ipairs(base_ty.members or {}) do
        if f.name == field_name then
          return true
        end
      end
      if is_field_inherit(base_ty, field_name) then
        return true
      end
    end
  end
  return false
end

-- Build output
local output = {}

local function add(...)
  for _, line in ipairs({ ... }) do
    output[#output + 1] = line
  end
end

local function add_option(prefix, name, typ, default, description)
  add("")
  add(string.format("#### %s.%s", prefix, name))
  add("")
  add(string.format("Type: `%s`, Default: `%s`", fix_typ(typ), format_value(default)))
  if description and type(description) == "string" and description ~= "" then
    add("")
    for line in description:gmatch("[^\n]+") do
      add(line)
    end
  end
end

-- Copy static header from original (everything up to first #### globals. option)
local global_opts_start = find_line("^## Global Options")
local first_option = find_line("^#### globals%.", global_opts_start)
local global_opts_intro_end = first_option and first_option - 1 or nil
-- Trim trailing empty lines
while global_opts_intro_end and global_opts_intro_end > 1 and original_content[global_opts_intro_end] == "" do
  global_opts_intro_end = global_opts_intro_end - 1
end

if global_opts_start and global_opts_intro_end then
  for i = 1, global_opts_intro_end do
    add(original_content[i])
  end
else
  -- Fallback: use hardcoded header
  add([[# NOTE: THIS DOCUMENT IS CURRENTLY WIP

**This document does not yet contain all of fzf-lua's options, there are a lot of esoteric and
undocumented options which can be found in issues/discussions which I will slowly but surely
add to this document.**

---

# Fzf-Lua Commands and Options

- [General Usage](#general-usage)
- [Setup Options](#setup-options)
- [Global Options](#global-options)
- [Pickers](#pickers)
  + [Buffers and Files](#buffers-and-files)
  + [Search](#search)
  + [CTags](#ctags)
  + [Git](#git)
  + [LSP | Diagnostics](#lspdiagnostics)
  + [Misc](#misc)
  + [Neovim API](#neovim-api)
  + [`nvim-dap`](#nvim-dap)
  + [`tmux`](#tmux)
  + [Completion Functions](#completion-functions)

---

## General Usage

Options in fzf-lua can be specified in a few different ways:
- Global setup options
- Provider-defaults setup options
- Provider-specific setup options
- Command call options

Most of fzf-lua's options are applicable in all of the above, a few examples below:

Global setup, applies to all fzf-lua interfaces:
```lua
-- Places the floating window at the bottom left corner
require("fzf-lua").setup({ winopts = { row = 1, col = 0 } })
```

Disable `file_icons` globally (files, grep, etc) via provider defaults setup options:
```lua
require("fzf-lua").setup({ defaults = { file_icons = false } })
```

Disable `file_icons` in `files` only via provider specific setup options:
```lua
require("fzf-lua").setup({ files = { file_icons = false } })
```

Disable `file_icons` in `files`, applies to this call only:
```lua
:lua require("fzf-lua").files({ file_icons = false  })
-- Or
:FzfLua files file_icons=false
```

Fzf-lua conveniently enables setting lua tables recursively using dotted keys, for example, if we
wanted to call `files` in "split" mode (instead of the default floating window), we would normally call:

```lua
:lua require("fzf-lua").files({ winopts = { split = "belowright new" } })
```

But we can also use the dotted key format (unique to fzf-lua):
```lua
:lua require("fzf-lua").files({ ["winopts.split"] = "belowright new" })
```

This makes it possible to send nested lua values via the `:FzfLua` user command:
```lua
-- Escape spaces with \
:FzfLua files winopts.split=belowright\ new
```

Lua string serialization is also possible:
```lua
-- Places the floating window at the top left corner
:FzfLua files winopts={row=0,col=0}
```

---

## Setup Options

Most of fzf-lua's options are global, meaning they can be specified in any of the different ways
explained in [General Usage](#general-usage) and are described in detail in the [Global Options](#global-options) section below.

There are however a few options that can be specified only during the call to `setup`, these are
described below.

#### setup.nbsp

Type: `string`, Default: `nil`

Fzf-lua uses a special invisible unicode character `EN SPACE` (U+2002) as text delimiter.

It is not recommended to modify this value as this can have uninteded consequnces when entries contain the character designated as `nbsp`, but if your terminal/font does not support `EN_SPACE` you can use `NBSP` (U+00A0) instead:
```lua
require("fzf-lua").setup({ nbsp = "\xc2\xa0" })
```

#### setup.winopts.preview.default

Type: `string|function|object`, Default: `builtin`

Default previewer for file pickers, possible values `builtin|bat|cat|head`, for example:

```lua
require("fzf-lua").setup({ winopts = { preview = { default = "bat" } } })
```

If set to a `function` the return value will be used (`string|object`).

If set to an `object`, fzf-lua expects a previewer class that will be initlaized with `object:new(...)`, see the advanced Wiki "Neovim builtin previewer" section for more info.

#### setup.help_open_win

Type: `fun(number, boolean, table)`,  Default: `vim.api.nvim_open_win`

Function override for opening the help window (default bound to `<F1>`), will be called with the same arguments as `nvim_open_win(bufnr, enter, winopts)`. By default opens a floating window at the bottom of current screen.

Override this function if you want to customize window configs of the help window (location, width, border, etc.).

Example, opening a floating help window at the top of screen with single border:
```lua
    require("fzf-lua").setup({
      help_open_win = function(buf, enter, opts)
        opts.border = 'single'
        opts.row = 0
        opts.col = 0
        return vim.api.nvim_open_win(buf, enter, opts)
      end,
    })
```

---

## Global Options

Globals are options that aren't picker-specific and can be used with all fzf-lua commands, for
example, positioning the floating window at the bottom line using `globals.winopts.row`:

> The `globals` prefix denotates the scope of the option and is therefore omitted 

Using `FzfLua` user command:
```lua
:FzfLua files winopts.row=1
```

Using Lua:
```lua
:lua require("fzf-lua").files({ winopts = { row = 1 } })
-- Using the recursive option format
:lua require("fzf-lua").files({ ["winopts.row"] = 1 })
```
]])
end

-- Generate globals from Base class (cwd, query, prompt, etc)
local base_ty = tymap["fzf-lua.config.Base"]
if base_ty and base_ty.members then
  for _, member in ipairs(base_ty.members) do
    local name = member.name
    if name:match("^_") then goto continue end
    -- Only include documented global options
    local globals_list = {
      "cwd", "query", "prompt", "header", "previewer",
      "formatter", "file_icons", "git_icons", "color_icons"
    }
    local is_global = vim.tbl_contains(globals_list, name)
    if is_global and member.description and type(member.description) == "string" then
      local default_val = get_default_value({ name })
      add_option("globals", name, member.typ, default_val, member.description)
    end
    ::continue::
  end
end

-- Generate winopts section
add("")
add("#### globals.winopts.split")
add("")
add("Type: `string`, Default: `nil`")
add("")
add("Neovim split command to use for fzf-lua interface, e.g `belowright new`.")

local winopts_ty = tymap["fzf-lua.config.Winopts"]
if winopts_ty and winopts_ty.members then
  for _, member in ipairs(winopts_ty.members) do
    local name = member.name
    if name:match("^_") then goto continue end
    -- Skip preview (handled separately) and split (hardcoded above)
    if name == "preview" or name == "split" then goto continue end

    local default_val = get_default_value({ "winopts", name })
    if member.description and type(member.description) == "string" then
      add_option("globals.winopts", name, member.typ, default_val, member.description)
    end
    ::continue::
  end
end

-- Generate winopts.preview section
local preview_ty = tymap["fzf-lua.config.PreviewOpts"]
if preview_ty and preview_ty.members then
  for _, member in ipairs(preview_ty.members) do
    local name = member.name
    if name:match("^_") then goto continue end
    if name == "winopts" or name == "default" then goto continue end

    local default_val = get_default_value({ "winopts", "preview", name })
    if member.description and type(member.description) == "string" then
      add_option("globals.winopts.preview", name, member.typ, default_val, member.description)
    end
    ::continue::
  end
end

-- Generate winopts.preview.winopts section
local previewer_winopts_ty = tymap["fzf-lua.config.PreviewerWinopts"]
if previewer_winopts_ty and previewer_winopts_ty.members then
  for _, member in ipairs(previewer_winopts_ty.members) do
    local name = member.name
    if name:match("^_") then goto continue end

    local default_val = get_default_value({ "winopts", "preview", "winopts", name })
    if member.description and type(member.description) == "string" then
      add_option("globals.winopts.preview.winopts", name, member.typ, default_val, member.description)
    end
    ::continue::
  end
end

-- Generate hls section
local hls_ty = tymap["fzf-lua.config.HLS"]
if hls_ty and hls_ty.members then
  for _, member in ipairs(hls_ty.members) do
    local name = member.name
    if name:match("^_") then goto continue end

    if name == "fzf" then
      -- Handle nested fzf hls
      local fzf_hls_ty = tymap["fzf-lua.config.fzfHLS"]
      if fzf_hls_ty and fzf_hls_ty.members then
        for _, fzf_member in ipairs(fzf_hls_ty.members) do
          local fzf_name = fzf_member.name
          if fzf_name:match("^_") then goto fzf_continue end
          local default_val = get_default_value({ "__HLS", "fzf", fzf_name })
          if fzf_member.description and type(fzf_member.description) == "string" then
            add_option("globals.hls.fzf", fzf_name, fzf_member.typ, default_val, fzf_member.description)
          end
          ::fzf_continue::
        end
      end
    else
      local default_val = get_default_value({ "__HLS", name })
      if member.description and type(member.description) == "string" then
        add_option("globals.hls", name, member.typ, default_val, member.description)
      end
    end
    ::continue::
  end
end

-- Copy remaining static content (Pickers section onwards)
local pickers_start = find_line("^## Pickers")
if pickers_start then
  add("")
  add("---")
  add("")
  for i = pickers_start, #original_content do
    add(original_content[i])
  end
end

-- Write the output
local file = io.open(options_file, "w")
if file then
  file:write(table.concat(output, "\n"))
  file:close()
  print("Generated " .. options_file)
else
  print("Error: Could not open " .. options_file .. " for writing")
end
