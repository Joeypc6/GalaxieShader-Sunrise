// Galaxie: the format's uniforms, and the values the WGSL pack read from Sunrise's `frame`, worked out
// from them. Every program includes this first (after settings.glsl).
#if !defined GS_FRAME
#define GS_FRAME 1

uniform float frameTimeCounter;   // seconds, wraps hourly (as the WGSL frame.time)
uniform float frameTime;          // the last frame's length
uniform float rainStrength;
uniform float wetness;            // rainStrength eased (the WGSL frame.wetness)
uniform float thunderStrength;
uniform float viewWidth;
uniform float viewHeight;
uniform float temperature;        // the biome at the camera
uniform float rainfall;
uniform int worldTime;
uniform int worldDay;
uniform int moonPhase;            // 0 full .. 4 new .. 7
uniform int isEyeInWater;
uniform int biome_precipitation;  // 0 none, 1 rain, 2 snow
uniform int biome_category;       // CAT_NETHER, CAT_THE_END, ... (the biome at the camera)
uniform ivec2 eyeBrightnessSmooth;
uniform bool hasCeiling;
uniform bool hasSkylight;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

// The shadow map, as the WGSL manifest's [shadow]: 2048 texels over 128 blocks each way, no distortion.
const int shadowMapResolution = 2048;
const float shadowDistance = 128.0;
const float sunPathRotation = 0.0;
const float GS_SHADOW_DISTANCE = 128.0;
// One texel of the map, in blocks (the WGSL frame.shadow_center_texel).
const float GS_SHADOW_TEXEL = 0.125;

// 0 the Overworld, -1 the Nether, 1 the End (the WGSL frame.dimension).
// The biome's category tells the End apart (its dimension reports sky light in Sunrise); the Nether also
// by its ceiling.
int gs_dimension() {
#if defined CAT_THE_END && defined CAT_NETHER
    if (biome_category == CAT_THE_END) {
        return 1;
    }
    if (biome_category == CAT_NETHER) {
        return -1;
    }
#endif
    return hasCeiling ? -1 : (hasSkylight ? 0 : 1);
}

float gs_time() {
    return frameTimeCounter;
}

vec2 gs_resolution() {
    return vec2(viewWidth, viewHeight);
}

// World-aligned directions toward the sun, the moon and the light that casts shadows.
vec3 gs_sun_dir() {
    return normalize(mat3(gbufferModelViewInverse) * sunPosition);
}

vec3 gs_moon_dir() {
    return normalize(mat3(gbufferModelViewInverse) * moonPosition);
}

vec3 gs_light_dir() {
    return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
}

// The light at the camera, 0..1, eased (the WGSL frame.eye_light_smooth: x block, y sky).
vec2 gs_eye_light() {
    return clamp(vec2(eyeBrightnessSmooth) / 240.0, 0.0, 1.0);
}

// The time of day, 0..1 with noon at 0.25 (the WGSL frame.day_time).
float gs_day_time() {
    return float(worldTime) / 24000.0;
}

// GL window depth to a camera-relative, world-aligned position (the WGSL view_position).
vec3 gs_player_pos(vec2 uv, float depth) {
    vec4 v = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    return (gbufferModelViewInverse * vec4(v.xyz / v.w, 1.0)).xyz;
}

// The view ray through a screen point, from two points on it: walking bob moves the projection, so
// one point just before the camera swings with every step.
vec3 gs_view_dir(vec2 uv) {
    return normalize(gs_player_pos(uv, 0.999) - gs_player_pos(uv, 0.5));
}

// A camera-relative point to the screen (uv 0..1 from the bottom left) and its w.
vec3 gs_to_screen(vec3 p) {
    vec4 clip = gbufferProjection * (gbufferModelView * vec4(p, 1.0));
    return vec3(clip.xy / clip.w * 0.5 + 0.5, clip.w);
}

#endif
