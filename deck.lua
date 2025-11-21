local Card = require "card"
local M = {}

-- seed once at module load (avoid reseeding on every shuffle)
math.randomseed(os.time())
math.random() -- warmup

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
