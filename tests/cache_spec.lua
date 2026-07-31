local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local fzf = require("fzf-lua")
local LRU = fzf.shell.LRU

describe("Testing cache module", function()
  ---@type fzf-lua.lru
  local cache
  local cached_fun = function(id) return function() return "CACHED" .. tostring(id) end end

  -- The cases of this spec share one LRU instance through the `cache`
  -- upvalue and each builds on the state left by the previous one. Replaying
  -- the prefix of state-building operations keeps every case self-contained
  -- so cases stay correct when distributed across parallel workers.
  local build = function(n_steps)
    cache = LRU:new(50)
    local set_anon = function() cache:set(function() end) end
    local steps = {
      function() cache:set(cached_fun(1)) end, -- "first"
      function() for _ = 1, 12 do set_anon() end end, -- "half store bubble"
      function() cache:set(cached_fun(14)) end, -- "half store bubble"
      function() for _ = 1, 11 do set_anon() end end, -- "half store bubble"
      function() cache:get(14) end, -- bubble, end of "half store bubble"
      function() for _ = 1, 25 do set_anon() end end, -- "full store"
      function() cache:get(14) end, -- bubble, "full store bubble"
      function() cache:get(1) end, -- bubble, "full store bubble"
      function() cache:set(cached_fun(51)) end, -- "eviction"
      function() cache:get(14) end, -- bubble, "yet another bubble"
    }
    for i = 1, n_steps do steps[i]() end
  end

  it("new", function()
    local size = 50
    cache = LRU:new(size)
    assert.is.same(cache.max_size, size)
  end)

  it("first", function()
    build(0)
    local id = cache:set(cached_fun(1))
    assert.is.same(id, 1)
    assert.is.same(cache:get(1)(), "CACHED1")
  end)

  it("half store bubble", function()
    build(1)
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
    build(5)
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
    build(6)
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
    build(8)
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
    build(9)
    assert.is.same(cache:get(14)(), "CACHED14")
    assert.is.same(cache:len(), #cache.mru)
    assert.is.same(cache.mru[1], 14)
    assert.is.same(cache.mru[2], 51)
    assert.is.same(cache.mru[3], 1)
    assert.is.same(cache.mru[50], 3)
  end)

  it("size set: err", function()
    build(10)
    local ok, err = pcall(cache.set_size, cache, 10)
    assert.is.False(ok)
    ---@diagnostic disable-next-line: param-type-mismatch, need-check-nil
    assert.is.True(err and err:match("cannot be smaller than current length") ~= nil)
  end)

  it("size set: ok", function()
    build(10)
    cache:set_size(50) -- should not err, same size
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
