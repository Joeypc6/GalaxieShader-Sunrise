// Galaxie: the vertex stage of terrain, water and translucent terrain (gbuffers_terrain, gbuffers_water):
// the WGSL vertex stage's movement, and what the material stage needs.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/common.glsl"
#include "/lib/wave.glsl"
#include "/lib/guess.glsl"

in vec4 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_tangent;
in vec4 at_midBlock;

uniform sampler2D gtexture;

out vec2 texcoord;
out vec2 lmcoord;
out vec2 light_level;
out vec4 glcolor;
out vec3 player_pos;
out vec3 world_normal;
out vec4 world_tangent;
flat out int block_id;
flat out float emission;

void main() {
    vec3 p = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    light_level = clamp(gl_MultiTexCoord1.xy / 240.0, 0.0, 1.0);
    block_id = int(mc_Entity.x + 0.5);
    emission = clamp(at_midBlock.w / 15.0, 0.0, 1.0);
    world_normal = normalize(mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal));
    if (!gs_ids_present(at_midBlock))
        block_id = gs_guess_id(block_id, textureLod(gtexture, mc_midTexCoord.xy, 4.0), gl_Color.rgb, world_normal, light_level.x);
    world_tangent = vec4(normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * at_tangent.xyz)),
        at_tangent.w < 0.0 ? -1.0 : 1.0);

    // Vanilla's shade of each face (the format leaves it out of the vertex colour): the WGSL pack was
    // handed the shaded tint.
    float shade = 1.0;
    if (world_normal.y < -0.5) {
        shade = gs_dimension() == -1 ? 0.9 : 0.5;
    } else if (abs(world_normal.z) > 0.5) {
        shade = 0.8;
    } else if (abs(world_normal.x) > 0.5) {
        shade = 0.6;
    }
    glcolor = vec4(gl_Color.rgb * shade, gl_Color.a);

    // The sprite's top corners lie above its middle in the atlas (v grows downward).
    float top = gl_MultiTexCoord0.y < mc_midTexCoord.y ? 1.0 : 0.0;
    p = gs_move_corner(p, block_id, top, light_level.y);
    player_pos = p;
    gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(p, 1.0));
}
