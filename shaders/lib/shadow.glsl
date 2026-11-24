// Galaxie: the shadow map, read by terrain (gbuffers_terrain, gbuffers_water) and the light shafts
// (composite3). With the Shadows option off nothing declares it, and the format runs no shadow pass.
#if !defined GS_SHADOW
#define GS_SHADOW 1

#ifdef SHADOWS
uniform sampler2DShadow shadowtex0;   // everything (the WGSL shadow_map_translucent)
uniform sampler2DShadow shadowtex1;   // without translucent terrain (the WGSL shadow_map)
uniform sampler2D shadowcolor0;       // stained glass colour; alpha 1 marks water
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
const bool shadowHardwareFiltering = true;

// A camera-relative point in the shadow map: xy 0..1, z the depth to compare.
vec3 gs_shadow_position(vec3 p) {
    vec4 c = shadowProjection * (shadowModelView * vec4(p, 1.0));
    return c.xyz / c.w * 0.5 + 0.5;
}
#endif

#endif
