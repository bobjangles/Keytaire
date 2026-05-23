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

-- Combo internal state
Input.lastKey = nil
Input.lastKeyTime = 0
Input.SEQ_TIMEOUT = 0.5 -- seconds for double-press sequences

-- Evaluates the raw input and returns a unified Action String
function Input.getAction(key, isShift, now)
    -- 1) Handle uppercase G -> bottom row
    if key == "g" and isShift then
        Input.lastKey = nil
        return "bottomRow"
    end

    -- 2) Handle '$' (far right)
    if key == "$" or key == "end" or (key == "4" and isShift) then
        Input.lastKey = nil
        return "farRight"
    end

    -- 3) Handle '0' (far left)
    if key == "0" then
        Input.lastKey = nil
        return "farLeft"
    end

    -- 4) Handle 'gg' double-press -> top row
    if key == "g" and not isShift then
        if Input.lastKey == "g" and (now - Input.lastKeyTime) <= Input.SEQ_TIMEOUT then
            Input.lastKey = nil
            return "topRow"
        else
            Input.lastKey = "g"
            Input.lastKeyTime = now
            return nil
        end
    end

    -- Clear sequence state if any other key is pressed
    Input.lastKey = nil

    -- 5) Match standard bindings
    for action, list in pairs(Input.bindings) do
        for _, k in ipairs(list) do
            if k == key then return action end
        end
    end

    return nil
end

return Input
