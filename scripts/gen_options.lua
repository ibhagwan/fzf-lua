-- Run with: nvim -l scripts/gen_options.lua
-- Generates OPTIONS.md from EmmyLua annotations in the codebase

--- types from https://github.com/lewis6991/gitsigns.nvim/blob/42d6aed4e94e0f0bbced16bbdcc42f57673bd75e/gen_help.lua#L41
--- @alias EmmyDocLoc { file: string, line: integer }
--- @alias EmmyDocParam { name: string, typ: string, desc: string? }
--- @alias EmmyDocReturn { name: string?, typ: string, desc: string? }
--- @alias EmmyDocModule { name: string, members: EmmyDocFn[] }

--- @class EmmyDocFn: EmmyDocTypeField
--- @field type 'fn'
--- @field name string
--- @field description string?
--- @field deprecated boolean
--- @field deprecation_reason string?
--- @field loc EmmyDocLoc
--- @field params EmmyDocParam[]
--- @field returns EmmyDocReturn[]

--- @class EmmyDocTypeField
--- @field type 'field'
--- @field name string
--- @field description string?
--- @field typ string

--- @alias EmmyDocTypeMember EmmyDocTypeField | EmmyDocFn

--- @class EmmyDocTypeClass: EmmyDocTypeField
--- @field type 'class'
--- @field name string
--- @field bases string[]?
--- @field members EmmyDocTypeMember[]

--- @class EmmyDocTypeAlias: EmmyDocTypeField
--- @field type 'alias'
--- @field name string
--- @field members EmmyDocTypeMember[]

--- @alias EmmyDocType EmmyDocTypeClass | EmmyDocTypeAlias | EmmyDocTypeField

--- @class EmmyDocJson
--- @field modules EmmyDocModule[]
--- @field types EmmyDocType[]?

local obj = vim.system({ "sh", "-c", [[
  emmylua_doc_cli lua/fzf-lua/ --output-format json --output stdout
]] }):wait()

vim.opt.rtp:append(vim.fn.fnamemodify(assert(debug.getinfo(1, "S")).source:gsub("^@", ""), ":h:h:h:p"))
local defaults = require("fzf-lua.defaults").defaults

local res = vim.json.decode(obj.stdout or "") ---@type EmmyDocJson

local tymap = {} ---@type table<string, EmmyDocType?>
vim.iter(assert(res.types)):each(function(ty) tymap[ty.name] = ty end)

---@param typ string
---@param default? string
---@return string, string?
local function fix_typ(typ, default)
  if typ == "fzf-lua.profile" then
    if tymap[typ] and tymap[typ].name then
      return fix_typ(tymap[typ].typ, default)
    end
  end
  -- First, remove trailing ? (optional marker)
  typ = typ:gsub("%?$", "")
  -- Clean up fzf-lua config prefix
  typ = typ:gsub("fzf%-lua%.config%.", "")
  -- Remove outer parentheses from union types for cleaner display
  if typ:match("^%(.*%)$") then
    local ty = typ:sub(2, -2)
    local is = vim.iter(vim.split(ty, ",")):all(function(t)
      return t:match([[".-"]])
    end)
    if is then
      return "string[]", typ
    end
    typ = ty
  end
  -- Clean up complex types for readability (remove function signatures)
  if typ:match("|fun") then
    typ = typ:gsub("|%(fun%([^)]*%)[^)]*%)", "")
  end
  return typ, default
end

local normalize_classname = function(classname)
  return classname:gsub("^fzf%-lua%.config%.", ""):gsub("(%l)(%u)", "%1_%2"):lower()
end

local literal = function(v)
  if v == nil then
    return "nil"
  end
  if type(v) ~= "function" then
    local str = vim.inspect(v, { newline = " ", indent = "" })
    -- Truncate very long defaults
    if #str > 60 then
      str = str:sub(1, 57) .. "..."
    end
    return str
  end
  return nil -- Don't show function defaults
end

local alias = {
  __HLS = "hls",
}

-- Fields to exclude from Global Options (setup-only)
local EXCLUDE_FROM_GLOBALS = {
  nbsp = true, -- documented in Setup Options
}

-- Options that are global (not picker-specific) and should be processed
-- from Defaults type with recursion (skipped from Base type processing)
local globals_include = {
  winopts = true,
  keymap = true,
  actions = true,
  hls = true,
}

-- Static header content for OPTIONS.md
local STATIC_HEADER = [[
> [!NOTE]
> **This document should not be modified directly as it's automatically generated from emmylua
> comments and annotations and updated as part of the vimdoc CI, for manual regeneration run
> `nvim -l scripts/gen_options.lua`**

---

# Fzf-Lua Commands and Options

- [General Usage](#general-usage)
- [Setup Options](#setup-options)
- [Global Options](#global-options)
- [Pickers](#pickers)

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

It is not recommended to modify this value as this can have unintended consequences when entries contain the character designated as `nbsp`, but if your terminal/font does not support `EN_SPACE` you can use `NBSP` (U+00A0) instead:
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

If set to an `object`, fzf-lua expects a previewer class that will be initialized with `object:new(...)`, see the advanced Wiki "Neovim builtin previewer" section for more info.

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

#### setup.ui_select

Type: `boolean|table|function`, Default: `false`

Register fzf-lua as the UI interface for `vim.ui.select` during `setup`.

When set to a table or function, the value is passed to `register_ui_select`.

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

]]

-- Track which options we've already output
local done = {}

local function make_desc(member)
  if type(member.description) == "string" then
    return member.description
  end
  return nil
end

local function concat(x, sep)
  local function flatten(y)
    local ret = {}
    for _, v in ipairs(y) do
      if type(v) == "table" then
        vim.list_extend(ret, flatten(v))
      elseif type(v) == "string" then
        ret[#ret + 1] = v
      end
    end
    return ret
  end
  if not x then return "" end
  return table.concat(flatten(x), sep or "\n") .. "\n"
end

-- Sort members alphabetically by name
local function sort_members(members)
  local sorted = vim.deepcopy(members)
  table.sort(sorted, function(a, b)
    return (a.name or "") < (b.name or "")
  end)
  return sorted
end

local function _member_to_markdown(classname, member, rec, header_level, require_desc)
  header_level = header_level or "####"
  local name = alias[member.name] or member.name or "Unknown"
  local original_typ = member.typ
      or (member.returns and member.returns[1] and member.returns[1].typ)
      or "Unknown"
  local typ = original_typ
  local norm = ("%s.%s"):format(normalize_classname(classname), name)
  -- Build path for default lookup, handling aliases
  local path_parts = vim.split(norm, "%.")
  -- Skip "globals" prefix for default lookup
  local lookup_parts = vim.list_slice(path_parts, 2)
  -- Handle __HLS alias
  if lookup_parts[1] == "hls" then lookup_parts[1] = "__HLS" end
  local default_val = vim.tbl_get(defaults, unpack(lookup_parts))
  local default = type(member.literal) == "string" and member.literal or literal(default_val)
  typ, default = fix_typ(typ, default)
  if done[norm] or name:match("^_") or name == "[string]" then return end
  done[norm] = true
  local subclass = tymap[original_typ] or (original_typ and tymap[original_typ:match("(.-)%?")])
  if rec and subclass and subclass.members and #subclass.members > 0 then
    local ordered_members = sort_members(subclass.members)
    local results = {}
    for _, sub_member in ipairs(ordered_members) do
      local result = _member_to_markdown(norm, sub_member, rec + 1, header_level, require_desc)
      if result then
        table.insert(results, result)
      end
    end
    return results
  end
  local desc = make_desc(member)
  -- Skip options without descriptions if require_desc is set
  if require_desc and not desc then
    return nil
  end
  local out = {}
  out[#out + 1] = ("%s %s"):format(header_level, norm)
  out[#out + 1] = ""
  out[#out + 1] = ("Type: `%s`, Default: `%s`"):format(typ, default or "nil")
  out[#out + 1] = ""
  if type(desc) == "string" then
    out[#out + 1] = desc
    out[#out + 1] = ""
  end
  return out
end

local function member_to_markdown(...)
  return concat(_member_to_markdown(...))
end

-- Generate global options section - starting with Base type options
-- Only include options that have descriptions (curated documentation)
local function generate_globals()
  local output = {}

  -- First, add Base type globals (cwd, query, prompt, header, etc.)
  -- Skip fields that are in globals_include (they'll be processed from Defaults with recursion)
  local base_ty = tymap["fzf-lua.config.Base"]
  if base_ty and base_ty.members then
    local sorted_members = sort_members(base_ty.members)
    for _, member in ipairs(sorted_members) do
      if not globals_include[member.name] then
        table.insert(output, member_to_markdown("globals", member, nil, "####", true))
      end
    end
  end

  -- Then add Defaults type options
  local ty = assert(tymap["fzf-lua.config.Defaults"], "fzf-lua.config.Defaults type not found")
  vim.iter(ty.members)
      :each(function(member)
        -- Skip excluded fields
        if EXCLUDE_FROM_GLOBALS[member.name] then
          return
        end
        if (member.name:match("^_")
              and not member.name:match("__HLS"))
            or ((defaults[normalize_classname(member.typ:match("fzf%-lua%.config%.(.*)") or "")]
                or defaults[normalize_classname(member.typ:match("fzf%-lua%.config%.(.-)Base") or "")])
              and not globals_include[normalize_classname(member.typ:match("fzf%-lua%.config%.(.*)") or "")])
        then
          return
        end
        table.insert(output, member_to_markdown("globals", member, 1, "####", true))
      end)
  return table.concat(output, "")
end

-- Fields to exclude from picker documentation (internal implementation details)
local PICKER_EXCLUDE_FIELDS = {
  -- Inherited base fields documented elsewhere
  previewer = true,
  file_icons = true,
  color_icons = true,
  git_icons = true,
  multiprocess = true,
  fn_transform = true,
  fn_preprocess = true,
  -- fzf configuration
  fzf_opts = true,
  fzf_colors = true,
  -- Internal fields
  winopts = true,
  actions = true,
  cmd = true, -- Usually internal command strings
  preview = true,
  preview_pager = true,
  -- Internal index fields
  line_field_index = true,
  field_index_expr = true,
  ctags_file = true,
}

-- Keys to skip when discovering pickers (not actual pickers, or internal)
local SKIP_KEYS = {
  nbsp = true,
  fzf_bin = true,
  fzf_opts = true,
  fzf_tmux_opts = true,
  previewers = true,
  formatters = true,
  file_icon_padding = true,
  dir_icon = true,
  __HLS = true,
  keymap = true,
  actions = true,
  winopts = true,
}

-- Classes that are containers, not actual pickers
-- These have sub-pickers but shouldn't appear in docs themselves
local CONTAINER_CLASSES = {
  ["fzf-lua.config.Git"] = true,
  ["fzf-lua.config.Dap"] = true,
  ["fzf-lua.config.Tmux"] = true,
  ["fzf-lua.config.Global"] = true, -- Multi-picker, not a standalone picker
}

-- Convert picker key to EmmyLua class name
-- e.g., "files" -> "fzf-lua.config.Files"
--       "git.files" -> "fzf-lua.config.GitFiles"
--       "lsp.code_actions" -> "fzf-lua.config.LspCodeActions"
local function key_to_classname(key)
  local parts = vim.split(key, "%.")
  local class_parts = {}
  for _, part in ipairs(parts) do
    -- Convert snake_case to PascalCase
    local pascal = part:gsub("_(.)", function(c) return c:upper() end)
    pascal = pascal:sub(1, 1):upper() .. pascal:sub(2)
    table.insert(class_parts, pascal)
  end
  return "fzf-lua.config." .. table.concat(class_parts, "")
end

-- Recursively collect picker keys from defaults table
local function collect_picker_keys(tbl, prefix)
  prefix = prefix or ""
  local keys = {}
  for k, v in pairs(tbl) do
    -- Skip numeric keys (array elements)
    if type(k) ~= "string" then
      goto continue
    end
    local full_key = prefix ~= "" and (prefix .. "." .. k) or k
    if SKIP_KEYS[k] or k:match("^_") then
      -- Skip internal keys
    elseif type(v) == "table" then
      -- Check if this table has a corresponding class (i.e., it's a picker)
      local class_name = key_to_classname(full_key)
      if tymap[class_name] and not CONTAINER_CLASSES[class_name] then
        -- It's a picker with its own class (not a container)
        table.insert(keys, full_key)
      end
      -- Always check for sub-pickers (containers have sub-pickers)
      local sub_keys = collect_picker_keys(v, full_key)
      if #sub_keys > 0 then
        vim.list_extend(keys, sub_keys)
      end
    end
    ::continue::
  end
  return keys
end

-- Generate picker documentation
local function generate_pickers()
  local output = {}
  table.insert(output, "---\n\n## Pickers\n\n")

  -- Collect all picker keys from defaults
  local picker_keys = collect_picker_keys(defaults)
  table.sort(picker_keys)

  for _, key in ipairs(picker_keys) do
    -- Get defaults value for this picker
    local path_parts = vim.split(key, "%.")
    local default_val = vim.tbl_get(defaults, unpack(path_parts))

    -- Picker header with underscore-to-hyphen conversion for display
    local display_name = key:gsub("%.", "_")
    table.insert(output, ("#### %s\n\n"):format(display_name))

    -- Get class type and description from EmmyLua annotations
    local class_name = key_to_classname(key)
    local ty = tymap[class_name]

    -- Use EmmyLua description if available and non-empty
    local desc = ty and ty.description
    -- Filter out empty or inheritance-only descriptions (e.g. ": fzf-lua.config.Base")
    if desc and desc ~= "" and not desc:match("^:%s*fzf%-lua%.config%.") then
      table.insert(output, desc .. "\n\n")
    end

    -- Generate field documentation for this picker's specific fields
    -- Only include fields that have explicit descriptions (curated documentation)
    if ty and ty.members then
      for _, member in ipairs(ty.members) do
        local field_desc = make_desc(member)
        -- Skip fields without descriptions - these are implementation details
        -- Also skip excluded fields, private fields, and picker config types
        -- Note: We don't filter inherited fields if they have a description,
        -- as this indicates intentional documentation override
        local member_typ = member.typ or ""
        local is_picker_config = member_typ:match("^fzf%-lua%.config%.%u")
        local is_excluded = PICKER_EXCLUDE_FIELDS[member.name]
        if field_desc
            and not member.name:match("^_")
            and not is_picker_config
            and not is_excluded
        then
          local field_typ, field_default = fix_typ(member.typ)
          -- Get default value from actual defaults table
          local actual_default = default_val and default_val[member.name]
          local default_str = literal(actual_default) or field_default or "nil"

          table.insert(output, ("##### %s.%s\n\n"):format(display_name, member.name))
          table.insert(output, ("Type: `%s`, Default: `%s`\n\n"):format(field_typ, default_str))
          table.insert(output, field_desc .. "\n\n")
        end
      end
    end
  end

  table.insert(output, "---\n\n<!--- vim: set nospell: -->\n")
  return table.concat(output, "")
end

-- Main function to generate OPTIONS.md
local function generate_options_md()
  local output = {}
  table.insert(output, STATIC_HEADER)
  table.insert(output, generate_globals())
  table.insert(output, generate_pickers())
  return table.concat(output, "")
end

-- Generate and write to OPTIONS.md
local content = generate_options_md()
local script_dir = vim.fn.fnamemodify(assert(debug.getinfo(1, "S")).source:gsub("^@", ""), ":h")
local options_path = script_dir .. "/../OPTIONS.md"
local f = io.open(options_path, "w")
if f then
  f:write(content)
  f:close()
  print("Generated OPTIONS.md successfully at: " .. options_path)
else
  print("Error: Could not write to OPTIONS.md")
  -- Fall back to printing to stdout
  print(content)
end
