-- (updated main.lua with undo/redo selection/move fix)
local Deck = require "deck"
local Card = require "card"
local Input = require "input"
local ImageCache = require "card_images"
local Undo = require "undo"

local CARD_W = 100
local CARD_H = 140
local PADDING = 20
local TABLEAU_SPACING = 30
local UI_TOP = 20
local UI_LEFT = 20

local state = {}
local fonts = {}

-- background image (loaded in love.load)
local bgImage = nil

local cursor = {
    area = "stock", -- "stock","waste","foundation","tableau"
    index = 1, -- for foundation (1..4) or tableau (1..7)
    -- when area == "tableau", cardIndex is the index among face-up cards (1..nFaceUp).
    -- If cardIndex == 0, there are no face-up cards in that pile (navigation ignores them).
    cardIndex = 0,
}

local selected = nil -- { pileType="tableau"/"foundation"/"waste", index=..., cards={...}, absIndex=... }

-- For detecting quick key sequences (gg)
local lastKey = nil
local lastKeyTime = 0
local SEQ_TIMEOUT = 0.5 -- seconds for double-press sequences

-- Undo manager (keeps snapshots)
local undo = Undo.new(500)

local function newGame()
    -- create deck, shuffle, deal
    local deck = Deck.newDeck()
    Deck.shuffle(deck)

    -- piles
    local foundations = { {}, {}, {}, {} }
    local tableau = {}
    for i=1,7 do
        tableau[i] = {}
    end
    local stock = {}
    local waste = {}

    -- deal to tableau: 1..7 piles, with i cards in pile i
    for i=1,7 do
        for j=1,i do
            local c = table.remove(deck)
            c.faceUp = (j == i)
            table.insert(tableau[i], c)
        end
    end

    -- rest to stock
    while #deck > 0 do
        local c = table.remove(deck)
        c.faceUp = false
        table.insert(stock, c)
    end

    state = {
        stock = stock,
        waste = waste,
        foundations = foundations,
        tableau = tableau,
        win = false,
        winTimer = 0,
        winMessage = nil,
    }

    cursor.area = "stock"
    cursor.index = 1
    cursor.cardIndex = 0
    selected = nil

    -- clear undo history on new game
    undo:clear()
end

local function drawTextCentered(text, x, y, w)
    local font = fonts.small
    local sw = font:getWidth(text)
    love.graphics.setFont(font)
    love.graphics.print(text, x + (w - sw)/2, y)
end


local function getTopOfPile(pile)
    return pile[#pile]
end

local function isBuildDescendingAlt(c1, c2)
    -- c1 can be placed on c2: rank one lower and opposite color
    if not c1 or not c2 then return false end
    return (c1.rankIndex + 1 == c2.rankIndex) and (c1:isRed() ~= c2:isRed())
end

local function canMoveSequenceToTableau(seq, destPile)
    if #seq == 0 then return false end
    local top = getTopOfPile(destPile)
    if not top then
        -- only a King can be placed on empty
        return seq[1].rankIndex == 13
    else
        return isBuildDescendingAlt(seq[1], top)
    end
end

local function canMoveToFoundation(card, foundationPile)
    if not card then return false end
    local top = getTopOfPile(foundationPile)
    if not top then
        return card.rankIndex == 1 -- Ace
    else
        return (card.suit == top.suit) and (card.rankIndex == top.rankIndex + 1)
    end
end

-- Helpers to work with face-up ranges
local function firstFaceUpIndex(pile)
    for i = 1, #pile do
        if pile[i].faceUp then
            return i
        end
    end
    return nil
end

local function faceUpCount(pile)
    local first = firstFaceUpIndex(pile)
    if not first then return 0 end
    return #pile - first + 1
end

-- Convert a face-up position (1..nFaceUp) to the absolute pile index.
-- Returns nil if invalid or no face-up cards.
local function faceUpPosToAbsolute(pile, pos)
    local first = firstFaceUpIndex(pile)
    if not first then return nil end
    if pos < 1 then return nil end
    local abs = first + pos - 1
    if abs > #pile then return nil end
    return abs
end

-- NOTE: pickupFromPile no longer flips the new top card on the origin pile.
-- Flipping will only occur after a successful placement.
-- Supports selecting a sub-sequence in tableau by providing faceUpPos.
local function pickupFromPile(area, idx, faceUpPos)
    if area == "tableau" then
        local pile = state.tableau[idx]
        if #pile == 0 then return nil end
        local nFaceUp = faceUpCount(pile)
        if nFaceUp == 0 then return nil end
        -- faceUpPos defaults to topmost face-up card (nFaceUp)
        faceUpPos = faceUpPos or nFaceUp
        local absIndex = faceUpPosToAbsolute(pile, faceUpPos)
        if not absIndex then return nil end
        -- ensure the targeted card is faceUp (it should be by construction)
        if not pile[absIndex].faceUp then return nil end
        -- pick up the sequence from absIndex .. #pile
        local seq = {}
        for i = absIndex, #pile do
            table.insert(seq, pile[i])
        end
        -- remove them from the pile (from the end)
        for _ = 1, #seq do
            table.remove(pile)
        end
        -- return pickup with absolute index so placement/flip logic can reference the origin
        return {pileType="tableau", index=idx, cards=seq, absIndex=absIndex}
    elseif area == "waste" then
        local pile = state.waste
        if #pile == 0 then return nil end
        local card = table.remove(pile)
        return {pileType="waste", index=1, cards={card}}
    elseif area == "foundation" then
        local pile = state.foundations[idx]
        if #pile == 0 then return nil end
        local card = table.remove(pile)
        return {pileType="foundation", index=idx, cards={card}}
    elseif area == "stock" then
        -- no pickup; use Enter to draw
        return nil
    end
    return nil
end

-- Helper to flip the new top card of an origin tableau after a successful move.
local function flipOriginIfNeeded(pickup)
    if pickup and pickup.pileType == "tableau" then
        local origin = state.tableau[pickup.index]
        if #origin > 0 and not origin[#origin].faceUp then
            origin[#origin].faceUp = true
        end
    end
end

local function placeOntoPile(area, idx, pickup)
    if not pickup or #pickup.cards == 0 then return false end
    if area == "tableau" then
        local dest = state.tableau[idx]
        if canMoveSequenceToTableau(pickup.cards, dest) then
            for _,c in ipairs(pickup.cards) do
                table.insert(dest, c)
            end
            -- successful placement: flip origin top if it was a tableau pickup
            flipOriginIfNeeded(pickup)
            return true
        end
    elseif area == "foundation" then
        if #pickup.cards ~= 1 then return false end
        local dest = state.foundations[idx]
        if canMoveToFoundation(pickup.cards[1], dest) then
            table.insert(dest, pickup.cards[1])
            -- successful placement: flip origin top if it was a tableau pickup
            flipOriginIfNeeded(pickup)
            return true
        end
    elseif area == "waste" then
        -- not allowed to place onto waste
        return false
    elseif area == "stock" then
        return false
    end
    return false
end

local function drawFromStock()
    if #state.stock == 0 then
        -- recycle waste back to stock
        while #state.waste > 0 do
            local c = table.remove(state.waste)
            c.faceUp = false
            table.insert(state.stock, c)
        end
        return
    end
    local c = table.remove(state.stock)
    c.faceUp = true
    table.insert(state.waste, c)
end

-- Adjust cursor after state restore so indices are valid
local function clampCursor()
    if cursor.area == "tableau" then
        if not cursor.index or cursor.index < 1 then cursor.index = 1 end
        cursor.index = math.min(7, cursor.index)
        local pile = state.tableau[cursor.index]
        local nFaceUp = faceUpCount(pile)
        cursor.cardIndex = nFaceUp > 0 and math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp) or 0
    elseif cursor.area == "foundation" then
        if not cursor.index or cursor.index < 1 then cursor.index = 1 end
        cursor.index = math.min(4, cursor.index)
        cursor.cardIndex = 0
    else
        cursor.index = 1
        cursor.cardIndex = 0
    end
end

-- NEW HELPERS
-- return true if any card in tableau piles is face-down
local function anyFaceDownInTableau()
    for i = 1, 7 do
        local pile = state.tableau[i]
        for j = 1, #pile do
            if not pile[j].faceUp then
                return true
            end
        end
    end
    return false
end

-- Try to move top of waste to any foundation. Return true if moved.
local function tryMoveWasteTopToFoundation()
    if #state.waste == 0 then return false end
    local card = getTopOfPile(state.waste)
    if not card then return false end
    for i = 1, 4 do
        if canMoveToFoundation(card, state.foundations[i]) then
            table.insert(state.foundations[i], table.remove(state.waste))
            return true
        end
    end
    return false
end

-- Try to move top card from any tableau pile to any foundation. Return true if moved.
local function tryMoveTableauTopToFoundation()
    for i = 1, 7 do
        local pile = state.tableau[i]
        if #pile > 0 then
            local top = pile[#pile]
            if top.faceUp then
                for f = 1, 4 do
                    if canMoveToFoundation(top, state.foundations[f]) then
                        table.remove(pile) -- remove top
                        table.insert(state.foundations[f], top)
                        -- flip new top if needed
                        if #pile > 0 and not pile[#pile].faceUp then
                            pile[#pile].faceUp = true
                        end
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- If all tableau cards are face-up, repeatedly move available top cards to foundations
-- until no more legal moves are possible. This helps auto-complete the game when only face-up
-- cards remain.
local function autoMoveAllFaceUpToFoundations()
    -- only run when there are no face-down cards in tableau
    if anyFaceDownInTableau() then return end

    local moved = true
    while moved do
        moved = false
        -- prefer moving waste first (common rule)
        if tryMoveWasteTopToFoundation() then
            moved = true
        else
            if tryMoveTableauTopToFoundation() then
                moved = true
            end
        end
    end
end

-- Check win condition: no cards in bottom area (tableau). Set a short timer and message.
-- Also, if all cards in tableau are face-up, auto-move them into foundations when possible.
local function checkAndSetWin()
    -- If all cards are face-up, attempt to auto-move them to foundations.
    autoMoveAllFaceUpToFoundations()

    local total = 0
    for i=1,7 do
        total = total + #state.tableau[i]
    end
    if total == 0 and not state.win then
        state.win = true
        state.winTimer = 3.0 -- seconds
        state.winMessage = "You win!"
    end
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    fonts.small = love.graphics.newFont(14)
    fonts.big = love.graphics.newFont(20)

    -- load background image (safe: won't error if missing)
    local ok, img = pcall(function() return love.graphics.newImage("PNG/Texturelabs_Fabric_184M.jpg") end)
    if ok and img then
        bgImage = img
    else
        bgImage = nil
        -- optional: print an informative message to the console for debugging
        print("Warning: background image PNG/Texturelabs_Fabric_184M.jpg not found or failed to load; using solid background color.")
    end

    newGame()
end

local function cursorToXY(a, i)
    -- return x,y for top-left of the pile for drawing and hit area
    local W = love.graphics.getWidth()
    -- stock and waste at left top
    if a == "stock" then
        return UI_LEFT, UI_TOP, CARD_W, CARD_H
    elseif a == "waste" then
        return UI_LEFT + CARD_W + 12, UI_TOP, CARD_W, CARD_H
    elseif a == "foundation" then
        local start = UI_LEFT + 350
        return start + (i-1)*(CARD_W+12), UI_TOP, CARD_W, CARD_H
    elseif a == "tableau" then
        local startY = UI_TOP + CARD_H + 60
        local startX = UI_LEFT
        return startX + (i-1)*(CARD_W + TABLEAU_SPACING), startY, CARD_W, CARD_H
    end
end

-- draw selected cards in the bottom-left of the screen
local function drawSelectedAtBottomLeft()
    if not selected then return end
    local x = UI_LEFT
    local margin_bottom = 20
    local screen_h = love.graphics.getHeight()
    -- start so cards sit above the bottom margin
    local start_y = screen_h - CARD_H - margin_bottom
    for i=1,#selected.cards do
        local c = selected.cards[i]
        local drawY = start_y + (i-1)*20
        c:draw(x, drawY, CARD_W, CARD_H, fonts.small)
    end
end

-- helper moves for vim motions
local function moveToFarRight()
    if cursor.area == "tableau" then
        cursor.index = 7
        local pile = state.tableau[cursor.index]
        local nFaceUp = faceUpCount(pile)
        cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
    else
        cursor.area = "foundation"
        cursor.index = 4
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
    -- move to tableau area; keep current column if possible
    cursor.area = "tableau"
    if not cursor.index or cursor.index < 1 then cursor.index = 1 end
    cursor.index = math.min(7, cursor.index)
    local pile = state.tableau[cursor.index]
    local nFaceUp = faceUpCount(pile)
    cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
end

function love.keypressed(key)
    local now = love.timer.getTime()

    -- 1) Handle uppercase G (Shift+g) -> bottom row
    if key == "g" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        moveToBottomRow()
        lastKey = nil
        lastKeyTime = 0
        return
    end

    -- 2) Handle '$' — support "end" key, or Shift+4 as '$'
    local isDollar = false
    if key == "$" or key == "end" then
        isDollar = true
    elseif key == "4" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        isDollar = true
    end
    if isDollar then
        moveToFarRight()
        lastKey = nil
        lastKeyTime = 0
        return
    end

    -- 3) Handle '0' -> far left
    if key == "0" then
        moveToFarLeft()
        lastKey = nil
        lastKeyTime = 0
        return
    end

    -- 4) Handle 'gg' (double-press g within SEQ_TIMEOUT) -> top row
    if key == "g" and not (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        if lastKey == "g" and (now - lastKeyTime) <= SEQ_TIMEOUT then
            -- gg detected
            moveToTopRow()
            lastKey = nil
            lastKeyTime = 0
            return
        else
            -- record first 'g' and wait for a possible second
            lastKey = "g"
            lastKeyTime = now
            -- don't fall through to other movement handling on a single 'g'
            return
        end
    end

    -- clear sequence state for other keys
    lastKey = nil
    lastKeyTime = 0

    -- Undo / Redo handling (use Input bindings so they can be remapped)
    if Input.is("undo", key) then
        local prev = undo:undo(state)
        if prev then
            state = prev
            selected = nil
            clampCursor()
            checkAndSetWin()
        end
        return
    elseif Input.is("redo", key) then
        local nextState = undo:redo(state)
        if nextState then
            state = nextState
            selected = nil
            clampCursor()
            checkAndSetWin()
        end
        return
    end

    -- existing navigation handling (arrow/vim keys) and actions
    if Input.is("left", key) then
        if cursor.area == "tableau" then
            cursor.index = math.max(1, cursor.index - 1)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 then
                cursor.cardIndex = 0
            else
                cursor.cardIndex = math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp)
            end
        else
            -- move left in top row (stock->waste->foundations)
            if cursor.area == "foundation" then
                if cursor.index > 1 then
                    cursor.index = cursor.index - 1
                else
                    cursor.area = "waste"
                    cursor.index = 1
                end
            elseif cursor.area == "waste" then
                cursor.area = "stock"
                cursor.index = 1
            elseif cursor.area == "stock" then
                -- already at leftmost; do nothing
            end
        end
    elseif Input.is("right", key) then
        if cursor.area == "tableau" then
            cursor.index = math.min(7, cursor.index + 1)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 then
                cursor.cardIndex = 0
            else
                cursor.cardIndex = math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp)
            end
        else
            if cursor.area == "stock" then
                cursor.area = "waste"
            elseif cursor.area == "waste" then
                cursor.area = "foundation"
                cursor.index = 1
            elseif cursor.area == "foundation" then
                cursor.index = math.min(4, cursor.index + 1)
            end
        end
    elseif Input.is("down", key) then
        if cursor.area == "tableau" then
            -- move cursor "down" among face-up cards (toward deeper / later cards)
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp > 0 then
                cursor.cardIndex = math.min(nFaceUp, (cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp) + 1)
            end
        else
            -- move to tableau: set cardIndex to topmost face-up card (nFaceUp) or 0 if none
            cursor.area = "tableau"
            cursor.index = 1
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
        end
    elseif Input.is("up", key) then
        if cursor.area == "tableau" then
            local pile = state.tableau[cursor.index]
            local nFaceUp = faceUpCount(pile)
            if nFaceUp == 0 or cursor.cardIndex <= 1 then
                -- either no face-up cards or already at the topmost face-up: go to top row (stock)
                cursor.area = "stock"
                cursor.index = 1
                cursor.cardIndex = 0
            else
                -- move cursor "up" among face-up cards (toward earlier face-up)
                cursor.cardIndex = math.max(1, cursor.cardIndex - 1)
            end
        else
            -- move focus back to stock when up from top row
            cursor.area = "stock"
            cursor.index = 1
            cursor.cardIndex = 0
        end
    elseif Input.is("select", key) then
        if selected then
            -- deselect: put back to original pile
            local origin = selected
            if origin.pileType == "tableau" then
                local p = state.tableau[origin.index]
                for _,c in ipairs(origin.cards) do table.insert(p, c) end
            elseif origin.pileType == "waste" then
                for _,c in ipairs(origin.cards) do table.insert(state.waste, c) end
            elseif origin.pileType == "foundation" then
                for _,c in ipairs(origin.cards) do table.insert(state.foundations[origin.index], c) end
            end
            selected = nil
        else
            -- pick up from current cursor
            -- push snapshot BEFORE mutating state (so undo returns to original position)
            undo:push(state)
            if cursor.area == "tableau" then
                local pile = state.tableau[cursor.index]
                local nFaceUp = faceUpCount(pile)
                if nFaceUp == 0 then
                    -- nothing selectable in this pile (face-down only)
                    -- since nothing changed, pop the last undo entry to avoid empty history entries
                    undo:undo(state)
                    return
                end
                local p = pickupFromPile("tableau", cursor.index, cursor.cardIndex)
                if p then selected = p end
            else
                local p = pickupFromPile(cursor.area, cursor.index)
                if not p then
                    -- nothing picked; rollback the snapshot
                    undo:undo(state)
                    return
                end
                selected = p
            end
        end
    elseif Input.is("move", key) then
        if selected then
            -- selected exists: we already pushed the snapshot at selection time,
            -- so do NOT push again here (avoids splitting selection+place into two undo steps).
            -- attempt move to cursor location
            local ok = placeOntoPile(cursor.area, cursor.index, selected)
            if ok then
                selected = nil
                checkAndSetWin()
            else
                -- invalid move, return cards to origin
                local origin = selected
                if origin.pileType == "tableau" then
                    local p = state.tableau[origin.index]
                    for _,c in ipairs(origin.cards) do table.insert(p, c) end
                elseif origin.pileType == "waste" then
                    for _,c in ipairs(origin.cards) do table.insert(state.waste, c) end
                elseif origin.pileType == "foundation" then
                    for _,c in ipairs(origin.cards) do table.insert(state.foundations[origin.index], c) end
                end
                selected = nil
            end
        else
            -- no selection: if on stock, draw; if on waste or tableau, maybe try to auto move to foundation
            if cursor.area == "stock" then
                -- push snapshot before drawing
                undo:push(state)
                drawFromStock()
                checkAndSetWin()
            elseif cursor.area == "tableau" then
                -- pick up from the current face-up cursor.cardIndex and attempt auto to foundation if single card
                -- push snapshot before pickup/mutation
                undo:push(state)
                local pile = state.tableau[cursor.index]
                local nFaceUp = faceUpCount(pile)
                if nFaceUp == 0 then
                    -- nothing done, rollback snapshot
                    undo:undo(state)
                    return
                end
                local p = pickupFromPile("tableau", cursor.index, cursor.cardIndex)
                if p and #p.cards == 1 then
                    local card = p.cards[1]
                    -- try each foundation
                    local moved = false
                    for i=1,4 do
                        if canMoveToFoundation(card, state.foundations[i]) then
                            table.insert(state.foundations[i], card)
                            moved = true
                            break
                        end
                    end
                    if not moved then
                        -- put back
                        for _,c in ipairs(p.cards) do table.insert(state.tableau[cursor.index], c) end
                        -- nothing changed: rollback snapshot
                        undo:undo(state)
                    else
                        -- successful placement: flip origin top if needed
                        flipOriginIfNeeded(p)
                        checkAndSetWin()
                    end
                elseif p then
                    -- put back and rollback snapshot
                    for _,c in ipairs(p.cards) do table.insert(state.tableau[cursor.index], c) end
                    undo:undo(state)
                else
                    -- nothing picked; rollback
                    undo:undo(state)
                end
            elseif cursor.area == "waste" then
                -- attempt move top waste card to foundation or tableau
                if #state.waste == 0 then return end
                -- push snapshot before attempting moves
                undo:push(state)
                local card = getTopOfPile(state.waste)
                if card then
                    local moved = false
                    for i=1,4 do
                        if canMoveToFoundation(card, state.foundations[i]) then
                            table.insert(state.foundations[i], table.remove(state.waste))
                            moved = true
                            break
                        end
                    end
                    if not moved then
                        -- try tableau
                        for i=1,7 do
                            if canMoveSequenceToTableau({card}, state.tableau[i]) then
                                table.insert(state.tableau[i], table.remove(state.waste))
                                moved = true
                                break
                            end
                        end
                    end
                    if not moved then
                        -- nothing moved; rollback snapshot
                        undo:undo(state)
                    else
                        checkAndSetWin()
                    end
                else
                    undo:undo(state)
                end
            end
        end
    elseif Input.is("restart", key) then
        newGame()
    elseif Input.is("autofound", key) then
        -- Autofound is used when player has selected a single card and wants to move it to foundation
        if selected and #selected.cards == 1 then
            -- selected was created with a prior snapshot so do NOT push again here
            local card = selected.cards[1]
            for i=1,4 do
                if canMoveToFoundation(card, state.foundations[i]) then
                    table.insert(state.foundations[i], card)
                    -- successful placement: flip origin top if needed
                    flipOriginIfNeeded(selected)
                    selected = nil
                    checkAndSetWin()
                    return
                end
            end
        end
    elseif key == "escape" then
        love.event.quit()
    end
end

function love.update(dt)
    if state.win and state.winTimer and state.winTimer > 0 then
        state.winTimer = state.winTimer - dt
        if state.winTimer <= 0 then
            -- stop showing the message; keep win flag if desired
            state.winTimer = 0
            -- leave state.win = true so the game remains won; UI stops showing after timer
        end
    end
end

function love.draw()
    local Shaders = require "shaders"
    -- draw background image if available, otherwise fall back to the solid color
    if bgImage then
        local w, h = love.graphics.getDimensions()
        local iw, ih = bgImage:getWidth(), bgImage:getHeight()
        local sx, sy = w / iw, h / ih
        love.graphics.setColor(1,1,1)
        love.graphics.draw(bgImage, 0, 0, 0, sx, sy)
    else
        love.graphics.clear(0.12, 0.6, 0.2)
    end


    -- Draw stock
    local sx, sy = cursorToXY("stock", 1)
    if #state.stock > 0 then
        local backImg = ImageCache.getBackImage()
        if backImg then
            -- unsure why removing this for now: love.graphics.setColor(1,1,1)
            local scaleX = CARD_W / backImg:getWidth()
            local scaley =  CARD_H / backImg:getHeight()
            -- Shadow
            love.graphics.setShader(Shaders.dropShadow)
            love.graphics.draw(backImg, sx+3 , sy+3 , 0, scaleX, scaleY)
            love.graphics.setShader()
            -- Pile
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(backImg, sx, sy, 0, scaleX, scaleY)

        end
    else
        love.graphics.setColor(0.2,0.2,0.2)
        love.graphics.rectangle("line", sx, sy, CARD_W, CARD_H, 6)
        drawTextCentered("Empty", sx, sy+CARD_H/2-8, CARD_W)
    end
    -- highlight cursor
    if cursor.area == "stock" then
        love.graphics.setColor(1,1,0,0.9)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", sx-4, sy-4, CARD_W+8, CARD_H+8, 8)
        love.graphics.setLineWidth(1)
    end

    -- Draw waste
    local wx, wy = cursorToXY("waste", 1)
    if #state.waste > 0 then
        local top = getTopOfPile(state.waste)
        top:draw(wx,wy,CARD_W,CARD_H, fonts.small)
    else
        love.graphics.setColor(0.18,0.18,0.18)
        love.graphics.rectangle("line", wx, wy, CARD_W, CARD_H, 6)
        drawTextCentered("Waste", wx, wy+CARD_H/2-8, CARD_W)
    end
    if cursor.area == "waste" then
        love.graphics.setColor(1,1,0,0.9)
        love.graphics.rectangle("line", wx-4, wy-4, CARD_W+8, CARD_H+8, 8)
    end

    -- Foundations
    for i=1,4 do
        local fx, fy = cursorToXY("foundation", i)
        local pile = state.foundations[i]
        if #pile > 0 then
            getTopOfPile(pile):draw(fx,fy,CARD_W,CARD_H, fonts.small)
        else
            love.graphics.setColor(0.18,0.18,0.18)
            love.graphics.rectangle("line", fx, fy, CARD_W, CARD_H, 6)
            drawTextCentered("Foundation", fx, fy+CARD_H/2-8, CARD_W)
        end
        if cursor.area == "foundation" and cursor.index == i then
            love.graphics.setColor(1,1,0,0.9)
            love.graphics.rectangle("line", fx-4, fy-4, CARD_W+8, CARD_H+8, 8)
        end
    end

    -- Draw tableau
    for i=1,7 do
        local tx, ty = cursorToXY("tableau", i)
        local pile = state.tableau[i]
        if #pile == 0 then
            love.graphics.setColor(0.18,0.18,0.18)
            love.graphics.rectangle("line", tx, ty, CARD_W, CARD_H, 6)
            drawTextCentered("Empty", tx, ty+CARD_W/2-8, CARD_W)
        else
            for j=1,#pile do
                local c = pile[j]
                local drawY = ty + (j-1)*20
                c:draw(tx, drawY, CARD_W, CARD_H, fonts.small)
            end
        end

        -- highlight entire pile when cursor over it
        if cursor.area == "tableau" and cursor.index == i then
            love.graphics.setColor(1,1,0,0.3)
            love.graphics.rectangle("line", tx-4, ty-4, CARD_W, CARD_H+8 + math.max(0,(#pile-1)*20), 8)

            -- highlight the current targeted face-up card and cards underneath
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

    -- Draw selected cards in bottom-left
    if selected then
        -- small label above the drawn stack
        local sx = UI_LEFT
        local margin_bottom = 20
        local screen_h = love.graphics.getHeight()
        local start_y = screen_h - CARD_H - margin_bottom
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(1,1,1)
        love.graphics.print("Selected: "..#selected.cards.." card(s)", sx, start_y - 18)
        drawSelectedAtBottomLeft()
    end


    -- Win message (centered) while timer > 0
    if state.win and state.winTimer and state.winTimer > 0 then
        love.graphics.setFont(fonts.big)
        local msg = state.winMessage or "You win!"
        local w = love.graphics.getWidth()
        local h = love.graphics.getHeight()
        local tw = fonts.big:getWidth(msg)
        love.graphics.setColor(0,0,0,0.6)
        love.graphics.rectangle("fill", (w - tw)/2 - 20, 60 - 10, tw + 40, 50, 8)
        love.graphics.setColor(1,1,1)
        love.graphics.printf(msg, 0, 60, w, "center")
    end
end
