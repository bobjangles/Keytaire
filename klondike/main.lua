-- NOTE: To change your physical audio file paths, open `audio_manager.lua` 
-- and update the `soundFiles` table inside the `AudioManager.init()` function.
-- The keys ("place1", "place2", "slide1", "slide8", "shove") are used below to trigger them.

local AudioManager = require "audio_manager"
local Deck = require "deck"
local Card = require "card"
local Input = require "input"
local Rules = require "rules"
local ImageCache = require "card_images"
local Undo = require "undo"
local Shaders = require "shaders"
local TLfres = require "tlfres" 

local GAME_W = 1280
local GAME_H = 720
local CARD_W = 100
local CARD_H = 140
local PADDING = 20
local TABLEAU_SPACING = 30
local UI_TOP = 20
local UI_LEFT = 20

local state = {}
local fonts = {}
local bgImage = nil

local cursor = {
    area = "stock", 
    index = 1, 
    cardIndex = 0,
}

local selected = nil 
local undo = Undo.new(500)

local function newGame()
    local deck = Deck.newDeck()
    Deck.shuffle(deck)

    local foundations = { {}, {}, {}, {} }
    local tableau = {}
    for i=1,7 do tableau[i] = {} end
    local stock = {}
    local waste = {}

    for i=1,7 do
        for j=1,i do
            local c = table.remove(deck)
            c.faceUp = (j == i)
            table.insert(tableau[i], c)
        end
    end

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

    undo:clear()
end

local function drawTextCentered(text, x, y, w)
    local font = fonts.small
    local sw = font:getWidth(text)
    love.graphics.setFont(font)
    love.graphics.print(text, x + (w - sw)/2, y)
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
        for i = absIndex, #pile do
            table.insert(seq, pile[i])
        end
        for _ = 1, #seq do
            table.remove(pile)
        end
        return {pileType="tableau", index=idx, cards=seq, absIndex=absIndex}
    elseif area == "waste" then
        local pile = state.waste
        if #pile == 0 then return nil end
        return {pileType="waste", index=1, cards={table.remove(pile)}}
    elseif area == "foundation" then
        local pile = state.foundations[idx]
        if #pile == 0 then return nil end
        return {pileType="foundation", index=idx, cards={table.remove(pile)}}
    elseif area == "stock" then
        return nil
    end
    return nil
end

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
        if Rules.canMoveSequenceToTableau(pickup.cards, dest) then
            for _,c in ipairs(pickup.cards) do table.insert(dest, c) end
            flipOriginIfNeeded(pickup)
            return true
        end
    elseif area == "foundation" then
        if #pickup.cards ~= 1 then return false end
        local dest = state.foundations[idx]
        if Rules.canMoveToFoundation(pickup.cards[1], dest) then
            table.insert(dest, pickup.cards[1])
            flipOriginIfNeeded(pickup)
            return true
        end
    end
    return false
end

local function drawFromStock()
    if #state.stock == 0 then
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

local function anyFaceDownInTableau()
    for i = 1, 7 do
        for j = 1, #state.tableau[i] do
            if not state.tableau[i][j].faceUp then return true end
        end
    end
    return false
end

local function tryMoveWasteTopToFoundation()
    if #state.waste == 0 then return false end
    local card = Rules.getTopOfPile(state.waste)
    if not card then return false end
    for i = 1, 4 do
        if Rules.canMoveToFoundation(card, state.foundations[i]) then
            table.insert(state.foundations[i], table.remove(state.waste))
            return true
        end
    end
    return false
end

local function tryMoveTableauTopToFoundation()
    for i = 1, 7 do
        local pile = state.tableau[i]
        if #pile > 0 then
            local top = pile[#pile]
            if top.faceUp then
                for f = 1, 4 do
                    if Rules.canMoveToFoundation(top, state.foundations[f]) then
                        table.remove(pile)
                        table.insert(state.foundations[f], top)
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

local function autoMoveAllFaceUpToFoundations()
    if anyFaceDownInTableau() then return end
    local moved = true
    while moved do
        moved = false
        if tryMoveWasteTopToFoundation() then moved = true
        elseif tryMoveTableauTopToFoundation() then moved = true end
    end
end

local function checkAndSetWin()
    autoMoveAllFaceUpToFoundations()
    local total = 0
    for i=1,7 do total = total + #state.tableau[i] end
    if total == 0 and not state.win then
        state.win = true
        state.winTimer = 3.0
        state.winMessage = "You win!"
    end
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    fonts.small = love.graphics.newFont(14)
    fonts.big = love.graphics.newFont(20)

    local ok, img = pcall(function() return love.graphics.newImage("PNG/Texturelabs_Fabric_184M.jpg") end)
    if ok and img then bgImage = img else bgImage = nil end

    AudioManager.init()

    newGame()
end

local function cursorToXY(a, i)
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

local function moveToFarRight()
    if cursor.area == "tableau" then
        cursor.index = 7
        local nFaceUp = faceUpCount(state.tableau[cursor.index])
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
        local nFaceUp = faceUpCount(state.tableau[cursor.index])
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
    cursor.index = math.min(7, cursor.index)
    local nFaceUp = faceUpCount(state.tableau[cursor.index])
    cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
end

function love.keypressed(key)
    if key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        return
    end

    if key == "escape" then
        love.event.quit()
        return
    end

    local isShift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local action = Input.getAction(key, isShift, love.timer.getTime())

    if not action then return end

    -- Handle Vim Combo Motions
    if action == "bottomRow" then moveToBottomRow(); return end
    if action == "farRight" then moveToFarRight(); return end
    if action == "farLeft" then moveToFarLeft(); return end
    if action == "topRow" then moveToTopRow(); return end

    -- History
    if action == "undo" then
        local prev = undo:undo(state)
        if prev then 
            state = prev; selected = nil; clampCursor(); checkAndSetWin() 
            AudioManager.play("slide8") -- AUDIO: Satisfying rustle for undo
        end
        return
    elseif action == "redo" then
        local nextState = undo:redo(state)
        if nextState then 
            state = nextState; selected = nil; clampCursor(); checkAndSetWin()
            AudioManager.play("slide8") -- AUDIO: Satisfying rustle for redo
        end
        return
    end

    -- Normal Navigation
    if action == "left" then
        if cursor.area == "tableau" then
            cursor.index = math.max(1, cursor.index - 1)
            local nFaceUp = faceUpCount(state.tableau[cursor.index])
            cursor.cardIndex = nFaceUp == 0 and 0 or math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp)
        else
            if cursor.area == "foundation" then
                if cursor.index > 1 then cursor.index = cursor.index - 1 else cursor.area = "waste"; cursor.index = 1 end
            elseif cursor.area == "waste" then cursor.area = "stock"; cursor.index = 1 end
        end
    elseif action == "right" then
        if cursor.area == "tableau" then
            cursor.index = math.min(7, cursor.index + 1)
            local nFaceUp = faceUpCount(state.tableau[cursor.index])
            cursor.cardIndex = nFaceUp == 0 and 0 or math.min(cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp, nFaceUp)
        else
            if cursor.area == "stock" then cursor.area = "waste"
            elseif cursor.area == "waste" then cursor.area = "foundation"; cursor.index = 1
            elseif cursor.area == "foundation" then cursor.index = math.min(4, cursor.index + 1) end
        end
    elseif action == "down" then
        if cursor.area == "tableau" then
            local nFaceUp = faceUpCount(state.tableau[cursor.index])
            if nFaceUp > 0 then cursor.cardIndex = math.min(nFaceUp, (cursor.cardIndex > 0 and cursor.cardIndex or nFaceUp) + 1) end
        else
            cursor.area = "tableau"; cursor.index = 1
            local nFaceUp = faceUpCount(state.tableau[cursor.index])
            cursor.cardIndex = nFaceUp > 0 and nFaceUp or 0
        end
    elseif action == "up" then
        if cursor.area == "tableau" then
            local nFaceUp = faceUpCount(state.tableau[cursor.index])
            if nFaceUp == 0 or cursor.cardIndex <= 1 then
                cursor.area = "stock"; cursor.index = 1; cursor.cardIndex = 0
            else
                cursor.cardIndex = math.max(1, cursor.cardIndex - 1)
            end
        else
            cursor.area = "stock"; cursor.index = 1; cursor.cardIndex = 0
        end
    elseif action == "select" then
        if selected then
            local origin = selected
            if origin.pileType == "tableau" then
                for _,c in ipairs(origin.cards) do table.insert(state.tableau[origin.index], c) end
            elseif origin.pileType == "waste" then
                for _,c in ipairs(origin.cards) do table.insert(state.waste, c) end
            elseif origin.pileType == "foundation" then
                for _,c in ipairs(origin.cards) do table.insert(state.foundations[origin.index], c) end
            end
            selected = nil
            AudioManager.play("place1") -- AUDIO: Putting cards back down where they came from
        else
            undo:push(state)
            if cursor.area == "tableau" then
                if faceUpCount(state.tableau[cursor.index]) == 0 then 
                    undo:undo(state)
                    AudioManager.play("shove") -- AUDIO: Tried to pick up empty/facedown pile
                    return 
                end
                selected = pickupFromPile("tableau", cursor.index, cursor.cardIndex)
            else
                selected = pickupFromPile(cursor.area, cursor.index)
                if not selected then 
                    undo:undo(state)
                    AudioManager.play("shove") -- AUDIO: Tried to pick up empty pile
                end
            end
            if selected then AudioManager.play("slide1") end -- AUDIO: Successfully picked up card(s)
        end
    elseif action == "move" then
        if selected then
            if placeOntoPile(cursor.area, cursor.index, selected) then
                selected = nil; checkAndSetWin()
                AudioManager.play("place2") -- AUDIO: Successfully moved cards to new pile
            else
                local origin = selected
                if origin.pileType == "tableau" then
                    for _,c in ipairs(origin.cards) do table.insert(state.tableau[origin.index], c) end
                elseif origin.pileType == "waste" then
                    for _,c in ipairs(origin.cards) do table.insert(state.waste, c) end
                elseif origin.pileType == "foundation" then
                    for _,c in ipairs(origin.cards) do table.insert(state.foundations[origin.index], c) end
                end
                selected = nil
                AudioManager.play("shove") -- AUDIO: Invalid move, sent back
            end
        else
            if cursor.area == "stock" then
                undo:push(state); drawFromStock(); checkAndSetWin()
                AudioManager.play("slide8") -- AUDIO: Draw from stock to waste
            elseif cursor.area == "tableau" then
                undo:push(state)
                if faceUpCount(state.tableau[cursor.index]) == 0 then 
                    undo:undo(state)
                    AudioManager.play("shove") 
                    return 
                end
                local p = pickupFromPile("tableau", cursor.index, cursor.cardIndex)
                if p and #p.cards == 1 then
                    local moved = false
                    for i=1,4 do
                        if Rules.canMoveToFoundation(p.cards[1], state.foundations[i]) then
                            table.insert(state.foundations[i], p.cards[1])
                            moved = true; break
                        end
                    end
                    if not moved then
                        for _,c in ipairs(p.cards) do table.insert(state.tableau[cursor.index], c) end
                        undo:undo(state)
                        AudioManager.play("shove") -- AUDIO: Auto-move rejected (no valid foundation)
                    else
                        flipOriginIfNeeded(p); checkAndSetWin()
                        AudioManager.play("place2") -- AUDIO: Auto-moved single card to foundation
                    end
                elseif p then
                    for _,c in ipairs(p.cards) do table.insert(state.tableau[cursor.index], c) end
                    undo:undo(state)
                    AudioManager.play("shove") -- AUDIO: Can't auto-move a stack to foundation
                else
                    undo:undo(state)
                    AudioManager.play("shove")
                end
            elseif cursor.area == "waste" then
                if #state.waste == 0 then return end
                undo:push(state)
                local card = Rules.getTopOfPile(state.waste)
                if card then
                    local moved = false
                    for i=1,4 do
                        if Rules.canMoveToFoundation(card, state.foundations[i]) then
                            table.insert(state.foundations[i], table.remove(state.waste))
                            moved = true; break
                        end
                    end
                    if not moved then
                        for i=1,7 do
                            if Rules.canMoveSequenceToTableau({card}, state.tableau[i]) then
                                table.insert(state.tableau[i], table.remove(state.waste))
                                moved = true; break
                            end
                        end
                    end
                    if not moved then 
                        undo:undo(state)
                        AudioManager.play("shove") -- AUDIO: Waste card had nowhere to go
                    else 
                        checkAndSetWin()
                        AudioManager.play("place2") -- AUDIO: Waste card found a home
                    end
                else
                    undo:undo(state)
                end
            end
        end
    elseif action == "restart" then
        newGame()
        AudioManager.play("slide8") -- AUDIO: Shuffling the deck for a new game
    elseif action == "autofound" then
        if selected and #selected.cards == 1 then
            local card = selected.cards[1]
            for i=1,4 do
                if Rules.canMoveToFoundation(card, state.foundations[i]) then
                    table.insert(state.foundations[i], card)
                    flipOriginIfNeeded(selected)
                    selected = nil
                    checkAndSetWin()
                    AudioManager.play("place2") -- AUDIO: Autofound placed card successfully
                    return
                end
            end
            AudioManager.play("shove") -- AUDIO: Autofound failed to place card
        end
    end
end

function love.update(dt)
    if state.win and state.winTimer > 0 then
        state.winTimer = state.winTimer - dt
        if state.winTimer <= 0 then state.winTimer = 0 end
    end
end

function love.draw()
    TLfres.beginRendering(GAME_W, GAME_H)

    love.graphics.setShader(Shaders.feltGradient)
    if bgImage then
        love.graphics.draw(bgImage,0,0,0, GAME_W / bgImage:getWidth(), GAME_H / bgImage:getHeight())
    else
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
    end
    love.graphics.setShader()

    local dt = love.timer.getDelta()

    -- 1. Draw Stock
    local sx, sy = cursorToXY("stock", 1)
    if #state.stock == 0 then
        love.graphics.setColor(0.18, 0.18, 0.18)
        love.graphics.rectangle("line", sx, sy, CARD_W, CARD_H, 6)
        drawTextCentered("Empty", sx, sy + CARD_H/2 - 8, CARD_W)
    else
        for _, card in ipairs(state.stock) do card:update(dt, sx, sy) end
        state.stock[#state.stock]:draw(state.stock[#state.stock].x, state.stock[#state.stock].y, CARD_W, CARD_H)
    end

    -- 2. Draw Waste
    local wx, wy = cursorToXY("waste", 1)
    if #state.waste == 0 then
        love.graphics.setColor(0.18, 0.18, 0.18)
        love.graphics.rectangle("line", wx, wy, CARD_W, CARD_H, 6)
        drawTextCentered("Waste", wx, wy + CARD_H/2 - 8, CARD_W)
    else
        for i, card in ipairs(state.waste) do
            card:update(dt, wx, wy)
            if i == #state.waste then card:draw(card.x, card.y, CARD_W, CARD_H) end
        end
    end

    -- 3. Draw Foundations
    for i = 1, 4 do
        local fx, fy = cursorToXY("foundation", i)
        local pile = state.foundations[i]
        if #pile == 0 then
            love.graphics.setColor(0.18, 0.18, 0.18)
            love.graphics.rectangle("line", fx, fy, CARD_W, CARD_H, 6)
            drawTextCentered("Base", fx, fy + CARD_H/2 - 8, CARD_W)
        else
            for _, card in ipairs(pile) do card:update(dt, fx, fy) end
            pile[#pile]:draw(pile[#pile].x, pile[#pile].y, CARD_W, CARD_H)
        end
    end

    -- 4. Draw Tableau
    for i = 1, 7 do
        local tx, ty = cursorToXY("tableau", i)
        local pile = state.tableau[i]
        if #pile == 0 then
            love.graphics.setColor(0.18, 0.18, 0.18)
            love.graphics.rectangle("line", tx, ty, CARD_W, CARD_H, 6)
            drawTextCentered("Empty", tx, ty + CARD_H/2 - 8, CARD_W)
        else
            for j, card in ipairs(pile) do
                card:update(dt, tx, ty + (j - 1) * 20)
                card:draw(card.x, card.y, CARD_W, CARD_H)
            end
        end

        if cursor.area == "tableau" and cursor.index == i then
            love.graphics.setColor(1, 1, 0, 0.2)
            love.graphics.rectangle("line", tx - 4, ty - 4, CARD_W + 8, CARD_H + math.max(0, (#pile - 1) * 20) + 8, 8)
            local nFaceUp = faceUpCount(pile)
            if nFaceUp > 0 and cursor.cardIndex > 0 then
                local absIndex = faceUpPosToAbsolute(pile, cursor.cardIndex)
                if absIndex then
                    local cardAtCursor = pile[absIndex]
                    love.graphics.setColor(1, 1, 0, 0.9)
                    love.graphics.setLineWidth(3)
                    love.graphics.rectangle("line", tx - 6, cardAtCursor.y - 6, CARD_W + 12, CARD_H + (#pile - absIndex) * 20 + 12, 8)
                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    -- 5. Draw Selected Stack (Z-Indexed on top of Tableau)
    if selected then
        local sx = UI_LEFT
        local start_y = GAME_H - CARD_H - 20
        for i, card in ipairs(selected.cards) do
            card:update(dt, sx, start_y + (i-1)*20)
            card:draw(card.x, card.y, CARD_W, CARD_H, true)
        end
    end

    -- 6. Global Cursor
    if cursor.area ~= "tableau" then
        local cx, cy = cursorToXY(cursor.area, cursor.index)
        love.graphics.setColor(1, 1, 0, 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", cx - 4, cy - 4, CARD_W + 8, CARD_H + 8, 8)
        love.graphics.setLineWidth(1)
    end

    TLfres.endRendering()
end
