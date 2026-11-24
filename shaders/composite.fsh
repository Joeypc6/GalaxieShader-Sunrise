#version 330 compatibility
// Galaxie: the rain clock (the WGSL pack's post/rain_clock.wgsl), at a quarter of the size. Red: when the
// rainwater on the ground will have dried, in clock seconds (0 when the ground is dry); colortex6 keeps it
// for the next frame (composite1). Green: the lava glow under this pixel, from every one of the world's
// pixels it covers, so a far pool a single pixel wide still counts. Blue: last frame's blurred glow, read
// where this point of the world was on screen last frame.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;

in vec2 texcoord;

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 out_clock;

// An expiry time, not a per-frame water increment: small drying steps would round away.
float gs_rain_deadline(float before) {
    if (gs_dimension() != 0) {
        return 0.0;
    }
    float deadline = before - 1.0;
    if (before <= 0.0 || frameTime <= 0.0) {
        deadline = gs_time();
    } else if (deadline - gs_time() > PUDDLE_DRYING + 4.0) {
        // The clock wraps hourly; an expiry can lie just beyond that boundary.
        deadline -= 3600.0;
    }
    if (biome_precipitation == 1 && rainStrength > 0.001) {
        deadline = max(deadline, gs_time() + wetness * PUDDLE_DRYING);
    }
    if (deadline <= gs_time()) {
        return 0.0;
    }
    return deadline + 1.0;
}

void main() {
    float before = texelFetch(colortex6, ivec2(0), 0).r;
    ivec2 size = ivec2(gs_resolution());
    // An 8x8 box (overlapping the neighbours' by half): the blur in composite1 reads every pixel near it,
    // and a 4x4 box left a far pool glowing as a grid of dots.
    ivec2 base = ivec2(texcoord * gs_resolution() - vec2(4.0));
    float lava = 0.0;
    for (int k = 0; k < 64; k++) {
        vec4 s = texelFetch(colortex2, clamp(base + ivec2(k % 8, k / 8), ivec2(0), size - ivec2(1)), 0);
        if (s.w < 0.0) {
            lava += -s.w;
        }
    }
    // Read where this point of the world was on screen last frame: read at the same screen spot, the glow
    // trailed behind every turn.
    ivec2 qsize = textureSize(colortex6, 0);
    float depth = texelFetch(depthtex0, clamp(ivec2(texcoord * gs_resolution()), ivec2(0), size - ivec2(1)), 0).r;
    vec3 p = depth >= 1.0 ? gs_view_dir(texcoord) * 2000.0 : gs_player_pos(texcoord, depth);
    vec4 before_clip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(p + cameraPosition - previousCameraPosition, 1.0));
    float last = 0.0;
    if (before_clip.w > 0.0) {
        vec2 prev_uv = before_clip.xy / before_clip.w * 0.5 + 0.5;
        if (all(greaterThanEqual(prev_uv, vec2(0.0))) && all(lessThanEqual(prev_uv, vec2(1.0)))) {
            ivec2 t = clamp(ivec2(prev_uv * vec2(qsize)), ivec2(0), qsize - ivec2(1));
            last = texelFetch(colortex6, t, 0).g;
        }
    }
    out_clock = vec4(gs_rain_deadline(before), lava / 64.0, last, 1.0);
}
