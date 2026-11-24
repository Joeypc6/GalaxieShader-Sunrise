#version 330 compatibility
// Galaxie: keeps this frame's rain clock for the next frame (the WGSL pack's post/rain_copy.wgsl), and
// blurs the lava gathered in composite: every quarter-size pixel near this one is read directly (no
// filtering, no gaps: spaced or filtered taps left a far pool glowing as a grid of dots or bands), so lava
// glows as a smooth orange halo at any distance. composite4 adds it.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"

uniform sampler2D colortex5;

in vec2 texcoord;

/* RENDERTARGETS: 6 */
layout(location = 0) out vec4 out_kept;

void main() {
    ivec2 size = textureSize(colortex5, 0);
    ivec2 here = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    float sum = 0.0;
    float weight = 0.0;
    // A wide flat ellipse (2.5 times wider than tall): lava's light spreads over the ground, seen at a low
    // angle; a round blur read as an orange ball floating in the air.
    for (int y = -3; y <= 3; y++) {
        for (int x = -8; x <= 8; x++) {
            vec2 o = vec2(float(x) / 4.0, float(y) / 1.6);
            float w = exp(-dot(o, o) * 0.5);
            ivec2 t = clamp(here + ivec2(x, y), ivec2(0), size - ivec2(1));
            sum += texelFetch(colortex5, t, 0).g * w;
            weight += w;
        }
    }
    // Kept from frame to frame: a fifth of this frame's glow blended into last frame's, reprojected. A pool
    // smaller than a pixel far away is drawn on some frames and not others; without this its glow blinked.
    float glow = mix(texelFetch(colortex5, here, 0).b, sum / weight, 0.2);
    out_kept = vec4(texelFetch(colortex5, ivec2(0), 0).r, glow, 0.0, 1.0);
}
