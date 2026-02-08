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
        local backImg = ImageCache.getBackImage()
        if backImg then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(backImg, x, y, 0, w / backImg:getWidth(), h / backImg:getHeight())
        else
            -- Fallback to drawn back
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.rectangle("fill", x, y, w, h, 6, 6)
        end
    else
        -- Draw card face image
        local cardImg = ImageCache.getCardImage(self.rank, self.suit)
        if cardImg then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(cardImg, x, y, 0, w / cardImg:getWidth(), h / cardImg:getHeight())
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
