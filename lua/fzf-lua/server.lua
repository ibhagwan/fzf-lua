local FzfLuaSrv = {}
FzfLuaSrv.__index = FzfLuaSrv

local _INSTANCES = {}

function FzfLuaSrv.new()
  local self = setmetatable({}, FzfLuaSrv)
  -- Find the first empty slot in the table as values
  -- can be fragmented after a call to `:close()`
  self._IDX = 0
  local i = nil
  repeat
    self._IDX = self._IDX + 1
    i = next(_INSTANCES, i)
  until not i or self._IDX < i
  _INSTANCES[self._IDX] = self
  return self, self._IDX
end

function FzfLuaSrv:close()
  _INSTANCES[self._IDX] = nil
  self._IDX = nil
end

function FzfLuaSrv:id()
  return self._IDX
end

return FzfLuaSrv
