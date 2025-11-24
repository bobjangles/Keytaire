local Card = require "card"
local M = {}

-- seed once at module load
math.randomseed(os.time())
math.random() -- warmup

-- Use two suits (spades and hearts) and 4 copies of each (26 * 4 = 104)
local SUITS = {1, 2}      -- suit indices from card.lua: 1="s", 2="h"
local DECK_COUNT = 4      -- 4 copies of the 2-suit set -> 104 cards

function M.newDeck()
    local deck = {}
    for d = 1, DECK_COUNT do
        for _, s in ipairs(SUITS) do
            for r = 1, 13 do
                table.insert(deck, Card.new(r, s))
            end
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
