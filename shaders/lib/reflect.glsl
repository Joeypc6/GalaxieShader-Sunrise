// Galaxy Sky: the sky seen in a mirror (the WGSL pack's gs_puddle_sky): the night panorama or the day's
// air along the reflected ray, greyed by the cloud layer where the ray meets it, and storm flashes.
#if !defined GS_REFLECT
#define GS_REFLECT 1

vec3 gs_puddle_sky(vec3 dir, vec3 world, vec3 normal) {
    vec3 r = reflect(dir, normal);
    r.y = max(abs(r.y), 0.03);
    r = normalize(r);
    vec2 uv = vec2(atan(r.z, r.x) / 6.2831853 + 0.5,
        clamp((1.5707963 - asin(r.y)) / 1.8849556, 0.001, 0.999));
    vec3 night = textureLod(night_sky, uv, 0.0).rgb * 0.6;
    vec3 col = mix(night, gs_atmosphere(r, gs_sun_dir()), gs_dayf());
    vec3 cloud_hit = world + r * (max(GS_CLOUD_LOW + 15.0 - world.y, 0.0) / r.y);
    float cloud = gs_cloud_density(cloud_hit, false);
    vec3 grey = mix(vec3(0.015, 0.025, 0.045), vec3(0.3, 0.35, 0.42), gs_dayf());
    col = mix(col, grey * (1.0 - thunderStrength * 0.4), max(rainStrength * 0.65, cloud));
    return col + vec3(0.4, 0.5, 0.75) * gs_storm_flash();
}

// A screen-space mirror: the ray from `origin` along `ray` walked over the picture GS_MIRROR_SCENE and its
// depth GS_MIRROR_DEPTH (the including program defines both) in growing steps (`first` blocks, then
// i * i * `spread`), the hit refined by halving. rgb the colour there, a how far to trust it (off-screen
// and far hits fade back to the sky).
#if defined GS_MIRROR_SCENE
vec4 gs_trace_mirror(vec3 origin, vec3 ray, int count, float first, float spread, float fade_from,
                     float fade_to) {
    float previous_t = first * 0.6;
    for (int i = 1; i <= count; i++) {
        float t = first + float(i * i) * spread;
        vec3 point = origin + ray * t;
        vec3 s = gs_to_screen(point);
        if (s.z <= 0.0) {
            break;
        }
        vec2 uv = s.xy;
        if (any(lessThanEqual(uv, vec2(0.002))) || any(greaterThanEqual(uv, vec2(0.998)))) {
            break;
        }
        float depth = textureLod(GS_MIRROR_DEPTH, uv, 0.0).r;
        if (depth < 1.0) {
            float gap = length(point) - length(gs_player_pos(uv, depth));
            if (gap > 0.0 && gap < 0.2 + (t - previous_t) * 1.5) {
                float lo = previous_t;
                float hi = t;
                vec2 hit_uv = uv;
                for (int refine = 0; refine < 4; refine++) {
                    float mid = (lo + hi) * 0.5;
                    vec3 sample_point = origin + ray * mid;
                    vec2 probe = gs_to_screen(sample_point).xy;
                    float sample_depth = textureLod(GS_MIRROR_DEPTH, probe, 0.0).r;
                    if (sample_depth < 1.0 && length(sample_point) > length(gs_player_pos(probe, sample_depth))) {
                        hi = mid;
                        hit_uv = probe;
                    } else {
                        lo = mid;
                    }
                }
                float edge = min(min(hit_uv.x, hit_uv.y), min(1.0 - hit_uv.x, 1.0 - hit_uv.y));
                float confidence = smoothstep(0.01, 0.12, edge) * (1.0 - smoothstep(fade_from, fade_to, hi));
                return vec4(textureLod(GS_MIRROR_SCENE, hit_uv, 0.0).rgb, confidence);
            }
        }
        previous_t = t;
    }
    return vec4(0.0);
}
#endif

#endif
