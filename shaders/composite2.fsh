#version 330 compatibility
// Galaxie: bloom, at half size (the WGSL pack's post/bloom.wgsl): the bright parts of the world (sun, lava,
// torches, water glints) gathered on three rings, so they glow in composite4. The bright day sky glows only
// a third as much.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

in vec2 texcoord;

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 out_bloom;

vec3 gs_bright(vec2 uv) {
    vec3 c = textureLod(colortex0, uv, 0.0).rgb;
    // The End's black hole is drawn in composite4, after this pass: fetch its light here.
    if (gs_dimension() == 1 && textureLod(depthtex0, uv, 0.0).r >= 1.0) {
        c = gs_end_eye(gs_view_dir(uv)).rgb * 3.0;
    }
    // Only what is nearly white-hot glows, and coloured light (lava, torches) more than plain white
    // (snow and sand in the sun), which would wash the picture out.
    float hot = gs_max3(c);
    // Below the threshold the result is exactly 0: skip the depth read (most of the screen).
    if (hot <= 0.88) {
        return vec3(0.0);
    }
    float sky = textureLod(depthtex0, uv, 0.0).r >= 1.0 ? 0.35 : 1.0;
    float colourful = hot - min(c.r, min(c.g, c.b));
    return c * smoothstep(0.88, 1.0, hot) * (0.35 + 0.65 * smoothstep(0.1, 0.5, colourful)) * sky;
}

void main() {
    vec2 px = gs_resolution().y / 720.0 / gs_resolution();
    vec3 sum = gs_bright(texcoord) * 2.0;
    float weight = 2.0;
    // Rings of 8, 12 and 16 taps (the wider a ring, the more taps), each turned against the last: with 8 taps
    // on every ring a small bright spot (lava, a torch) glowed as an eight-pointed star or a square.
    for (int i = 0; i < 36; i++) {
        float ring = i >= 20 ? 2.0 : (i >= 8 ? 1.0 : 0.0);
        float count = 8.0 + ring * 4.0;
        float first = i >= 20 ? 20.0 : (i >= 8 ? 8.0 : 0.0);
        float angle = (float(i) - first) * 6.2831853 / count + ring * 0.3926991;
        float radius = 4.0 + ring * ring * 7.0;
        // The same weight per ring, shared by its taps.
        float w = 8.0 / count / (1.0 + ring);
        sum += gs_bright(texcoord + vec2(cos(angle), sin(angle)) * radius * px) * w;
        weight += w;
    }
    out_bloom = vec4(sum / weight * 2.0, 1.0);
}
