local Card = require "card"
local M = {}

function M.newDeck()
    local deck = {}
    for s=1,4 do
        for r=1,13 do
            table.insert(deck, Card.new(r,s))
        end
    end
    return deck
end

local function shuffle(deck)
    math.randomseed(os.time())
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function M.shuffle(deck)
    shuffle(deck)
end

function M.draw(deck)
    return table.remove(deck)
end

return M
