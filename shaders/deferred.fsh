#version 330 compatibility
// Galaxie: the sky (the WGSL pack's sky stage), where no opaque terrain is, and a copy of the opaque world
// for water to look through and into.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

in vec2 texcoord;

/* RENDERTARGETS: 0,4 */
layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_opaque;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    vec3 c = texelFetch(colortex0, texel, 0).rgb;
    float depth = texelFetch(depthtex0, texel, 0).r;
    // Only the Overworld gets this sky; the Nether and the End keep vanilla's.
    if (depth >= 1.0 && gs_dimension() == 0) {
        c = gs_sky(gs_view_dir(texcoord));
    }
    out_color = vec4(c, 1.0);
    out_opaque = vec4(c, 1.0);
}
