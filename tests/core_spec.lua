-- TODO: We have a lot of missing tests, but will add more soon :)

local config = require("fzf-lua.config")
local core = require("fzf-lua.core")


describe("fzf-lua.core", function()
  describe("build_fzf_cli", function()
    it("should generate fzf flag with minimal opts", function()
      local opts = {}
      opts = config.normalize_opts(opts, {})

      local cli = core.build_fzf_cli(opts)
      _G.dump(cli)

      local expected = [[
        --border=none --height=100% --multi --preview-window=nohidden:border:nowrap:down:45% layout=reverse --ansi --info=inline
        --bind='ctrl-e:end-of-line,alt-a:toggle-all,f3:toggle-preview-wrap,f4:toggle-preview,shift-down:preview-page-down,ctrl-z:abort,ctrl-u:unix-line-discard,ctrl-f:half-page-down,ctrl-b:half-page-up,shift-up:preview-page-up,ctrl-a:beginning-of-line'
      ]]

      -- CLI can have a non-deterministic order
      local cli_t = vim.split(vim.trim(cli), ' ')
      local expected_t = vim.split(vim.trim(cli), ' ')
      table.sort(cli_t)
      table.sort(expected_t)
      assert.are.same(expected_t, cli_t)
    end)
    it("should handle --header flag properly, which requires a rhs", function()
      -- Note: `fzf --header --multi`  !=  `fzf --header='' --multi`

      ---@return string
      local function build(raw_opts)
        local opts = config.normalize_opts(raw_opts, { query = [[<'" "'>]] })
        local cli = core.build_fzf_cli(opts)
        print(raw_opts.fzf_opts["--header"], "=>", cli)
        return cli .. ' '
      end

      -- easy case
      assert.has.match("--header='foo' ", build({ fzf_opts = { ["--header"] = "foo" } }))
      -- falsy values should remove the flag
      assert.has_no.match("--header", build({ fzf_opts = { ["--header"] = nil } }))
      assert.has_no.match("--header ", build({ fzf_opts = { ["--header"] = false } }))
      -- empty header string (tricky)
      assert.has.match("--header='' ", build({ fzf_opts = { ["--header"] = '' } }))
      -- shellescape?
      assert.has.match("--header=''\\''' ", build({ fzf_opts = { ["--header"] = [[']] } }))
      assert.has.match("--header='\"' ", build({ fzf_opts = { ["--header"] = [["]] } }))

    end)
  end)
end)
