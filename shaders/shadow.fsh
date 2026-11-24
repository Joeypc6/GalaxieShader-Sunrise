#version 330 compatibility
// Galaxie: what the shadow map holds besides depth: stained glass's colour (shadowcolor0), and water marked
// by alpha 1 (terrain under it gets the caustics).
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;
flat in int block_id;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 out_color;

void main() {
    vec4 c = texture(gtexture, texcoord) * glcolor;
    if (c.a < 0.1) {
        discard;
    }
    out_color = block_id == 1 ? vec4(1.0) : vec4(c.rgb, min(c.a, 0.99));
}
