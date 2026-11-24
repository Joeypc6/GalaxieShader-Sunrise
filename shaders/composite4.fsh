#version 330 compatibility
// Galaxie: the picture (the WGSL pack's post/final.wgsl): the world, wet ground and puddles after rain, haze
// in the colour of the biome's air, the End's sky, the Nether's shimmer, clouds in front of the ground,
// rainbows, blue fog and drifting specks under water, the light shafts and the bloom, then exposure like an
// eye's and a filmic tone curve.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"
#include "/lib/common.glsl"
#define GS_MIRROR_SCENE colortex0
#define GS_MIRROR_DEPTH depthtex0
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
#include "/lib/reflect.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 out_color;

// The ACES film curve (Narkowicz's fit): deep shadows, a long soft shoulder for the highlights.
vec3 gs_filmic(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3(0.0), vec3(1.0));
}

// Specks near the camera (motes under water, embers in the Nether). Each has its own place in the world,
// one per cell of `cell` blocks, and drifts with `moved` (how far they have all moved by now), so they
// stay where they are while the camera walks. The ray is walked through the cells for about 10 blocks.
float gs_specks(vec3 dir, float dist, vec3 moved, float cell, float radius) {
    vec3 origin = cameraPosition - moved;
    float sum = 0.0;
    vec3 last = vec3(1.0e9);
    for (int i = 0; i < 20; i++) {
        vec3 id = floor((origin + dir * (0.3 + float(i) * cell * 0.35)) / cell);
        if (all(equal(id, last)) || gs_hash13(id) > 0.4) {
            continue;
        }
        last = id;
        vec3 to = (id + vec3(0.2) + gs_hash33(id) * 0.6) * cell - origin;
        float along = dot(to, dir);
        if (along < 0.3 || along > dist) {
            continue;
        }
        float flicker = 0.6 + 0.4 * sin(gs_time() * (2.0 + 6.0 * gs_hash13(id + vec3(3.0))) + id.x);
        sum += smoothstep(radius, 0.0, length(to - dir * along)) * flicker / (1.0 + along * 0.12);
    }
    return sum;
}

vec3 gs_spectrum(float hue) {
    return clamp(abs(fract(hue + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, vec3(0.0), vec3(1.0));
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    vec3 c = texelFetch(colortex0, texel, 0).rgb;
    vec4 surface = texelFetch(colortex2, texel, 0);
    // The hand: the WGSL pack drew it after its passes, as vanilla does. Left as it is.
    if (surface.z < -0.5) {
        out_color = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
        return;
    }
    float depth = texelFetch(depthtex0, texel, 0).r;
    bool is_sky = depth >= 1.0;
    vec3 position = gs_player_pos(texcoord, depth);
    vec3 dir = gs_view_dir(texcoord);
    float dist = 1000.0;
    if (!is_sky) {
        dist = length(position);
    }
    bool overworld = gs_dimension() == 0;
    bool eye_dry = isEyeInWater == 0;
    float deadline = texelFetch(colortex5, ivec2(0), 0).r;
    float rainwater = deadline > 0.0 ? clamp((deadline - 1.0 - gs_time()) / PUDDLE_DRYING, 0.0, 1.0) : 0.0;

    // The surface is read only for rainwater and storm flashes; with neither, this block changes nothing.
    if (!is_sky && eye_dry && overworld && (rainwater > 0.0 || gs_storm_flash() > 0.0)) {
        float data = surface.w;
        if (data > 0.0) {
            float wet = rainwater * WETNESS_AMOUNT * data;
            if (wet > 0.0) {
                vec3 world = cameraPosition + position;
                vec3 normal = gs_decode_normal(surface.xy);
                float level = smoothstep(0.8, 0.98, normal.y);
                float puddle = gs_puddle(world, wet) * level;
                vec2 impacts = gs_rain_ripples(world.xz) * data * exp(-dist * 0.035);
                vec3 n = normalize(mix(normal, vec3(0.0, 1.0, 0.0), puddle)
                    + vec3(impacts.x, 0.0, impacts.y) * puddle);
                float fresnel = 0.025 + 0.975 * pow(1.0 - max(dot(n, -dir), 0.0), 5.0);
                c *= mix(1.0, 0.76, wet * (0.5 + 0.5 * level));
                if (puddle > 0.001) {
                    vec3 reflected = gs_puddle_sky(dir, world, n);
                    if (dist < 48.0) {
                        vec4 mirror = gs_trace_mirror(position + n * 0.06, reflect(dir, n), 16, 0.18, 0.14, 24.0, 36.1);
                        reflected = mix(reflected, mirror.rgb, mirror.a * (1.0 - smoothstep(32.0, 48.0, dist)));
                    }
                    c = mix(c, reflected, puddle * (0.12 + 0.8 * fresnel));
                    vec3 half_vec = normalize(gs_light_dir() - dir);
                    float glint = pow(max(dot(n, half_vec), 0.0), 220.0) * puddle;
                    c += gs_light_color() * glint * gs_cloud_shadow(position) * 0.5;
                }
            }
            c += vec3(0.25, 0.32, 0.48) * gs_storm_flash() * data;
        }
    }

    // Haze over far terrain, in the colour of the sky behind it, tinted and thickened by the biome's air.
    if (!is_sky && eye_dry && overworld) {
        vec4 air = gs_biome_air();
        vec3 flat_dir = normalize(vec3(dir.x, 0.03, dir.z));
        // Half vanilla's fog colour, half the scattered sky, so far land pales instead of turning cyan.
        vec3 sky_col = mix(gs_fog_color(), gs_atmosphere(flat_dir, gs_sun_dir()), 0.5 * gs_dayf() * (1.0 - rainStrength));
        float h = 1.0 - exp(-dist * 0.0015 * FOG_AMOUNT * air.a * (1.0 + 3.0 * rainStrength + 2.0 * thunderStrength));
        vec3 storm_fog = mix(sky_col * air.rgb, vec3(gs_luma(sky_col)) * vec3(0.75, 0.85, 1.0), thunderStrength * 0.6);
        c = mix(c, storm_fog, h * 0.45);
    }

    // The End: its own sky, and far islands sink into violet haze.
    if (gs_dimension() == 1) {
        if (is_sky) {
            // What the game drew there stays on top where it is bright: the End's purple flashes.
            c = gs_end_sky(dir) + max(c - vec3(0.15), vec3(0.0));
        } else {
            c = mix(c, vec3(0.1, 0.035, 0.17), 1.0 - exp(-dist * 0.004 * FOG_AMOUNT * 2.0));
        }
    }

    // The Nether: the hot air shimmers over what is far, the haze glows in the biome's fog colour and
    // orange from the lava below, and embers rise past the camera.
    if (gs_dimension() == -1 && eye_dry) {
        vec2 wobble = vec2(gs_noise(vec3(texcoord * vec2(60.0, 35.0), gs_time() * 1.5)),
            gs_noise(vec3(texcoord * vec2(60.0, 35.0) + vec2(9.0), gs_time() * 1.5))) - 0.5;
        c = textureLod(colortex0, texcoord + wobble * 0.004 * smoothstep(10.0, 60.0, dist), 0.0).rgb;
        float h = 1.0 - exp(-dist * 0.012 * FOG_AMOUNT * 2.0);
        vec3 glow = gs_fog_color() * 1.5 + vec3(1.0, 0.35, 0.08) * 0.2 * smoothstep(0.25, -0.4, dir.y);
        c = mix(c, glow, h * 0.6);
        c += vec3(1.0, 0.45, 0.1) * gs_specks(dir, dist, vec3(0.1, 0.5, 0.07) * gs_time(), 1.5, 0.04) * 1.5;
    }

    // Clouds in front of the ground: when the camera flies above or inside them, or a mountain reaches
    // past their base. (deferred draws them where only sky is behind.)
    if (!is_sky && eye_dry && overworld
        && (cameraPosition.y > GS_CLOUD_LOW - 2.0 || cameraPosition.y + position.y > GS_CLOUD_LOW)) {
        vec4 clouds = gs_clouds_along(dir, c, dist);
        c = mix(c, clouds.rgb, clouds.a);
    }

    if (overworld && eye_dry) {
        vec3 sun = gs_sun_dir();
        vec2 seed = gs_event_seed();
        // Rainbows while the ground is still wet after rain: a ring 42 degrees around the point opposite
        // the sun, red outside, so only a low sun lifts it above the horizon. Now and then a second,
        // fainter one at 51 degrees with its colours reversed. In front of far land it is fainter.
        float bow_angle = degrees(acos(clamp(dot(dir, -sun), -1.0, 1.0)));
        float seen = (is_sky ? 1.0 : smoothstep(30.0, 140.0, dist) * 0.6) * smoothstep(-0.03, 0.05, dir.y)
            * smoothstep(0.0, 0.08, sun.y) * gs_dayf();
        float wet_air = clamp(rainwater * 1.5, 0.0, 1.0) * (1.0 - rainStrength * 0.8) * (1.0 - thunderStrength);
        if (wet_air * seen > 0.0) {
            float k = (bow_angle - 40.0) / 2.4;
            vec3 bow = gs_spectrum(0.78 * (1.0 - clamp(k, 0.0, 1.0))) * smoothstep(0.0, 0.25, k) * smoothstep(1.0, 0.75, k);
            // Inside the bow the sky is a little brighter.
            bow += vec3(0.06) * smoothstep(42.0, 38.0, bow_angle);
            if (gs_hash13(vec3(seed, 21.0)) < 0.3) {
                float k2 = (bow_angle - 50.0) / 3.6;
                bow += gs_spectrum(0.78 * clamp(k2, 0.0, 1.0)) * smoothstep(0.0, 0.25, k2) * smoothstep(1.0, 0.75, k2) * 0.35;
            }
            c += bow * wet_air * seen * 0.45;
        }
        // Fog bows: a broad white ring, on some damp mornings and evenings in humid, cool biomes.
        float damp = smoothstep(0.7, 0.9, rainfall) * (1.0 - smoothstep(0.7, 1.0, temperature)) * gs_sun_low();
        if (damp * seen > 0.0 && gs_hash13(vec3(seed, 31.0)) < 0.35) {
            float kf = (bow_angle - 34.0) / 8.0;
            c += vec3(0.95, 0.97, 1.0) * smoothstep(0.0, 0.5, kf) * smoothstep(1.0, 0.5, kf) * damp * seen * (1.0 - rainStrength) * 0.12;
        }
        // A solar eclipse dims the land to a cold dusk (deferred dims the sky).
        vec2 ecl = gs_solar_eclipse();
        if (!is_sky) {
            c *= mix(vec3(1.0), vec3(0.28, 0.32, 0.42), ecl.y);
        }
        // A lunar eclipse: the moon turns copper red.
        float lun = gs_lunar_eclipse();
        if (is_sky && lun > 0.0) {
            float by_moon = 1.0 - smoothstep(0.1, 0.2, acos(clamp(dot(dir, gs_moon_dir()), -1.0, 1.0)));
            c = mix(c, vec3(gs_luma(c)) * vec3(1.0, 0.3, 0.18) * 0.9, by_moon * lun);
        }
    }

    // The light shafts, blurred a little (they were marched at half size with a jitter).
    vec2 px = 1.5 / gs_resolution();
    vec3 rays = textureLod(colortex7, texcoord, 0.0).rgb;
    rays += textureLod(colortex7, texcoord + vec2(px.x, px.y), 0.0).rgb;
    rays += textureLod(colortex7, texcoord + vec2(-px.x, px.y), 0.0).rgb;
    rays += textureLod(colortex7, texcoord + vec2(px.x, -px.y), 0.0).rgb;
    rays += textureLod(colortex7, texcoord - px, 0.0).rgb;
    rays /= 5.0;

    // Under water: things lose their red with distance and sink into blue fog; specks drift in the light.
    float uw = isEyeInWater == 1 ? 1.0 : 0.0;
    if (uw > 0.0) {
        vec3 water = vec3(0.10, 0.42, 0.52) * (0.3 + 0.7 * gs_eye_light().y) * mix(0.3, 1.0, gs_dayf());
        float f = 1.0 - exp(-dist * 0.025);
        c = mix(c, mix(c * vec3(0.75, 0.95, 1.0), water, f), uw);
        c += (rays * 6.0 + water * 0.5) * gs_specks(dir, dist, vec3(0.05, 0.03, -0.04) * gs_time(), 0.9, 0.025) * uw;
    }

    c += rays;
    vec3 glow = textureLod(colortex3, texcoord, 0.0).rgb * BLOOM_STRENGTH;
    // Lava's own glow (composite gathers it, composite1 blurs it), in its light's colour, smooth at any
    // distance.
    glow += vec3(1.0, 0.42, 0.07) * textureLod(colortex6, texcoord, 0.0).g * 0.35;
    // Very strong glow (far lava) is capped by its brightest channel, keeping its hue, so it adds orange
    // instead of burning out to white. Glow up to 0.6 (ordinary bloom) passes unchanged.
    float gl = gs_max3(glow);
    if (gl > 0.6) {
        glow *= (0.6 + 0.6 * (1.0 - exp(-(gl - 0.6)))) / gl;
    }
    c += glow;

    // Exposure: brighter in the dark, as an eye adapts (from the light at the camera, eased over seconds).
    float ev = EXPOSURE;
#ifdef AUTO_EXPOSURE
    float sky_light = gs_eye_light().y * mix(0.25, 1.0, gs_dayf());
    float seen_light = max(sky_light, gs_eye_light().x * 0.6);
    ev *= mix(1.25, 0.9, smoothstep(0.0, 0.9, seen_light));
#endif

    // Tone: to linear light, exposure, the film curve, back; then the grade.
    vec3 lin = pow(max(c, vec3(0.0)), vec3(2.2)) * ev;
    float golden = gs_sun_low() * gs_dayf() * (1.0 - rainStrength * 0.7) * 0.5 * (overworld ? 1.0 : 0.0);
    lin *= mix(vec3(1.0), vec3(1.1, 1.0, 0.82), golden);
    c = pow(gs_filmic(lin * 0.85), vec3(1.0 / 2.2));
    c = mix(vec3(gs_luma(c)), c, SATURATION);
    out_color = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
