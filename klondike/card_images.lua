-- Caches loaded card images to avoid reloading
local ImageCache = {}
local _rawCache = {}  --raw PNG textures
local _canvasCache = {} -- scaled canvases turned into textures

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
    return ("PNG/Self/card_%s_%s.png"):format(suitName, rankName)
end

-- returning a raw image

local function loadRawImage(path)
	local ok, img = pcall(love.graphics.newImage,path)
	if ok and img then
		img:setFilter("linear","linear",8)
		return img
	else
		print("[card_images] Warning: could not load '" .. path .. "'")
		return nil
	end
end

-- raw texture (fallback)

function ImageCache.getCardImage(rank, suit)
    local key = rank .. suit
    if not _rawCache[key] then
        _rawCache[key] = loadRawImage(getImagePath(rank, suit))
    end
    return _rawCache[key]
end


function ImageCache.getBackImage()
    if not _rawCache["back"] then
	    _rawCache["back"] = loadRawImage("PNG/Self/card_back.png")
	end
	return _rawCache["back"]
end

-- Scaled card texture

function ImageCache.getCardImage(rank, suit)
    local key = rank .. suit
	if not _rawCache[key] then
        _rawCache[key] = loadRawImage(getImagePath(rank,suit))
    end
    return _rawCache[key]
end

function ImageCache.getBackImage()
	if not _rawCache["back"] then
        _rawCache["back"] = loadRawImage("PNG/Self/card_back.png")
    end
	return _rawCache["back"]
end

return ImageCache
