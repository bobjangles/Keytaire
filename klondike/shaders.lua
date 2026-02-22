local Shaders = {}

Shaders.dropShadow = love.graphics.newShader[[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        return vec4(0.0, 0.05, 0.02, texcolor.a * 0.5);
    }
]]

Shaders.feltGradient = love.graphics.newShader[[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        // Calculate distance from center (0.5, 0.5)
        float dist = distance(texture_coords, vec2(0.5, 0.5));
        
        // Colors: Center (Bright Green) to Edges (Dark Hunter Green)
        vec3 centerColor = vec3(0.05, 0.35, 0.15); 
        vec3 edgeColor = vec3(0.01, 0.12, 0.04);
        
        // Smoothly mix the colors based on distance
        vec3 finalColor = mix(centerColor, edgeColor, dist * 1.2);
        
        return vec4(finalColor, 1.0);
    }
]]

return Shaders
