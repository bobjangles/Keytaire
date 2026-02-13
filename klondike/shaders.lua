local Shaders = {}

Shaders.dropShadow = love.graphics.newShader[[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        return vec4(0.0, 0.05, 0.02, texcolor.a * 0.5);
    }
]]

return Shaders
