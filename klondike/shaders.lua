local Shaders = {}

Shaders.dropShadow = love.graphics.newShader[[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        return vec4(0.0, 0.05, 0.02, texcolor.a * 0.5);
    }
]]

Shaders.feltGradient = love.graphics.newShader[[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        // 1. Sample the actual fabric image pixels
        vec4 texColor = Texel(texture, texture_coords);
        
        // 2. Calculate your gradient distance
        float dist = distance(texture_coords, vec2(0.5, 0.5));
        
        // 3. Define your green tones
        vec3 centerColor = vec3(0.05, 0.35, 0.15); 
        vec3 edgeColor = vec3(0.01, 0.12, 0.04);
        vec3 gradient = mix(centerColor, edgeColor, dist * 1.2);
        vec3 tinted = texColor.rgb * gradient;

        // 4. Multiply the fabric texture by the green gradient
        // This tints the image while keeping its details
        return vec4(mix(tinted, texColor.rgb,0.3), texColor.a);
    }
]]

return Shaders
