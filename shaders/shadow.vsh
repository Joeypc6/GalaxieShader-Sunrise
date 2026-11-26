#version 330 compatibility
// Galaxie: the shadow map. Plants, leaves and water move as in the view, so they shade themselves alike.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/common.glsl"
#include "/lib/wave.glsl"
#include "/lib/guess.glsl"

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform sampler2D gtexture;

in vec4 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_midBlock;

out vec2 texcoord;
out vec4 glcolor;
flat out int block_id;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    block_id = int(mc_Entity.x + 0.5);
    vec3 n = normalize(mat3(shadowModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    if (!gs_ids_present(at_midBlock)) {
        block_id = gs_guess_id(block_id, textureLod(gtexture, mc_midTexCoord.xy, 4.0), gl_Color.rgb, n,
            clamp(gl_MultiTexCoord1.x / 240.0, 0.0, 1.0));
    }
    vec3 p = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    float top = gl_MultiTexCoord0.y < mc_midTexCoord.y ? 1.0 : 0.0;
    float sky = clamp(gl_MultiTexCoord1.y / 240.0, 0.0, 1.0);
    p = gs_move_corner(p, block_id, top, sky);
    gl_Position = shadowProjection * (shadowModelView * vec4(p, 1.0));
}
