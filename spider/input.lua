local Input = {}
Input.bindings = {
    left = {"left", "h"},
    right = {"right", "l"},
    up = {"up", "k"},
    down = {"down", "j"},
    select = {"space"},
    move = {"return", "m"},
    restart = {"r"},
    autofound = {"f"},
    undo = {"u"},
    redo = {"n"},
}

function Input.is(action, key)
    local list = Input.bindings[action] or {}
    for _,k in ipairs(list) do
        if k == key then return true end
    end
    return false
end

return Input
