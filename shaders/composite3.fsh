#version 330 compatibility
// Galaxie: volumetric light, at half size (the WGSL pack's post/rays.wgsl): the view ray is marched through
// the shadow map, so the air glows where the sun (or the moon) reaches it and stays dark in the shadow of
// trees, cliffs and cave mouths: light shafts. Strongest looking toward the light. Under water it is blue
// and stronger. Then shafts between the clouds.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"
#include "/lib/common.glsl"
#include "/lib/shadow.glsl"

uniform sampler2D depthtex0;
uniform sampler2D colortex7;   // last frame's shafts (kept: not cleared)
uniform int frameCounter;

in vec2 texcoord;

/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 out_rays;

// A per-pixel offset for the march, so 12 steps look like many after the blur. It moves on every frame
// (a golden-ratio step), and the frames are blended below, so the march's grain averages out instead of
// sitting fixed on the screen and crawling over the world as the view turns.
float gs_ign(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))) + float(frameCounter % 1024) * 0.618034);
}

vec3 gs_rays() {
#ifndef SHADOWS
    return vec3(0.0);
#else
    if (RAY_STRENGTH <= 0.0 || gs_dimension() != 0) {
        return vec3(0.0);
    }
    float depth = textureLod(depthtex0, texcoord, 0.0).r;
    vec3 dir = gs_view_dir(texcoord);
    float len = GS_SHADOW_DISTANCE;
    if (depth < 1.0) {
        len = min(length(gs_player_pos(texcoord, depth)), GS_SHADOW_DISTANCE);
    }
    float step_len = len / 12.0;
    float jitter = gs_ign(gl_FragCoord.xy);
    float lit = 0.0;
    for (int i = 0; i < 12; i++) {
        vec3 sp = gs_shadow_position(dir * (float(i) + jitter) * step_len);
        lit += textureLod(shadowtex1, sp, 0.0);
    }
    lit /= 12.0;

    // Shafts between the clouds. The air under the cloud layer is walked along the view ray, out to 900
    // blocks. A sample glows where sunlight comes down in a bundle: at the edges of clouds and through
    // holes in them. The bundles are a pattern that is the same all along the sun's direction (it is
    // looked up on the plane that faces the sun), so on the screen they fan out from the sun, lean as it
    // moves, and drift over the land with the wind and the clouds.
    float beams = 0.0;
    vec3 sun = gs_sun_dir();
    if (sun.y > 0.03 && isEyeInWater == 0 && cameraPosition.y < GS_CLOUD_LOW) {
        float reach = 900.0;
        if (depth < 1.0) {
            reach = min(length(gs_player_pos(texcoord, depth)), reach);
        }
        // Not above the cloud base.
        if (dir.y > 0.001) {
            reach = min(reach, (GS_CLOUD_LOW - cameraPosition.y) / dir.y);
        }
        vec3 across = normalize(cross(sun, vec3(0.0, 1.0, 0.0)));
        vec3 up_sun = cross(across, sun);
        // The samples sit on planes fixed in the world, not at fixed distances from the camera: walking
        // forward leaves them where they are, and the ones that come and go at the ends fade in and out.
        // About 16 a ray, spaced 8, 16, 32 or 64 blocks: in steps, so the spacing stays put while walking.
        float spacing = exp2(clamp(ceil(log2(reach / 16.0)), 3.0, 6.0));
        float shift = fract(dot(cameraPosition, dir) / spacing + jitter) * spacing;
        for (int i = 0; i < 17; i++) {
            float t = (float(i) + 1.0) * spacing - shift;
            float w = clamp(t / spacing, 0.0, 1.0) * clamp((reach - t) / spacing + 0.5, 0.0, 1.0);
            if (w <= 0.0) {
                continue;
            }
            vec3 p = dir * t;
            float open = clamp((gs_cloud_shadow(p) - 0.4) / 0.6, 0.0, 1.0);
            // Under open sky (open == 1) both terms below are exactly 0: skip their two noise lookups.
            if (open >= 1.0) {
                continue;
            }
            vec3 world = p + cameraPosition;
            vec2 q = vec2(dot(world, across), dot(world, up_sun));
            float bundle = gs_noise(vec3(q * 0.035, gs_time() * 0.01)) * 0.7 + gs_noise(vec3(q * 0.09, 4.0)) * 0.3;
            beams += w * (4.0 * open * (1.0 - open) * smoothstep(0.45, 0.7, bundle) + 0.35 * (1.0 - open) * smoothstep(0.62, 0.8, bundle));
        }
        beams *= spacing / 900.0;
    }
    float toward = max(dot(dir, gs_light_dir()), 0.0);
    // Mostly toward the light: looking away from it the air stays clear, so open land is not washed out.
    float phase = 0.03 + 1.4 * pow(toward, 8.0) + 0.25 * pow(toward, 2.0);
    float air = len / GS_SHADOW_DISTANCE;
    vec3 tint = vec3(1.0);
    if (isEyeInWater == 1) {
        // Under water the shafts are blue and show from every side; the deeper the camera, the less
        // light is left of them.
        phase = 0.5 + 1.2 * pow(toward, 4.0);
        tint = vec3(0.35, 0.8, 1.0) * 2.0 * (0.2 + 0.8 * gs_eye_light().y);
    }
    // By night only a faint glow is left.
    float night_dim = mix(0.35, 1.0, gs_dayf());
    vec3 rays = gs_light_color() * tint * lit * phase * air * RAY_STRENGTH * 0.3 * night_dim * (1.0 - thunderStrength * 0.6);
    vec3 shafts = gs_light_color() * beams * (0.25 + 0.75 * pow(toward, 2.0)) * RAY_STRENGTH * 7.0 * gs_dayf()
        * (1.0 - rainStrength * 0.7) * (1.0 - gs_solar_eclipse().y);
    return rays + shafts;
#endif
}

void main() {
    vec3 rays = gs_rays();
    // Blended with last frame's shafts where this point of the world was on screen then (reprojected with
    // last frame's camera, as the lava glow is): a fifth of this frame's each frame. Off screen last frame,
    // or when the camera moved a long way, this frame's alone.
    float depth = textureLod(depthtex0, texcoord, 0.0).r;
    vec3 p = depth >= 1.0 ? gs_view_dir(texcoord) * 2000.0 : gs_player_pos(texcoord, depth);
    vec4 before = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(p + cameraPosition - previousCameraPosition, 1.0));
    if (before.w > 0.0 && length(cameraPosition - previousCameraPosition) < 4.0) {
        vec2 prev_uv = before.xy / before.w * 0.5 + 0.5;
        if (all(greaterThanEqual(prev_uv, vec2(0.0))) && all(lessThanEqual(prev_uv, vec2(1.0)))) {
            vec3 last = textureLod(colortex7, prev_uv, 0.0).rgb;
            if (any(isnan(last)) || any(isinf(last))) {
                last = rays;
            }
            rays = mix(last, rays, 0.2);
        }
    }
    out_rays = vec4(rays, 1.0);
}
