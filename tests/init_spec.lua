-- local fn = vim.fn
-- local api = vim.api

local fzf = require("fzf-lua")

describe("FzfLua", function()
  describe("configuration", function()
    it("initial setup", function()
      fzf.setup({})
      _G.dump(assert.is)
      assert.is.truthy(fzf)
    end)
  end)
end)
