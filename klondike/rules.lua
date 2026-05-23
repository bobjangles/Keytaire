local Rules = {}

function Rules.getTopOfPile(pile)
    return pile[#pile]
end

function Rules.isBuildDescendingAlt(c1, c2)
    -- c1 can be placed on c2: rank one lower and opposite color
    if not c1 or not c2 then return false end
    return (c1.rankIndex + 1 == c2.rankIndex) and (c1:isRed() ~= c2:isRed())
end

function Rules.canMoveSequenceToTableau(seq, destPile)
    if #seq == 0 then return false end
    local top = Rules.getTopOfPile(destPile)
    if not top then
        -- only a King can be placed on empty
        return seq[1].rankIndex == 13
    else
        return Rules.isBuildDescendingAlt(seq[1], top)
    end
end

function Rules.canMoveToFoundation(card, foundationPile)
    if not card then return false end
    local top = Rules.getTopOfPile(foundationPile)
    if not top then
        return card.rankIndex == 1 -- Ace
    else
        return (card.suit == top.suit) and (card.rankIndex == top.rankIndex + 1)
    end
end

return Rules
