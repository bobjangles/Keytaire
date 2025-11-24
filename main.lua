local Deck = require "deck"
local Card = require "card"
local Input = require "input"

local CARD_W, CARD_H = 100, 140
local PADDING = 20
local TABLEAU_SPACING = 24
local UI_TOP = 20
local UI_LEFT = 20

local TABLEAU_COUNT = 10

local state = {}
local fonts = {}

local bgImage = nil

local cursor = {
    area = "stock",
    index = 1,
    cardIndex = 0,
}

local selected = nil

local lastKey = nil
local lastKeyTime = 0
local SEQ_TIMEOUT = 0.5

local function newGame()
    local deck = Deck.newDeck()
    Deck.shuffle(deck)

    local foundations = {}
    local tableau = {}
    for i = 1, TABLEAU_COUNT do tableau[i] = {} end
    local stock = {}

    -- deal to tableau: first 4 piles get 6, remaining 6 get 5; top card face-up
    for i = 1, TABLEAU_COUNT do
        local count = (i <= 4) and 6 or 5
        for j = 1, count do
            local c = table.remove(deck)
            if not c then
                error("Deck exhausted while dealing to tableau: deck size insufficient for layout")
            end
            c.faceUp = (j == count)
            table.insert(tableau[i], c)
        end
    end

    while #deck > 0 do
        local c = table.remove(deck)
        c.faceUp = false
        table.insert(stock, c)
    end

    state = { stock = stock, foundations = foundations, tableau = tableau }

    cursor.area = "stock"
    cursor.index = 1
    cursor.cardIndex = 0
    selected = nil
end

local function drawTextCentered(text, x, y, w)
    local font = fonts.small
    local sw = font:getWidth(text)
    love.graphics.setFont(font)
    love.graphics.print(text, x + (w - sw)/2, y)
end

local function drawCardBack(x,y)
    love.graphics.setColor(0.2,0.2,0.6)
    love.graphics.rectangle("fill", x, y, CARD_W, CARD_H, 6)
    love.graphics.setColor(0.15,0.15,0.4)
    love.graphics.rectangle("line", x, y, CARD_W, CARD_H, 6)
end

local function getTopOfPile(pile)
    return pile[#pile]
end

local function isDescending(c1, c2)
    if not c1 or not c2 then return false end
    return (c1.rankIndex + 1 == c2.rankIndex)
end

local function sequenceIsSameSuitDescending(seq)
    if #seq <= 1 then return true end
    for i = 1, #seq - 1 do
        if not (seq[i].suit == seq[i+1].suit and seq[i].rankIndex + 1 == seq[i+1].rankIndex) then
            return false
        end
    end
    return true
end

local function canMoveSequenceToTableau(seq, destPile)
    if #seq == 0 then return false end
    if #seq > 1 and not sequenceIsSameSuitDescending(seq) then return false end
    local top = getTopOfPile(destPile)
    if not top then return true end
    return isDescending(seq[1], top)
end

local function removeCompleteSetIfPresent(pile, foundations)
    if #pile < 13 then return end
    local start = #pile - 12
    local s = pile[start].suit
    for i = 0, 12 do
        local card = pile[start + i]
        if not card or card.suit ~= s or card.rankIndex ~= 13 - i then
            return
        end
    end
    local completed = {}
    for i = 1, 13 do table.insert(completed, table.remove(pile)) end
    table.insert(foundations, completed)
end

local function firstFaceUpIndex(pile)
    for i = 1, #pile do
        if pile[i].faceUp then return i end
    end
    return nil
end

local function faceUpCount(pile)
    local first = firstFaceUpIndex(pile)
    if not first then return 0 end
    return #pile - first + 1
end

local function faceUpPosToAbsolute(pile, pos)
    local first = firstFaceUpIndex(pile)
    if not first then return nil end
    if pos < 1 then return nil end
    local abs = first + pos - 1
    if abs > #pile then return nil end
    return abs
end

local function pickupFromPile(area, idx, faceUpPos)
    if area == "tableau" then
        local pile = state.tableau[idx]
        if #pile == 0 then return nil end
        local nFaceUp = faceUpCount(pile)
        if nFaceUp == 0 then return nil end
        faceUpPos = faceUpPos or nFaceUp
        local absIndex = faceUpPosToAbsolute(pile, faceUpPos)
        if not absIndex then return nil end
        if not pile[absIndex].faceUp then return nil end
        local seq = {}
        for i = absIndex, #pile do table.insert(seq, pile[i]) end
        for _ = 1, #seq do table.remove(pile) end
        return {pileType="tableau", index=idx, cards=seq, absIndex=absIndex}
    elseif area == "foundation" then
        local pile = state.foundations[idx]
        if #pile == 0 then return nil end
        local card = table.remove(pile)
        return {pileType="foundation", index=idx, cards={card}}
    elseif area == "stock" then
        return nil
    end
    return nil
end

local function flipOriginIfNeeded(pickup)
    if pickup and pickup.pileType == "tableau" then
        local origin = state.tableau[pickup.index]
        if #origin > 0 and not origin[#origin].faceUp then origin[#origin].faceUp = true end
    end
end

local function placeOntoPile(area, idx, pickup)
    if not pickup or #pickup.cards == 0 then return false end
    if area == "tableau" then
        local dest = state.tableau[idx]
        if canMoveSequenceToTableau(pickup.cards, dest) then
            for _, c in ipairs(pickup.cards) do table.insert(dest, c) end
            flipOriginIfNeeded(pickup)
            removeCompleteSetIfPresent(dest, state.foundations)
            return true
        end
    elseif area == "foundation" then
        return false
    elseif area == "stock" then
        return false
    end
    return false
end

local function drawFromStock()
    if #state.stock < TABLEAU_COUNT then return end
    for i = 1, TABLEAU_COUNT do
        local c = table.remove(state.stock)
        c.faceUp = true
        table.insert(state.tableau[i], c)
    end
end

function love.load()
    fonts.small = love.graphics.newFont(14)
    fonts.big = love.graphics.newFont(20)

    local ok, img = pcall(function() return love.graphics.newImage("PNG/Texturelabs_Fabric_184M.jpg") end)
    if ok and img then bgImage = img else bgImage = nil end

    newGame()
end

local function cursorToXY(a, i)
    if a == "stock" then return UI_LEFT, UI_TOP, CARD_W, CARD_H
    elseif a == "foundation" then local start = UI_LEFT + 420; return start + (i-1)*(CARD_W+12), UI_TOP, CARD_W, CARD_H
    elseif a == "tableau" then local startY = UI_TOP + CARD_H + 60; local startX = UI_LEFT; return startX + (i-1)*(CARD_W + TABLEAU_SPACING), startY, CARD_W, CARD_H end
end

local function drawSelectedAtBottomLeft()
    if not selected then return end
    local x = UI_LEFT
    local margin_bottom = 20
    local screen_h = love.graphics.getHeight()
    local start_y = screen_h - CARD_H - margin_bottom
    for i = 1, #selected.cards do
        local c = selected.cards[i]
        local drawY = start_y + (i-1)*20
        c:draw(x, drawY, CARD_W, CARD_H, fonts.small)
    end
end

local function moveToFarRight()
    if cursor.area == "tableau" then
        cursor.index = TABLEAU_COUNT
        local pile = state.tableau[cursor.index]
        local nFaceUp = faceUpCount(pile)
        cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
    else
        cursor.area = "foundation"
        cursor.index = math.max(1, #state.foundations)
        if cursor.index == 0 then cursor.index = 1 end
        cursor.cardIndex = 0
    end
end

local function moveToFarLeft()
    if cursor.area == "tableau" then
        cursor.index = 1
        local pile = state.tableau[cursor.index]
        local nFaceUp = faceUpCount(pile)
        cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
    else
        cursor.area = "stock"
        cursor.index = 1
        cursor.cardIndex = 0
    end
end

local function moveToTopRow()
    cursor.area = "stock"
    cursor.index = 1
    cursor.cardIndex = 0
end

local function moveToBottomRow()
    cursor.area = "tableau"
    if not cursor.index or cursor.index < 1 then cursor.index = 1 end
    cursor.index = math.min(TABLEAU_COUNT, cursor.index)
    local pile = state.tableau[cursor.index]
    local nFaceUp = faceUpCount(pile)
    cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
end

function love.keypressed(key)
    local now = love.timer.getTime()

    if key == "g" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        moveToBottomRow()
        lastKey = nil
        lastKeyTime = 0
        return
    end

    local isDollar = false
    if key == "$" or key == "end" then isDollar = true
    elseif key == "4" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then isDollar = true end
    if isDollar then moveToFarRight(); lastKey=nil; lastKeyTime=0; return end

    if key == "0" then moveToFarLeft(); lastKey=nil; lastKeyTime=0; return end

    if key == "g" and not (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        if lastKey == "g" and (now - lastKeyTime) <= SEQ_TIMEOUT then
            moveToTopRow(); lastKey=nil; lastKeyTime=0; return
        else
            lastKey = "g"; lastKeyTime = now; return
        end
    end

    lastKey = nil; lastKeyTime = 0

    if Input.is("left", key) then
        if cursor.area == "tableau" then
            cursor.index = math.max(1, cursor.index - 1)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 then cursor.cardIndex = 0 else cursor.cardIndex = math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp) end
        else
            if cursor.area == "foundation" then
                if cursor.index > 1 then cursor.index = cursor.index - 1 else cursor.area = "stock"; cursor.index = 1 end
            end
        end
    elseif Input.is("right", key) then
        if cursor.area == "tableau" then
            cursor.index = math.min(TABLEAU_COUNT, cursor.index + 1)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 then cursor.cardIndex = 0 else cursor.cardIndex = math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp) end
        else
            if cursor.area == "stock" then if #state.foundations > 0 then cursor.area = "foundation"; cursor.index = 1 end
            elseif cursor.area == "foundation" then cursor.index = math.min(#state.foundations, cursor.index + 1) end
        end
    elseif Input.is("down", key) then
        if cursor.area == "tableau" then
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp > 0 then cursor.cardIndex = math.min(nFaceUp, (cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp) + 1) end
        else
            cursor.area = "tableau"; cursor.index = 1
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
        end
    elseif Input.is("up", key) then
        if cursor.area == "tableau" then
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 or cursor.cardIndex <= 1 then
                cursor.area = "stock"; cursor.index = 1; cursor.cardIndex = 0
            else
                cursor.cardIndex = math.max(1, cursor.cardIndex - 1)
            end
        else
            cursor.area = "stock"; cursor.index = 1; cursor.cardIndex = 0
        end
    elseif Input.is("select", key) then
        if selected then
            local origin = selected
            if origin.pileType == "tableau" then
                local p = state.tableau[origin.index]
                for _, c in ipairs(origin.cards) do table.insert(p, c) end
            elseif origin.pileType == "foundation" then
                for _, c in ipairs(origin.cards) do table.insert(state.foundations[origin.index], c) end
            end
            selected = nil
        else
            if cursor.area == "tableau" then
                local pile = state.tableau[cursor.index]
                local nFaceUp = faceUpCount(pile)
                if nFaceUp == 0 then return end
                local p = pickupFromPile("tableau", cursor.index, cursor.cardIndex)
                if p then selected = p end
            else
                local p = pickupFromPile(cursor.area, cursor.index)
                if p then selected = p end
            end
        end
    elseif Input.is("move", key) then
        if selected then
            local ok = placeOntoPile(cursor.area, cursor.index, selected)
            if ok then selected = nil else
                local origin = selected
                if origin.pileType == "tableau" then
                    local p = state.tableau[origin.index]
                    for _, c in ipairs(origin.cards) do table.insert(p, c) end
                elseif origin.pileType == "foundation" then
                    for _, c in ipairs(origin.cards) do table.insert(state.foundations[origin.index], c) end
                end
                selected = nil
            end
        else
            if cursor.area == "stock" then drawFromStock() end
        end
    elseif Input.is("restart", key) then
        newGame()
    elseif key == "escape" then love.event.quit() end
end

function love.draw()
    if bgImage then
        local w, h = love.graphics.getDimensions()
        local iw, ih = bgImage:getWidth(), bgImage:getHeight()
        local sx, sy = w / iw, h / ih
        love.graphics.setColor(1,1,1)
        love.graphics.draw(bgImage, 0, 0, 0, sx, sy)
    else
        love.graphics.clear(0.12, 0.6, 0.2)
    end

    love.graphics.setFont(fonts.big)
    love.graphics.setColor(1,1,1)
    love.graphics.print("Spider Solitaire — two-suit variant (vim: h j k l). Space to pick, Enter/m to place", UI_LEFT, UI_TOP - 10)

    local sx, sy = cursorToXY("stock", 1)
    if #state.stock > 0 then drawCardBack(sx, sy) else
        love.graphics.setColor(0.2,0.2,0.2)
        love.graphics.rectangle("line", sx, sy, CARD_W, CARD_H, 6)
        drawTextCentered("Empty", sx, sy+CARD_H/2-8, CARD_W)
    end
    if cursor.area == "stock" then
        love.graphics.setColor(1,1,0,0.9)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", sx-4, sy-4, CARD_W+8, CARD_H+8, 8)
        love.graphics.setLineWidth(1)
    end

    for i = 1, math.max(4, #state.foundations) do
        local fx, fy = cursorToXY("foundation", i)
        local pile = state.foundations[i] or {}
        if #pile > 0 then
            local top = pile[#pile]
            top:draw(fx, fy, CARD_W, CARD_H, fonts.small)
            drawTextCentered("Completed", fx, fy+CARD_H+6, CARD_W)
        else
            love.graphics.setColor(0.18,0.18,0.18)
            love.graphics.rectangle("line", fx, fy, CARD_W, CARD_H, 6)
            drawTextCentered("Completed", fx, fy+CARD_H/2-8, CARD_W)
        end
        if cursor.area == "foundation" and cursor.index == i then
            love.graphics.setColor(1,1,0,0.9)
            love.graphics.rectangle("line", fx-4, fy-4, CARD_W+8, CARD_H+8, 8)
        end
    end

    for i = 1, TABLEAU_COUNT do
        local tx, ty = cursorToXY("tableau", i)
        local pile = state.tableau[i]
        if #pile == 0 then
            love.graphics.setColor(0.18,0.18,0.18)
            love.graphics.rectangle("line", tx, ty, CARD_W, CARD_H, 6)
            drawTextCentered("Empty", tx, ty+CARD_W/2-8, CARD_W)
        else
            for j = 1, #pile do
                local c = pile[j]
                local drawY = ty + (j-1)*20
                c:draw(tx, drawY, CARD_W, CARD_H, fonts.small)
            end
        end

        if cursor.area == "tableau" and cursor.index == i then
            love.graphics.setColor(1,1,0,0.3)
            love.graphics.rectangle("line", tx-4, ty-4, CARD_W+8, CARD_H+8 + math.max(0,(#pile-1)*20), 8)

            local nFaceUp = faceUpCount(pile)
            if nFaceUp > 0 and cursor.cardIndex > 0 then
                local absIndex = faceUpPosToAbsolute(pile, cursor.cardIndex)
                if absIndex then
                    local startY = ty + (absIndex-1)*20
                    local height = CARD_H + (#pile - absIndex) * 20
                    love.graphics.setColor(1,1,0,0.9)
                    love.graphics.rectangle("line", tx-4, startY-4, CARD_W+8, height+8, 8)
                end
            end
        end
    end

    if selected then
        local sx = UI_LEFT
        local margin_bottom = 20
        local screen_h = love.graphics.getHeight()
        local start_y = screen_h - CARD_H - margin_bottom
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(1,1,1)
        love.graphics.print("Selected: "..#selected.cards.." card(s)", sx, start_y - 18)
        drawSelectedAtBottomLeft()
    end

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1,1,1)
    love.graphics.print("Controls: h/j/k/l or arrows to move · Down/Up (on tableau) cycle face-up cards; Space select/deselect · Enter/m to move/draw from stock · r restart", UI_LEFT, love.graphics.getHeight() - 30) 
