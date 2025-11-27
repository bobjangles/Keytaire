-- Spider Solitaire (2-suit mode, fixed deck size) adapted to Keytaire repo modules
-- Uses: card.lua (Card), deck.lua (Deck), input.lua (Input), undo.lua (Undo)
-- Controls (via input.lua):
--  h / left  : move cursor left
--  l / right : move cursor right
--  k / up    : move cursor up / among face-up cards
--  j / down  : move cursor down / among face-up cards
--  space     : select / deselect stack
--  return/m  : place selected stack or draw from stock when cursor on stock
--  f         : autofound (remove complete 13-card same-suit sequence from focused tableau)
--  r         : restart
--  u / n     : undo / redo
local Deck = require "deck"
local Card = require "card"
local Input = require "input"
local Undo = require "undo"

local CARD_W, CARD_H = 100, 140
local TABLEAU_SPACING = 30
local UI_TOP = 20
local UI_LEFT = 20
local NUM_TABLEAU = 10

local fonts = {}
local undo = Undo.new(500)

-- game state
local state = {
    suitsMode = 2, -- default to 2-suit game
    stock = {},
    tableau = {},
    foundations = {}, -- list of removed 13-card sequences
    score = 0,
    msg = "Spider (2-suit) — use h/j/k/l (or arrows). Space select, Enter/m move/draw, f autofound, r restart.",
}

local cursor = { area = "stock", index = 1, cardIndex = 0 }
local selected = nil -- { pileType="tableau", index, cards={}, absIndex }

-- utilities
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Build a deck that always provides the standard Spider card-count (2 * 4 * 13 = 104)
-- while using a reduced set of suits if requested.
-- For suitsCount < 4 we cycle the chosen suits to fill 4 suit-slots per deck,
-- ensuring there are enough cards for the initial deal and stock.
local function buildDeck(suitsCount)
    local baseSuits = {}
    if suitsCount == 1 then
        baseSuits = {1}
    elseif suitsCount == 2 then
        baseSuits = {1, 2}
    else
        baseSuits = {1, 2, 3, 4}
    end

    -- create a per-deck suit list of length 4 by cycling baseSuits
    local perDeckSuits = {}
    for k = 1, 4 do
        perDeckSuits[k] = baseSuits[((k - 1) % #baseSuits) + 1]
    end

    local deck = {}
    -- two decks (standard Spider uses two decks) with perDeckSuits each
    for copy = 1, 2 do
        for _, s in ipairs(perDeckSuits) do
            for r = 1, 13 do
                table.insert(deck, Card.new(r, s))
            end
        end
    end
    return deck
end

local function firstFaceUpIndex(pile)
    for i=1,#pile do
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

local function isDescending(a, b)
    return a.rankIndex == (b.rankIndex + 1)
end

local function validateSequence(seq)
    if #seq == 0 then return false end
    for k = 1, #seq do
        if not seq[k].faceUp then return false end
        if k > 1 and not isDescending(seq[k-1], seq[k]) then return false end
    end
    return true
end

local function isComplete13(pile)
    if #pile < 13 then return false end
    local start = #pile - 12
    local suit = pile[start].suitIndex
    for i = start, #pile do
        if pile[i].suitIndex ~= suit then return false end
        if i > start and not isDescending(pile[i-1], pile[i]) then return false end
        if not pile[i].faceUp then return false end
    end
    return true
end

local function popN(pile, n)
    local out = {}
    for i = 1, n do
        table.insert(out, 1, table.remove(pile))
    end
    return out
end

local function pushSeq(pile, seq)
    for _, c in ipairs(seq) do table.insert(pile, c) end
end

local function findPickupIndex(pile)
    if #pile == 0 then return nil end
    local i = #pile
    while i > 1 do
        local above = pile[i]
        local below = pile[i-1]
        if not above.faceUp or not below.faceUp then break end
        if not isDescending(below, above) then break end
        i = i - 1
    end
    while i <= #pile and not pile[i].faceUp do i = i + 1 end
    if i > #pile then return nil end
    return i
end

local function droppable(destPile, movingFirst)
    if not destPile then return false end
    if #destPile == 0 then
        return true
    else
        local destTop = destPile[#destPile]
        return destTop.rankIndex == (movingFirst.rankIndex + 1)
    end
end

-- Game actions
local function newGame(suitsMode)
    suitsMode = suitsMode or 2 -- default to 2 suits
    local deck = buildDeck(suitsMode)
    shuffle(deck)

    local tableau = {}
    for i=1,NUM_TABLEAU do tableau[i] = {} end

    local dealCounts = {}
    for i=1,NUM_TABLEAU do dealCounts[i] = (i <= 4) and 6 or 5 end

    for i=1,NUM_TABLEAU do
        for j=1,dealCounts[i] do
            local c = table.remove(deck)
            -- defensive check: should not happen because buildDeck produces 104 cards
            if not c then
                error("buildDeck produced too few cards for initial deal")
            end
            c.faceUp = (j == dealCounts[i])
            table.insert(tableau[i], c)
        end
    end

    -- remaining go to stock facedown
    for _,c in ipairs(deck) do c.faceUp = false end

    state.suitsMode = suitsMode
    state.stock = deck
    state.tableau = tableau
    state.foundations = {}
    state.score = 0
    state.msg = "Spider (2-suit) — use h/j/k/l (or arrows). Space select, Enter/m move/draw, f autofound, r restart."

    cursor.area = "stock"
    cursor.index = 1
    cursor.cardIndex = 0
    selected = nil
    undo:clear()
end

local function flipOriginIfNeeded(pickup)
    if pickup and pickup.pileType == "tableau" then
        local origin = state.tableau[pickup.index]
        if #origin > 0 and not origin[#origin].faceUp then
            origin[#origin].faceUp = true
        end
    end
end

local function dealFromStock()
    if #state.stock == 0 then state.msg = "Stock is empty." return end
    for i=1,NUM_TABLEAU do
        if #state.tableau[i] == 0 then
            state.msg = "Fill empty pile(s) before dealing."
            return
        end
    end
    undo:push(state)
    for i=1,NUM_TABLEAU do
        local card = table.remove(state.stock)
        card.faceUp = true
        table.insert(state.tableau[i], card)
    end
    state.msg = "Dealt one round."
end

local function removeCompleteToFoundation(i)
    local pile = state.tableau[i]
    if isComplete13(pile) then
        local seq = popN(pile, 13)
        table.insert(state.foundations, seq)
        state.score = state.score + 1
        if #pile > 0 then pile[#pile].faceUp = true end
        state.msg = "Moved a complete sequence to foundations."
        return true
    end
    return false
end

local function placeOntoPile(area, idx, pickup)
    if not pickup or #pickup.cards == 0 then return false end
    if area == "tableau" then
        local dest = state.tableau[idx]
        if droppable(dest, pickup.cards[1]) then
            pushSeq(dest, pickup.cards)
            flipOriginIfNeeded(pickup)
            if isComplete13(dest) then
                popN(dest, 13)
                state.score = state.score + 1
                state.msg = "Complete sequence removed to foundation!"
            end
            return true
        end
    end
    return false
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
        return { pileType="tableau", index=idx, cards=seq, absIndex=absIndex }
    end
    return nil
end

-- Drawing helpers
local function cursorToXY(a, i)
    if a == "stock" then
        return UI_LEFT, UI_TOP
    elseif a == "tableau" then
        local startY = UI_TOP + CARD_H + 40
        local startX = UI_LEFT
        return startX + (i-1)*(CARD_W + TABLEAU_SPACING), startY
    end
end

local function drawCardBack(x,y,w,h)
    love.graphics.setColor(0.2,0.2,0.6)
    love.graphics.rectangle("fill", x, y, w, h, 6)
    love.graphics.setColor(0.15,0.15,0.4)
    love.graphics.rectangle("line", x, y, w, h, 6)
end

function love.load()
    math.randomseed(os.time())
    fonts.small = love.graphics.newFont(14)
    fonts.big = love.graphics.newFont(20)
    love.graphics.setFont(fonts.small)
    newGame(2) -- start in 2-suit mode
end

function love.draw()
    love.graphics.clear(0.12, 0.12, 0.12)
    love.graphics.setColor(1,1,1)
    love.graphics.print("Spider (2-suit). Msg: "..state.msg, UI_LEFT + 360, 10)
    love.graphics.print("Stock: " .. tostring(#state.stock) .. " Foundations: " .. tostring(#state.foundations), UI_LEFT + 360, 30)

    -- stock
    local sx, sy = cursorToXY("stock", 1)
    if #state.stock > 0 then
        drawCardBack(sx, sy, CARD_W, CARD_H)
    else
        love.graphics.setColor(0.2,0.2,0.2)
        love.graphics.rectangle("line", sx, sy, CARD_W, CARD_H, 6)
        love.graphics.setColor(1,1,1)
        love.graphics.print("Empty", sx+10, sy+CARD_H/2 - 6)
    end

    -- tableau
    for i = 1, #state.tableau do
        local tx, ty = cursorToXY("tableau", i)
        local pile = state.tableau[i]
        if #pile == 0 then
            love.graphics.setColor(0.18,0.18,0.18)
            love.graphics.rectangle("line", tx, ty, CARD_W, CARD_H, 6)
            love.graphics.setColor(1,1,1)
            love.graphics.print("Empty", tx + CARD_W/2 - 16, ty + CARD_W/2 - 6)
        else
            for j=1,#pile do
                local c = pile[j]
                local drawY = ty + (j-1)*20
                c:draw(tx, drawY, CARD_W, CARD_H, fonts.small)
            end
        end

        -- pile label/index
        love.graphics.setColor(1,1,1)
        love.graphics.print(tostring(i), tx + CARD_W/2 - 4, ty + CARD_H + 18)
    end

    -- cursor highlight
    if cursor.area == "stock" then
        love.graphics.setColor(1,1,0,0.9)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", sx-4, sy-4, CARD_W+8, CARD_H+8, 6)
        love.graphics.setLineWidth(1)
    elseif cursor.area == "tableau" then
        local px, py = cursorToXY("tableau", cursor.index)
        local pile = state.tableau[cursor.index]
        love.graphics.setColor(1,1,0,0.5)
        love.graphics.rectangle("line", px-4, py-4, CARD_W, CARD_H + math.max(0, (#pile-1)*20), 8)
        local nFaceUp = faceUpCount(pile)
        if nFaceUp > 0 and cursor.cardIndex > 0 then
            local absIdx = faceUpPosToAbsolute(pile, cursor.cardIndex)
            if absIdx then
                local startY = py + (absIdx-1)*20
                local height = CARD_H + (#pile - absIdx) * 20
                love.graphics.setColor(1,1,0,0.9)
                love.graphics.rectangle("line", px-4, startY-4, CARD_W+8, height+8, 8)
            end
        end
    end

    -- selected stack drawn bottom-left
    if selected then
        local x = UI_LEFT
        local screen_h = love.graphics.getHeight()
        local start_y = screen_h - CARD_H - 20
        love.graphics.setColor(1,1,1)
        love.graphics.print("Selected: "..#selected.cards.." card(s)", x, start_y - 18)
        for i=1,#selected.cards do
            local c = selected.cards[i]
            local drawY = start_y + (i-1)*20
            c:draw(x, drawY, CARD_W, CARD_H, fonts.small)
        end
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    -- click tableau piles
    for i = 1, #state.tableau do
        local px, py = cursorToXY("tableau", i)
        local w,h = CARD_W, CARD_H + math.max(0, (#state.tableau[i]-1)*20)
        if x >= px and x <= px + w and y >= py and y <= py + h then
            if selected then
                if placeOntoPile("tableau", i, selected) then
                    selected = nil
                else
                    pushSeq(state.tableau[selected.index], selected.cards)
                    selected = nil
                end
            else
                local pile = state.tableau[i]
                local pickupIdx = findPickupIndex(pile)
                if pickupIdx then
                    local seq = {}
                    for j = pickupIdx, #pile do table.insert(seq, pile[j]) end
                    for _ = pickupIdx, #pile do table.remove(pile) end
                    selected = { pileType="tableau", index=i, cards=seq, absIndex=pickupIdx }
                end
            end
            return
        end
    end
    -- click stock
    local sx, sy = cursorToXY("stock", 1)
    if x >= sx and x <= sx + CARD_W and y >= sy and y <= sy + CARD_H then
        dealFromStock()
    end
end

function love.keypressed(key)
    -- navigation
    if Input.is("left", key) then
        if cursor.area == "tableau" then
            cursor.index = math.max(1, cursor.index - 1)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            cursor.cardIndex = (nFaceUp > 0) and math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp) or 0
        else
            cursor.area = "stock"
            cursor.index = 1
            cursor.cardIndex = 0
        end
        return
    end

    if Input.is("right", key) then
        if cursor.area == "tableau" then
            cursor.index = math.min(NUM_TABLEAU, cursor.index + 1)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            cursor.cardIndex = (nFaceUp > 0) and math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp) or 0
        else
            cursor.area = "tableau"
            cursor.index = 1
            local pile = state.tableau[cursor.index]
            cursor.cardIndex = faceUpCount(pile)
        end
        return
    end

    if Input.is("down", key) then
        if cursor.area == "tableau" then
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp > 0 then
                cursor.cardIndex = math.min(nFaceUp, (cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp) + 1)
            end
        else
            cursor.area = "tableau"
            cursor.index = 1
            local pile = state.tableau[cursor.index]
            cursor.cardIndex = faceUpCount(pile)
        end
        return
    end

    if Input.is("up", key) then
        if cursor.area == "tableau" then
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 or cursor.cardIndex <= 1 then
                cursor.area = "stock"
                cursor.index = 1
                cursor.cardIndex = 0
            else
                cursor.cardIndex = math.max(1, cursor.cardIndex - 1)
            end
        else
            cursor.area = "stock"
            cursor.index = 1
            cursor.cardIndex = 0
        end
        return
    end

    -- undo / redo
    if Input.is("undo", key) then
        local prev = undo:undo(state)
        if prev then
            state = prev
            selected = nil
            cursor.area = "stock"
            cursor.index = 1
            cursor.cardIndex = 0
        end
        return
    elseif Input.is("redo", key) then
        local nextState = undo:redo(state)
        if nextState then
            state = nextState
            selected = nil
            cursor.area = "stock"
            cursor.index = 1
            cursor.cardIndex = 0
        end
        return
    end

    -- select / deselect
    if Input.is("select", key) then
        if selected then
            if selected.pileType == "tableau" then
                pushSeq(state.tableau[selected.index], selected.cards)
            end
            selected = nil
            return
        else
            if cursor.area == "tableau" then
                local pile = state.tableau[cursor.index]
                local nFaceUp = faceUpCount(pile)
                if nFaceUp == 0 then
                    state.msg = "No face-up cards to select here."
                    return
                end
                local pos = cursor.cardIndex
                if pos == 0 then pos = nFaceUp end
                undo:push(state)
                local p = pickupFromPile("tableau", cursor.index, pos)
                if p then
                    selected = p
                else
                    undo:undo(state)
                    state.msg = "Failed to pick up stack."
                end
            end
            return
        end
    end

    -- move/place or draw
    if Input.is("move", key) then
        if selected then
            if cursor.area == "tableau" then
                if placeOntoPile("tableau", cursor.index, selected) then
                    selected = nil
                else
                    pushSeq(state.tableau[selected.index], selected.cards)
                    selected = nil
                    state.msg = "Illegal move."
                end
            else
                pushSeq(state.tableau[selected.index], selected.cards)
                selected = nil
            end
        else
            if cursor.area == "stock" then
                dealFromStock()
            else
                state.msg = "Nothing selected to move."
            end
        end
        return
    end

    -- autofound
    if Input.is("autofound", key) then
        if cursor.area == "tableau" then
            if removeCompleteToFoundation(cursor.index) then
                -- success
            else
                state.msg = "No complete 13-card same-suit sequence at this pile."
            end
        end
        return
    end

    if Input.is("restart", key) then
        newGame(state.suitsMode)
        cursor = { area = "stock", index = 1, cardIndex = 0 }
        selected = nil
        return
    end
end

function love.update(dt)
    -- nothing needed for now
end
