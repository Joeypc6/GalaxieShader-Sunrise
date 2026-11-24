// Galaxie: the fragment stage of terrain (gbuffers_terrain) and, with GS_TRANSLUCENT, of water and
// translucent terrain (gbuffers_water): the WGSL material stage.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/common.glsl"
#include "/lib/material.glsl"
#if defined GS_TRANSLUCENT
#define GS_MIRROR_SCENE colortex4
#define GS_MIRROR_DEPTH depthtex1
uniform sampler2D colortex4;
uniform sampler2D depthtex1;
#include "/lib/reflect.glsl"
#include "/lib/water.glsl"
#endif

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D normals;
uniform sampler2D specular;

in vec2 texcoord;
in vec2 lmcoord;
in vec2 light_level;
in vec4 glcolor;
in vec3 player_pos;
in vec3 world_normal;
in vec4 world_tangent;
flat in int block_id;
flat in float emission;

/* RENDERTARGETS: 0,2 */
layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_surface;

void main() {
    vec4 albedo = texture(gtexture, texcoord);
    vec4 normal_map = texture(normals, texcoord);
    vec4 specular_map = texture(specular, texcoord);
    vec3 lm = texture(lightmap, lmcoord).rgb;
    if (albedo.a * glcolor.a < 0.1) {
        discard;
    }
    GsSurfaceIn i;
    i.albedo = vec4(albedo.rgb, albedo.a * glcolor.a);
    i.tint = glcolor.rgb;
    i.lightmap = lm;
    i.light = light_level;
    i.position = player_pos;
    i.normal = normalize(world_normal);
    i.tangent = vec4(normalize(world_tangent.xyz), world_tangent.w);
    i.uv = texcoord;
    i.normal_map = normal_map;
    i.specular_map = specular_map;
    i.screen = gl_FragCoord.xy / gs_resolution();
    i.material = block_id;
    i.emission = emission;
    i.top = i.normal.y > 0.5;
#if defined GS_TRANSLUCENT
    i.translucent = true;
    // Sunrise draws distant terrain's water as a sheet that its land does not hide from this program:
    // test it against the opaque world's depth here, so far land shows instead of water drawn over it.
    if (gs_behind(gl_FragCoord.xy / gs_resolution()) < length(player_pos) - 0.5) {
        discard;
    }
    if (block_id == GS_WATER) {
        out_color = gs_water(i);
        out_surface = vec4(0.0);
        return;
    }
    if (block_id == GS_PORTAL) {
        out_color = gs_portal(i);
        out_surface = vec4(0.0);
        return;
    }
#else
    i.translucent = false;
#endif
    GsSurfaceOut o = gs_terrain(i);
    out_color = o.color;
    out_surface = vec4(gs_encode_normal(o.normal), o.smoothness, o.data);
}
