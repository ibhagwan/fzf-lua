local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert
local eq = assert.are.same

local undotree = require("fzf-lua.providers.undotree")
local utils = require("fzf-lua.utils")

local FROZEN_TIME = 1700000000

local function freeze_time()
  local orig = os.time
  _G.os.time = function() return FROZEN_TIME end
  return orig
end

local function setup_ansi_identity()
  local orig = {}
  for _, hl in ipairs({ "Directory", "Number", "Comment" }) do
    orig[hl] = utils.ansi_codes[hl]
    utils.ansi_codes[hl] = function(s) return s end
  end
  return orig
end

local function restore_ansi_identity(orig)
  for hl, fn in pairs(orig) do
    utils.ansi_codes[hl] = fn
  end
end

local opts = {
  hls = {
    dir_part = "Directory",
    buf_name = "Number",
    path_linenr = "Comment",
  },
}

local function collect_tree(tree, reverse)
  local rows = {}
  local cb = function(seq, line)
    table.insert(rows, { seq = seq, line = utils.strip_ansi_coloring(line) })
  end
  undotree._draw_tree(opts, cb, tree, { 0 }, reverse or false)
  return rows
end

local function collect_graph(tree)
  local rows = {}
  local cb = function(seq, line)
    table.insert(rows, { seq = seq, line = utils.strip_ansi_coloring(line) })
  end
  undotree._draw_graph(opts, cb, tree, 0, false)
  return rows
end

local function origin()
  return { [0] = { child = {}, time = -1 } }
end

local function linear_chain()
  return {
    [0] = { child = { 1 }, time = -1 },
    [1] = { child = { 2 }, time = FROZEN_TIME },
    [2] = { child = {}, time = FROZEN_TIME + 10 },
  }
end

local function simple_branch()
  return {
    [0] = { child = { 1 }, time = -1 },
    [1] = { child = { 2, 3 }, time = FROZEN_TIME },
    [2] = { child = {}, time = FROZEN_TIME + 5 },
    [3] = { child = {}, time = FROZEN_TIME + 10 },
  }
end

local function triple_branch()
  return {
    [0] = { child = { 1 }, time = -1 },
    [1] = { child = { 2, 3, 4 }, time = FROZEN_TIME },
    [2] = { child = {}, time = FROZEN_TIME + 5 },
    [3] = { child = {}, time = FROZEN_TIME + 10 },
    [4] = { child = {}, time = FROZEN_TIME + 15 },
  }
end

local function nested_branches()
  return {
    [0] = { child = { 1, 2 }, time = -1 },
    [1] = { child = { 3, 4 }, time = FROZEN_TIME },
    [2] = { child = {}, time = FROZEN_TIME + 5 },
    [3] = { child = {}, time = FROZEN_TIME + 10 },
    [4] = { child = {}, time = FROZEN_TIME + 15 },
  }
end

local function grandchild_branch()
  return {
    [0] = { child = { 1 }, time = -1 },
    [1] = { child = { 2, 3, 4 }, time = FROZEN_TIME },
    [2] = { child = {}, time = FROZEN_TIME + 5 },
    [3] = { child = { 5 }, time = FROZEN_TIME + 10 },
    [4] = { child = {}, time = FROZEN_TIME + 15 },
    [5] = { child = {}, time = FROZEN_TIME + 20 },
  }
end

describe("undotree draw_tree", function()
  local orig_time, orig_ansi

  before_each(function()
    orig_time = freeze_time()
    orig_ansi = setup_ansi_identity()
  end)

  after_each(function()
    _G.os.time = orig_time
    restore_ansi_identity(orig_ansi)
  end)

  it("renders a single origin node", function()
    local rows = collect_tree(origin())
    eq({
      { seq = 0, line = "0\t\torigin" },
    }, rows)
  end)

  it("renders a linear chain without branch glyphs", function()
    local rows = collect_tree(linear_chain())
    eq({
      { seq = 0, line = "0\t\torigin" },
      { seq = 1, line = "1\t\tjust now" },
      { seq = 2, line = "2\t\tjust now" },
    }, rows)
  end)

  it("renders branch children with box-drawing glyphs", function()
    local rows = collect_tree(simple_branch())
    eq({
      { seq = 0, line = "0\t\torigin" },
      { seq = 1, line = "1\t\tjust now" },
      { seq = 2, line = "├── 2\t\tjust now" },
      { seq = 3, line = "└── 3\t\tjust now" },
    }, rows)
  end)

  it("uses reversed leaf glyphs when reverse is true", function()
    local rows = collect_tree(simple_branch(), true)
    eq({
      { seq = 0, line = "0\t\torigin" },
      { seq = 1, line = "1\t\tjust now" },
      { seq = 2, line = "├── 2\t\tjust now" },
      { seq = 3, line = "┌── 3\t\tjust now" },
    }, rows)
  end)

  it("handles three siblings", function()
    local rows = collect_tree(triple_branch())
    eq({
      { seq = 0, line = "0\t\torigin" },
      { seq = 1, line = "1\t\tjust now" },
      { seq = 2, line = "├── 2\t\tjust now" },
      { seq = 3, line = "├── 3\t\tjust now" },
      { seq = 4, line = "└── 4\t\tjust now" },
    }, rows)
  end)

  it("renders nested branches in pre-order", function()
    local rows = collect_tree(nested_branches())
    eq({
      { seq = 0, line = "0\t\torigin" },
      { seq = 1, line = "├── 1\t\tjust now" },
      { seq = 3, line = "│   ├── 3\t\tjust now" },
      { seq = 4, line = "│   └── 4\t\tjust now" },
      { seq = 2, line = "└── 2\t\tjust now" },
    }, rows)
  end)

  it("renders a grandchild in pre-order", function()
    local rows = collect_tree(grandchild_branch())
    eq({
      { seq = 0, line = "0\t\torigin" },
      { seq = 1, line = "1\t\tjust now" },
      { seq = 2, line = "├── 2\t\tjust now" },
      { seq = 3, line = "├── 3\t\tjust now" },
      { seq = 5, line = "│   5\t\tjust now" },
      { seq = 4, line = "└── 4\t\tjust now" },
    }, rows)
  end)
end)

describe("undotree draw_graph", function()
  local orig_time, orig_ansi

  before_each(function()
    orig_time = freeze_time()
    orig_ansi = setup_ansi_identity()
  end)

  after_each(function()
    _G.os.time = orig_time
    restore_ansi_identity(orig_ansi)
  end)

  it("renders a single origin node", function()
    local rows = collect_graph(origin())
    eq({
      { seq = 0, line = "●    0    (origin)" },
    }, rows)
  end)

  it("renders a linear chain", function()
    local rows = collect_graph(linear_chain())
    eq({
      { seq = 0, line = "●    0    (origin)" },
      { seq = 1, line = "●    1    (just now)" },
      { seq = 2, line = "●    2    (just now)" },
    }, rows)
  end)

  it("renders a branch with connector and :Undotree-style columns", function()
    local rows = collect_graph(simple_branch())
    eq({
      { seq = 0, line = "●    0    (origin)" },
      { seq = 1, line = "●    1    (just now)" },
      { seq = nil, line = "│╲" },
      { seq = 2, line = "│ ●    2    (just now)" },
      { seq = 3, line = "●    3    (just now)" },
    }, rows)
  end)

  it("renders three siblings", function()
    local rows = collect_graph(triple_branch())
    eq({
      { seq = 0, line = "●    0    (origin)" },
      { seq = 1, line = "●    1    (just now)" },
      { seq = nil, line = "│╲" },
      { seq = 2, line = "│ ●    2    (just now)" },
      { seq = nil, line = "│╲" },
      { seq = 3, line = "│ ●    3    (just now)" },
      { seq = 4, line = "●    4    (just now)" },
    }, rows)
  end)

  it("renders nested branches with remove/branch connectors", function()
    local rows = collect_graph(nested_branches())
    eq({
      { seq = 0, line = "●    0    (origin)" },
      { seq = nil, line = "│╲" },
      { seq = 1, line = "│ ●    1    (just now)" },
      { seq = 2, line = "● │    2    (just now)" },
      { seq = nil, line = " ╱│" },
      { seq = 3, line = "│ ●    3    (just now)" },
      { seq = 4, line = "●    4    (just now)" },
    }, rows)
  end)

  it("emits connector rows with no digits and node rows with digits", function()
    local rows = collect_graph(simple_branch())
    for _, r in ipairs(rows) do
      if r.seq == nil then
        eq(nil, r.line:match("%d"))
      else
        eq(true, r.line:match("%d+") ~= nil)
      end
    end
  end)
end)
