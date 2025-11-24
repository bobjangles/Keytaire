local Card = require "card"
local M = {}

-- seed once at module load (avoid reseeding on every shuffle)
math.randomseed(os.time())
math.random() -- warmup

-- Use two suits: spades and hearts (matching card.lua suits table)
local SUITS = {1, 2}
-- To reach 104 cards for Spider, use 4 physical decks worth of these two suits: 4 * 2 * 13 = 104
local DECK_COUNT = 4

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
