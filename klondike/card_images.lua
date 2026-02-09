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
		img:setFilter("nearest","nearest")
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
    end
    return _rawCache[key]
end


function ImageCache.getBackImage()
    if not _rawCache["back"] then
	    _rawCache["back"] = loadRawImage("PNG/Cards (large)/card_back/png")
	end
	return _rawCache["back"]
end

-- start Canvas scaling

local function getScaledTexture(rawImg, w, h)
    -- Create a unique cache key
    local key = rawImg .. "_" .. w .. "x" .. h
    if _canvasCache[key] then return _canvasCache[key] end

    -- Build a canvas of the target size
    local canvas = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    -- Draw the raw image stretched to the canvas size
    love.graphics.draw(
        rawImg,
        0, 0,
        0,
        w / rawImg:getWidth(),
        h / rawImg:getHeight()
    )
    love.graphics.setCanvas()   -- restore default render target

    -- Turn the canvas into a regular Image (so callers can treat it like any other texture)
    local tex = canvas:newImageData():newImage()
    tex:setFilter("nearest", "nearest")
    _canvasCache[key] = tex
    return tex
end

-- Scaled card texture

function ImageCache.getCardTexture(rank, suit, w, h)
	w = w or 100
	h = h or 140
	local raw = ImageCache.getCardImage(rank,suit)
	if not raw then return nil end
	return getScaledTexture(raw, w, h)
end

function ImageCache.getBackTexture(w, h)
	w = w or 100
	h = h or 140
	local raw = ImageCache.getBackImage()
	if not raw then return nil end
	return getScaledTexture(raw, w, h)
end

return ImageCache
