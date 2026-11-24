// Galaxie: the vertex stage of everything the WGSL pack left to vanilla (entities, block entities, the
// hand, particles, lines, the breaking overlay, rain and snow).
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec2 light_level;
out vec4 glcolor;
out vec3 player_pos;
out vec3 world_normal;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    light_level = clamp(gl_MultiTexCoord1.xy / 240.0, 0.0, 1.0);
    glcolor = gl_Color;
    player_pos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    world_normal = normalize(mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal));
}
