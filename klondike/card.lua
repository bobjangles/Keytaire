local Card = {}
Card.__index = Card

local unpack = table.unpack or unpack

local ranks = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local suits = { "s", "h", "d", "c" }

function Card.new(rankIndex, suitIndex)
    local self = setmetatable({}, Card)
    self.rankIndex = rankIndex -- 1..13
    self.suitIndex = suitIndex -- 1..4
    self.rank = ranks[rankIndex]
    self.suit = suits[suitIndex]
    self.faceUp = false
    -- red for hearts/diamonds (use numeric colors, to be unpacked when calling love.graphics.setColor)
    self.color = (suitIndex == 2 or suitIndex == 3) and {1,0,0} or {0,0,0}
    return self
end

function Card:draw(x, y, w, h, font)
    if not self.faceUp then
        -- facedown
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
        love.graphics.setColor(0.15, 0.15, 0.15)
        for i=4, h-8, 6 do
            love.graphics.line(x+6, y+i, x+w-6, y+i-2)
        end
    else
        -- faceup
        love.graphics.setColor(1,1,1)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
        love.graphics.setColor(0,0,0)
        love.graphics.rectangle("line", x, y, w, h, 6, 6)
        love.graphics.setFont(font)
        love.graphics.setColor(unpack(self.color))
        love.graphics.print(self.rank .. self.suit, x+8, y+6)
        -- second corner (keep color)
        love.graphics.setColor(unpack(self.color))
        love.graphics.print(self.rank .. self.suit, x+w-28, y+h-24)
    end
end

function Card:rank()
    return self.rankIndex
end

function Card:suit()
    return self.suitIndex
end

function Card:isRed()
    return (self.suitIndex == 2 or self.suitIndex == 3)
end

return Card
