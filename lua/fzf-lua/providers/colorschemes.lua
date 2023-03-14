local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local function get_current_colorscheme()
  if vim.g.colors_name then
    return vim.g.colors_name
  else
    return "default"
  end
end

local M = {}

M.colorschemes = function(opts)
  opts = config.normalize_opts(opts, config.globals.colorschemes)
  if not opts then return end


  local current_colorscheme = get_current_colorscheme()
  local current_background = vim.o.background
  local colors = opts.colors or vim.fn.getcompletion("", "color")

  opts.fzf_opts["--no-multi"] = ""

  if opts.live_preview then
    -- must add ':nohidden' or fzf ignores the preview action
    opts.fzf_opts["--preview-window"] = "nohidden:right:0"
    opts.preview = shell.raw_action(function(args)
      if opts.live_preview and args then
        local colorscheme = args[1]
        vim.cmd("colorscheme " .. colorscheme)
      end
    end, nil, opts.debug)
  end

  opts.fn_selected = function(selected)
    -- reset color scheme if live_preview is enabled
    -- and nothing or non-default action was selected
    if opts.live_preview and (not selected or #selected[1] > 0) then
      vim.o.background = current_background
      vim.cmd("colorscheme " .. current_colorscheme)
      vim.o.background = current_background
    end

    if selected then
      actions.act(opts.actions, selected)
    end

    if opts.post_reset_cb then
      opts.post_reset_cb()
    end
  end

  core.fzf_exec(colors, opts)
end

M.highlights = function(opts)
  opts = config.normalize_opts(opts, config.globals.highlights)
  if not opts then return end

  local contents = function(cb)
    local colormap = vim.api.nvim_get_color_map()
    local highlights = vim.fn.getcompletion("", "highlight")

    local function add_entry(hl, co)
      -- translate the highlight using ansi escape sequences
      local x = utils.ansi_from_hl(hl, hl, colormap)
      cb(x, function(err)
        if co then coroutine.resume(co) end
        if err then
          -- error, close fzf pipe
          cb(nil)
        end
      end)
      if co then coroutine.yield() end
    end

    local function populate(entries, fn, co)
      for _, e in ipairs(entries) do
        fn(e, co)
      end

      cb(nil, function()
        if co then coroutine.resume(co) end
      end)
    end

    local coroutinify = (opts.coroutinify == nil) and false or opts.coroutinify

    if not coroutinify then
      populate(highlights, add_entry)
    else
      coroutine.wrap(function()
        -- Unable to coroutinify, hl functions fail inside coroutines with:
        -- E5560: vimL function must not be called in a lua loop callback
        -- and using 'vim.schedule'
        -- attempt to yield across C-call boundary
        populate(highlights,
          function(x, co)
            vim.schedule(function()
              add_entry(x, co)
            end)
          end,
          coroutine.running())
        coroutine.yield()
      end)()
    end
  end

  opts.fzf_opts["--no-multi"] = ""

  core.fzf_exec(contents, opts)
end

return M
