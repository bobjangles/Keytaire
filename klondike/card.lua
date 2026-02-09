local Card = {}
Card.__index = Card

local ImageCache = require "card_images"

local ranks = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local suits = { "s", "h", "d", "c" }

function Card.new(rankIndex, suitIndex)
    local self = setmetatable({}, Card)
    self.rankIndex = rankIndex
    self.suitIndex = suitIndex
    self.rank = ranks[rankIndex]
    self.suit = suits[suitIndex]
    self.faceUp = false
    self.color = (suitIndex == 2 or suitIndex == 3) and {1,0,0} or {0,0,0}
    return self
end

function Card:draw(x, y, w, h, font)
    if not self.faceUp then
        -- Draw card back image
        local backTex = ImageCache.getBackTexture(w,h)
        if backTex then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(backTex, x, y)
        else
            -- Fallback to drawn back
            love.graphics.setColor(0.2, 0.2, 0.6)
            love.graphics.rectangle("fill", x, y, w, h, 6)
	    love.graphics.setColor(0.15,0.15,0.4)
	    love.graphics.rectangle("line", x, y, w, h, 6)
        end
    else
        -- Draw card face image
        local tex = ImageCache.getCardTexture(self.rank, self.suit, w, h)
        if tex then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(tex, x, y)
        else
            -- Fallback to drawn card
            love.graphics.setColor(1, 1, 1)
            love.graphics.rectangle("fill", x, y, w, h, 6, 6)
            love.graphics.setColor(0, 0, 0)
            love.graphics.rectangle("line", x, y, w, h, 6, 6)
            love.graphics.setFont(font)
            love.graphics.setColor(unpack(self.color))
            love.graphics.print(self.rank .. self.suit, x + 8, y + 6)
        end
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
