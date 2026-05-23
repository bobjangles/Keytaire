local Card = {}
Card.__index = Card

local ImageCache = require "card_images"
local Shaders = require "shaders"

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
    self.x = nil 
    self.y = nil 
    return self
end

function Card:draw(x, y, w, h, isSelected)
    love.graphics.setColor(1,1,1,1)

    local tex = self.faceUp and ImageCache.getCardImage(self.rank, self.suit) or ImageCache.getBackImage()

    if not tex then return end

    local sx = w / tex:getWidth()
    local sy = h / tex:getHeight()
    local offset = isSelected and 8 or 3

    -- Shadow
    love.graphics.setShader(Shaders.dropShadow)
    love.graphics.draw(tex, x + offset, y + offset, 0, sx, sy)
    love.graphics.setShader()
    
    -- Card
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(tex, x, y, 0, sx, sy)
end

function Card:update(dt, targetX, targetY)
    -- if X or Y is nil, snap to target instantly for the first frame
    if self.x == nil or self.y == nil then
        self.x = targetX
        self.y = targetY
        return
    end

    -- Snappier animation speed
    local speed = 25
    local dx = targetX - self.x
    local dy = targetY - self.y

    -- Snap into place to stop micro-jitter when very close
    if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then
        self.x = targetX
        self.y = targetY
    else
        self.x = self.x + dx * speed * dt
        self.y = self.y + dy * speed * dt
    end
end

function Card:rank() return self.rankIndex end
function Card:suit() return self.suitIndex end
function Card:isRed() return (self.suitIndex == 2 or self.suitIndex == 3) end

return Card
