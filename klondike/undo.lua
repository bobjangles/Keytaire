local Undo = {}
Undo.__index = Undo

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

-- NEW: Transfers physical coordinates from the visible screen to the restored logical state
local function transferCoordinates(oldState, newState)
    local coords = {}
    
    local function scan(pile)
        for _, c in ipairs(pile) do
            coords[c.rankIndex .. "_" .. c.suitIndex] = {x = c.x, y = c.y}
        end
    end

    -- Map all current on-screen coordinates
    scan(oldState.stock)
    scan(oldState.waste)
    for i=1,4 do scan(oldState.foundations[i]) end
    for i=1,7 do scan(oldState.tableau[i]) end

    -- Apply them to the restored layout
    local function apply(pile)
        for _, c in ipairs(pile) do
            local key = c.rankIndex .. "_" .. c.suitIndex
            if coords[key] then
                c.x = coords[key].x
                c.y = coords[key].y
            end
        end
    end

    apply(newState.stock)
    apply(newState.waste)
    for i=1,4 do apply(newState.foundations[i]) end
    for i=1,7 do apply(newState.tableau[i]) end
end

function Undo.new(limit)
    return setmetatable({ undoStack = {}, redoStack = {}, limit = limit or 200 }, Undo)
end

function Undo:push(state)
    table.insert(self.undoStack, deepcopy(state))
    self.redoStack = {}
    if self.limit and #self.undoStack > self.limit then
        table.remove(self.undoStack, 1)
    end
end

function Undo:undo(currentState)
    local prev = table.remove(self.undoStack)
    if not prev then return nil end
    table.insert(self.redoStack, deepcopy(currentState))
    
    local restored = deepcopy(prev)
    transferCoordinates(currentState, restored) -- Prevent teleportation
    return restored
end

function Undo:redo(currentState)
    local nextState = table.remove(self.redoStack)
    if not nextState then return nil end
    table.insert(self.undoStack, deepcopy(currentState))
    
    local restored = deepcopy(nextState)
    transferCoordinates(currentState, restored) -- Prevent teleportation
    return restored
end

function Undo:clear()
    self.undoStack = {}
    self.redoStack = {}
end

return Undo
