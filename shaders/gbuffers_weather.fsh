#version 330 compatibility
// Galaxie: rain and snow (the WGSL pack's weather stage). Rain streaks take the light of the place and the
// sky, and the sheets are broken up; snow keeps its own texture and opacity.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;

in vec2 texcoord;
in vec2 lmcoord;
in vec2 light_level;
in vec4 glcolor;
in vec3 player_pos;
in vec3 world_normal;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 out_color;

void main() {
    vec4 color = texture(gtexture, texcoord) * glcolor;
    // The format draws rain and snow alike: the biome at the camera tells which falls (the WGSL pack was
    // told per streak).
    if (biome_precipitation == 2 || gs_dimension() != 0) {
        out_color = vec4(color.rgb * texture(lightmap, lmcoord).rgb, color.a);
        return;
    }
    float daylight = mix(0.28, 1.0, gs_dayf()) * (1.0 - 0.3 * thunderStrength);
    float lit = max(light_level.x * 0.8, light_level.y * daylight);
    vec3 tint = mix(vec3(0.38, 0.48, 0.62), vec3(0.65, 0.75, 0.86), lit);
    vec3 flash = vec3(0.35, 0.42, 0.6) * gs_storm_flash() * light_level.y;
    // Break up the sheets without moving the streaks through roofs or walls.
    vec3 world = player_pos + cameraPosition;
    float drops = gs_noise(vec3(world.xz * 12.0, (world.y + gs_time() * 18.0) * 1.5));
    float thin = smoothstep(0.08, 0.45, drops);
    float near_fade = smoothstep(0.35, 1.5, length(player_pos));
    out_color = vec4(vec3(gs_luma(color.rgb)) * tint + flash,
        color.a * mix(0.3, 0.8, thin) * near_fade * mix(0.8, 1.0, thunderStrength));
}
