-- undo.lua
-- Simple undo/redo manager using deep copies of state tables.
-- Usage:
--   local Undo = require "undo"
--   local undo = Undo.new(200) -- optional limit
--   undo:push(gameState) -- BEFORE applying a move
--   local prev = undo:undo(gameState) -- returns previous state (deepcopy) or nil
--   local next = undo:redo(gameState) -- returns next state (deepcopy) or nil

local Undo = {}
Undo.__index = Undo

-- deep copy (handles nested tables; does not handle userdata or functions specially)
local function deepcopy(obj, seen)
    if type(obj) ~= "table" then return obj end
    seen = seen or {}
    if seen[obj] then return seen[obj] end
    local res = {}
    seen[obj] = res
    for k, v in pairs(obj) do
        res[deepcopy(k, seen)] = deepcopy(v, seen)
    end
    local mt = getmetatable(obj)
    if mt then
        setmetatable(res, deepcopy(mt, seen))
    end
    return res
end

function Undo.new(limit)
    return setmetatable({ undoStack = {}, redoStack = {}, limit = limit or 200 }, Undo)
end

-- Save a snapshot of state. Call this BEFORE applying a move.
function Undo:push(state)
    table.insert(self.undoStack, deepcopy(state))
    -- clear redo on new branch
    self.redoStack = {}
    if self.limit and #self.undoStack > self.limit then
        -- drop oldest
        table.remove(self.undoStack, 1)
    end
end

-- Undo: supply the current state so we can push it to redo
-- Returns previous state (deep copy) or nil if none
function Undo:undo(currentState)
    local prev = table.remove(self.undoStack)
    if not prev then return nil end
    table.insert(self.redoStack, deepcopy(currentState))
    return deepcopy(prev)
end

-- Redo: supply the current state so we can push it to undo
-- Returns next state (deep copy) or nil if none
function Undo:redo(currentState)
    local nextState = table.remove(self.redoStack)
    if not nextState then return nil end
    table.insert(self.undoStack, deepcopy(currentState))
    return deepcopy(nextState)
end

function Undo:clear()
    self.undoStack = {}
    self.redoStack = {}
end

return Undo
