local fzf = require("fzf-lua")
local utils = fzf.utils

describe("Testing utils module", function()
  it("separator", function()
    utils.__IS_WINDOWS = false
    assert.are.same(utils._if_win_normalize_vars("--w=$COLUMNS"), "--w=$COLUMNS")

    utils.__IS_WINDOWS = true
    assert.are.same(utils._if_win_normalize_vars("--w=$COLUMNS", 1), "--w=%COLUMNS%")
    assert.are.same(utils._if_win_normalize_vars("--w=%COLUMNS%", 1), "--w=%COLUMNS%")
    assert.are.same(utils._if_win_normalize_vars("-w=$C -l=$L", 1), "-w=%C% -l=%L%")
    assert.are.same(utils._if_win_normalize_vars("--w=$COLUMNS", 2), "--w=!COLUMNS!")
    assert.are.same(utils._if_win_normalize_vars("--w=%COLUMNS%", 2), "--w=!COLUMNS!")
    assert.are.same(utils._if_win_normalize_vars("-w=$C -l=$L", 2), "-w=!C! -l=!L!")
  end)
end)
