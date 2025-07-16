local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local fzf = require("fzf-lua")
local LRU = fzf.shell.LRU

describe("Testing cache module", function()
  local cache
  local cached_fun = function(id) return function() return "CACHED" .. tostring(id) end end

  it("new", function()
    local size = 50
    cache = LRU:new(size)
    assert.is.same(cache.max_size, size)
  end)

  it("first", function()
    local id = cache:set(cached_fun(1))
    assert.is.same(id, 1)
    assert.is.same(cache:get(1)(), "CACHED1")
  end)

  it("half store bubble", function()
    for _ = 1, 12 do cache:set(function() end) end
    cache:set(cached_fun(14))
    for _ = 1, 11 do cache:set(function() end) end
    -- After inserting 25 elements the last element should be at the top
    -- so basically the MRU is sorted in reverse order
    assert.is.same(cache:len(), 25)
    for i = 1, 25 do
      assert.is.same(cache.mru[i], 25 - i + 1)
    end
    -- In reveerse order func14 is at [12] and fun1 is at [25]
    assert.is.same(cache:len(), #cache.mru)
    assert.is.same(cache.mru[12], 14)
    assert.is.same(cache.mru[25], 1)
    assert.is.same(cache:get(14)(), "CACHED14")
    assert.is.same(cache:len(), #cache.mru)
    -- After bubbling func14 should be moved to [1]
    -- and rest of the elements should be shifted
    assert.is.same(cache.mru[1], 14)
    assert.is.same(cache.mru[11], 16)
    assert.is.same(cache.mru[12], 15)
    assert.is.same(cache.mru[13], 13)
    assert.is.same(cache.mru[25], 1)
  end)

  it("full store", function()
    -- Fill in the remaining 25 items
    for _ = 1, 25 do cache:set(function() end) end
    assert.is.same(cache:len(), 50)
    -- New elements should take the first 25 slots
    -- No element should be evicted at this point
    for i = 1, 25 do
      local _, evicted_id = assert.is.same(cache.mru[i], 50 - i + 1)
      assert.is.same(evicted_id, nil)
    end
    -- Previous elements are shifted by 25
    assert.is.same(cache.mru[1 + 25], 14)
    assert.is.same(cache.mru[11 + 25], 16)
    assert.is.same(cache.mru[12 + 25], 15)
    assert.is.same(cache.mru[13 + 25], 13)
    assert.is.same(cache.mru[25 + 25], 1)
  end)

  it("full store bubble", function()
    -- Calling `:get()` bubbles the item in the MRU
    assert.is.same(cache:get(14)(), "CACHED14")
    assert.is.same(cache:len(), #cache.mru)
    assert.is.same(cache.mru[1], 14)
    assert.is.same(cache.mru[50], 1)
    -- After bubbling func1, func14 shifts downward
    assert.is.same(cache:get(1)(), "CACHED1")
    assert.is.same(cache:len(), #cache.mru)
    assert.is.same(cache.mru[1], 1)
    assert.is.same(cache.mru[2], 14)
    assert.is.same(cache.mru[50], 2)
  end)

  it("eviction", function()
    -- Store a new function, should have an incremental id
    -- func2 is evicted as it's at the bottom of the MRU
    local id, evicted_id = cache:set(cached_fun(51))
    assert.is.same(cache:len(), #cache.mru)
    assert.is.same(id, 51)
    assert.is.same(evicted_id, 2)
    -- func51 gets the top spot at the MRU
    assert.is.same(cache.mru[1], 51)
    assert.is.same(cache.mru[2], 1)
    assert.is.same(cache.mru[3], 14)
    assert.is.same(cache.mru[50], 3)
  end)

  it("yet another bubble", function()
    assert.is.same(cache:get(14)(), "CACHED14")
    assert.is.same(cache:len(), #cache.mru)
    assert.is.same(cache.mru[1], 14)
    assert.is.same(cache.mru[2], 51)
    assert.is.same(cache.mru[3], 1)
    assert.is.same(cache.mru[50], 3)
  end)

  it("size set: err", function()
    local ok, err = pcall(cache.set_size, cache, 10)
    assert.is.False(ok)
    assert.is.True(err:match("cannot be smaller than current length") ~= nil)
  end)

  it("size set: ok", function()
    cache:set_size(50)  -- should not err, same size
    cache:set_size(51)
    local id, evicted_id = cache:set(cached_fun(52))
    assert.is.same(id, 52)
    assert.is.same(evicted_id, nil)
    assert.is.same(cache.mru[1], 52)
    assert.is.same(cache.mru[2], 14)
    assert.is.same(cache.mru[3], 51)
    assert.is.same(cache.mru[4], 1)
    assert.is.same(cache.mru[51], 3)
  end)

end)
