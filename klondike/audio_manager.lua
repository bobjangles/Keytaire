-- audio_manager.lua
local AudioManager = {}

local sfx = {}
local isMuted = false
local defaultVolume = 0.8

function AudioManager.init()
    -- Map logical action keys to your physical audio assets
    -- (You can change or add filenames here yourself whenever you want)
    local soundFiles = {
        place1 = "Audio/card-place-3.wav",
        place2 = "Audio/card-place-2.wav",
        slide1 = "Audio/card-slide-1.wav",
        slide8 = "Audio/card-slide-4.wav",
        shove  = "Audio/card-shove-3.wav",
        pack_open = "Audio/cards-pack-open-1.wav"
    }

    for key, path in pairs(soundFiles) do
        if love.filesystem.getInfo(path) then
            sfx[key] = love.audio.newSource(path, "static")
        else
            print(("[AudioManager] Warning: Could not find sound file at '%s'"):format(path))
        end
    end
end

function AudioManager.play(name, customPitch)
    if isMuted or not sfx[name] then return end

    local source = sfx[name]

    -- TRICK FOR JUICY FEEL: Subtle pitch variation
    -- If a pitch isn't explicitly provided, vary it randomly between 0.95 and 1.05
    -- so every single card interaction sounds slightly unique.
    local pitch = customPitch or (love.math.random(95, 105) / 100)
    source:setPitch(pitch)
    source:setVolume(defaultVolume)

    -- If the sound is already playing (e.g. rapid inputs), rewind it to start immediately
    if source:isPlaying() then
        source:seek(0)
    end
    source:play()
end

function AudioManager.toggleMute()
    isMuted = not isMuted
    if isMuted then
        love.audio.stop()
    end
end

return AudioManager
