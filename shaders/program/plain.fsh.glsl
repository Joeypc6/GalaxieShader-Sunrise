// Galaxie: the fragment stage of what the WGSL pack left to vanilla. One of these is defined first:
// GS_PLAIN_BASIC (lines: the vertex colour), GS_PLAIN_TEXTURED (unlit: texture and colour), GS_PLAIN_LIT
// (lit particles: and the light map), GS_PLAIN_ENTITY (entities and block entities: and vanilla's two
// lights; colortex2 cleared, so no puddles on them), GS_PLAIN_HAND (as entities, marked in colortex2 so the
// later passes leave it as vanilla draws it: the WGSL pack drew the hand after its passes).
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform vec4 entityColor;

in vec2 texcoord;
in vec2 lmcoord;
in vec2 light_level;
in vec4 glcolor;
in vec3 player_pos;
in vec3 world_normal;

#if defined GS_PLAIN_ENTITY || defined GS_PLAIN_HAND
/* RENDERTARGETS: 0,2 */
layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_surface;
#else
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 out_color;
#endif

void main() {
#if defined GS_PLAIN_BASIC
    vec4 color = glcolor;
#else
    vec4 color = texture(gtexture, texcoord) * glcolor;
#endif
#if !defined GS_PLAIN_BASIC
    if (color.a < 0.1) {
        discard;
    }
#endif
#if defined GS_PLAIN_LIT || defined GS_PLAIN_ENTITY || defined GS_PLAIN_HAND
    color.rgb *= texture(lightmap, lmcoord).rgb;
#endif
#if defined GS_PLAIN_ENTITY || defined GS_PLAIN_HAND
    // Vanilla's two lights on entities.
    vec3 n = normalize(world_normal);
    float shade = 0.4 + 0.6 * (max(dot(n, normalize(vec3(0.2, 1.0, -0.7))), 0.0)
        + max(dot(n, normalize(vec3(-0.2, 1.0, 0.7))), 0.0));
    color.rgb *= min(shade, 1.0);
    // The hurt flash and the creeper's white flash.
    color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);
#endif
    out_color = color;
#if defined GS_PLAIN_HAND
    out_surface = vec4(0.0, 0.0, -1.0, 0.0);
#elif defined GS_PLAIN_ENTITY
    out_surface = vec4(0.0);
#endif
}
