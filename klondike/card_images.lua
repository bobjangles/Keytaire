-- Caches loaded card images to avoid reloading
local ImageCache = {}
local imageCache = {}

-- Normalize image filenames
local function getImagePath(rank, suit)
    local suitMap = {s = "spades", h = "hearts", d = "diamonds", c = "clubs"}
    local rankMap = {
        A = "A", ["2"] = "02", ["3"] = "03", ["4"] = "04",
        ["5"] = "05", ["6"] = "06", ["7"] = "07", ["8"] = "08",
        ["9"] = "09", ["10"] = "10", J = "J", Q = "Q", K = "K"
    }
    local suitName = suitMap[suit] or suit
    local rankName = rankMap[rank] or rank
    return "PNG/Cards (large)/card_" .. suitName .. "_" .. rankName .. ".png"
end

function ImageCache.getCardImage(rank, suit)
    local key = rank .. suit
    if not imageCache[key] then
        local path = getImagePath(rank, suit)
        local ok, img = pcall(function() return love.graphics.newImage(path) end)
        if ok and img then
            imageCache[key] = img
        else
            print("Warning: Could not load card image: " .. path)
            return nil
        end
    end
    return imageCache[key]
end

function ImageCache.getBackImage()
    if not imageCache["back"] then
        local ok, img = pcall(function() return love.graphics.newImage("PNG/Cards (medium)/card_back.png") end)
        if ok and img then
            imageCache["back"] = img
        else
            print("Warning: Could not load card back image")
            return nil
        end
    end
    return imageCache["back"]
end

return ImageCache
