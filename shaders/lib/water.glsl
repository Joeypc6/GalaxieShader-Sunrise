// Galaxy Sky: water and the Nether portal (the WGSL pack's gs_water and gs_portal). gbuffers_water
// includes this: colortex4 holds the opaque world with its sky (deferred wrote it), depthtex1 its depth.
#if !defined GS_WATER_LIB
#define GS_WATER_LIB 1

ivec2 gs_screen_texel(vec2 screen) {
    ivec2 size = ivec2(gs_resolution());
    return clamp(ivec2(screen * vec2(size)), ivec2(0), size - ivec2(1));
}

// How far from the camera, in blocks, the solid world behind a screen position lies.
float gs_behind(vec2 screen) {
    float depth = texelFetch(depthtex1, gs_screen_texel(screen), 0).r;
    if (depth >= 1.0) {
        return 10000.0;
    }
    return length(gs_player_pos(screen, depth));
}

vec3 gs_opaque_color(vec2 screen) {
    return texelFetch(colortex4, gs_screen_texel(screen), 0).rgb;
}

vec4 gs_water(GsSurfaceIn i) {
    vec3 world = i.position + cameraPosition;
    float dist = length(i.position);
    vec3 v = i.position / -dist;
    bool top = i.top;
    float t = gs_time() * WAVE_SPEED;
    vec3 l = gs_light_dir();

    // Top faces follow the waves plus small ripples that make the sparkles; side faces keep their normal.
    // Level of detail: what is finer than a pixel fades into roughness (gs_water_footprint).
    vec3 n = i.normal;
    float rough = 0.0;
    if (top) {
        float f = gs_water_footprint(i.position);
        // Shading keeps a wave only while it spans several pixels (3x the footprint), not just one: the pack's
        // waves are regular sine trains, and kept down to a pixel they line up into even bands far out.
        // Distant water then turns smooth and mirror-like, its lost slope widening the sun's glint instead.
        vec4 waves = gs_water_normal_lod(world.xz, f * 3.0);
        // Past ~32 blocks the long swells, though wider than a pixel, still read as straight stripes (the
        // trains are perfectly regular): ease their tilt down to a tenth by ~160 blocks, the lost tilt
        // widening the glint as roughness, so open water further out looks calm and clear.
        float calm = mix(1.0, 0.1, smoothstep(32.0, 160.0, dist));
        vec2 tilt = waves.xz / max(waves.y, 0.001);
        n = normalize(vec3(tilt.x * calm, 1.0, tilt.y * calm));
        rough = waves.w + dot(tilt, tilt) * (1.0 - calm * calm) * 0.5;
        // The ripples are about a quarter block across: gone, as roughness, a few dozen blocks out.
        float ripple_keep = gs_wave_keep(25.0, f);
        if (ripple_keep > 0.0) {
            vec2 ripple = vec2(
                gs_noise(vec3(world.xz * 4.0, t * 0.7)) - 0.5,
                gs_noise(vec3(world.xz * 4.0 + vec2(7.3, 1.9), t * 0.7)) - 0.5);
            n = normalize(n + vec3(ripple.x, 0.0, ripple.y) * 0.35 * ripple_keep);
        }
        rough += 0.01 * (1.0 - ripple_keep * ripple_keep);
        // Raindrop rings are finer still; past them, skip their nine-cell search entirely.
        float impact_keep = gs_wave_keep(85.0, f) * smoothstep(0.85, 0.99, i.light.y);
        if (impact_keep > 0.0) {
            vec2 impacts = gs_rain_ripples(world.xz) * impact_keep;
            n = normalize(n + vec3(impacts.x, 0.0, impacts.y));
        }
    }
    if (dot(n, v) < 0.0) {
        n = -n;
    }

    // Refraction: what lies behind the water, shifted by the waves, more where the water is deeper.
    float thick_here = max(gs_behind(i.screen) - dist, 0.0);
    // (The WGSL screen ran downward; here it runs up, so the shift's y turns over.)
    vec2 shift = n.xz * vec2(1.0, -1.0) * 0.04 * clamp(thick_here, 0.0, 1.0) / (1.0 + dist * 0.08);
    vec2 ruv = clamp(i.screen + shift, vec2(0.001), vec2(0.999));
    float behind_shifted = gs_behind(ruv);
    float thick = behind_shifted - dist;
    if (thick < 0.0) {
        // The shifted ray would show something in front of the water.
        ruv = i.screen;
        thick = thick_here;
    }
    // Falling water is a thin sheet, however far the land behind it is: without this a waterfall
    // against the sky was as dark as the deep sea.
    if (!top) {
        thick = min(thick, 3.5);
    }
    vec3 refracted = gs_opaque_color(ruv);

    float day = mix(0.15, 1.0, gs_dayf()) * max(i.light.y, 0.25);
    vec3 col;
    if (isEyeInWater == 1) {
        // From below: the world above shows in a round window overhead, the deep reflects around it.
        // The surface glitters where the waves tilt toward the light.
        float window = smoothstep(0.35, 0.65, max(dot(n, v), 0.0));
        float sparkle = pow(max(dot(n, normalize(l + v)), 0.0), 60.0) * 0.6;
        col = mix(vec3(0.03, 0.2, 0.3) * day, refracted * 1.15 + vec3(0.1, 0.25, 0.3) * day, window);
        col += gs_light_color() * sparkle * day;
        return vec4(col, 1.0);
    }

    // Water takes red first, then green: shallow water is turquoise, deep water dark blue.
    vec3 absorb = exp(-thick * vec3(0.42, 0.09, 0.055));
    vec3 scatter = mix(vec3(0.03, 0.42, 0.45), vec3(0.01, 0.07, 0.22), 1.0 - exp(-thick * 0.12)) * day;
    col = mix(refracted * absorb, scatter, 1.0 - exp(-thick * 0.25));

    // Reflection: the mirror, else the sky along the reflected ray.
    float fresnel = 0.02 + 0.98 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
    vec3 r = reflect(-v, n);
    r.y = abs(r.y);
    vec3 reflected = mix(gs_sky_color(), gs_atmosphere(r, gs_sun_dir()), gs_dayf() * (1.0 - rainStrength));
#ifdef WATER_MIRROR
    // The mirror is the world flipped about the flat water plane, so only flat tops may use it: waterfalls
    // and the sides of flowing water reflect the sky. The format has no planar mirror, so the world is
    // traced on screen (as the puddles are) along the reflected ray of the flat plane, tilted a little by
    // the waves as the WGSL mirror was shifted by them; where the trace finds nothing the pack's sky shows
    // (the night panorama, the day's air, the clouds' grey).
    if (top) {
        vec3 sky_r = gs_puddle_sky(-v, world, n);
        vec3 wavy = normalize(vec3(n.x * 0.3, 1.0, n.z * 0.3));
        vec4 mirror = gs_trace_mirror(i.position + vec3(0.0, 0.05, 0.0), reflect(-v, wavy),
            22, 0.3, 0.5, 150.0, 240.0);
        reflected = mix(sky_r, mirror.rgb, mirror.a);
    }
#endif
    col = mix(col, reflected, fresnel * (top ? 1.0 : 0.5));

    // Foam: along shores and rocks where the water is thin, and on falling water.
    float foam = 0.0;
    if (top) {
        float pattern = gs_noise(vec3(world.xz * 3.0 + gs_wind_dir() * t * 0.4, t * 0.6));
        float edge = 1.0 - smoothstep(0.0, 0.7, thick_here);
        foam = edge * smoothstep(0.35, 0.75, pattern + (1.0 - smoothstep(0.0, 0.25, thick_here)) * 0.5);
    } else {
        // Falling water: thin streaks running down, faint, and fainter still by night.
        float streak = gs_noise(vec3((world.x + world.z) * 7.0, world.y * 0.3 + t * 2.5, world.x - world.z));
        foam = smoothstep(0.55, 0.95, streak) * 0.22 * mix(0.2, 1.0, gs_dayf());
    }
    // Foam is only as bright as the light on it.
    col = mix(col, vec3(0.95, 0.97, 1.0) * day, foam);

    // Sun glints: a sharp highlight plus sparkles from the ripples; bloom makes them glow.
    vec3 half_vec = normalize(l + v);
    float nh = max(dot(n, half_vec), 0.0);
    // The slope the level of detail removed widens the glints (and lowers them, so the light they carry
    // stays the same): far water shows one soft path of sunlight instead of a field of flickering points.
    float p1 = 500.0 / (1.0 + 500.0 * rough);
    float p2 = 2500.0 / (1.0 + 2500.0 * rough);
    float glint = (pow(nh, p1) * 1.2 * (p1 / 500.0) + pow(nh, p2) * 4.0 * (p2 / 2500.0)) * max(i.light.y, 0.2)
        * (top ? 1.0 : 0.0) * gs_cloud_shadow(i.position);
    col += gs_light_color() * glint;
    col += vec3(0.45, 0.55, 0.75) * gs_storm_flash() * max(n.y, 0.0) * i.light.y * 0.25;
    return vec4(min(col, vec3(1.0)), 1.0);
}

// The Nether portal: a thin sheet of violet liquid light. What lies behind shows through it, bent by
// slow ripples and tinted; the sheet glows from inside, brighter where the ripples crest, and shines at
// a flat angle like glass. Drawn in world space, so the blocks of one portal join up.
float gs_portal_height(vec2 p, float t) {
    float warp = gs_noise(vec3(p * 0.9 + vec2(0.0, t * 0.15), t * 0.1)) - 0.5;
    return gs_noise(vec3(p * 2.2 + warp * 2.0 + vec2(t * 0.1, -t * 0.35), t * 0.25))
        + 0.5 * gs_noise(vec3(p * 5.0 - warp * 3.0 + vec2(0.0, -t * 0.6), t * 0.4));
}

vec4 gs_portal(GsSurfaceIn i) {
    vec3 world = i.position + cameraPosition;
    vec2 p = vec2(world.x + world.z, world.y);
    float t = gs_time();
    float dist = length(i.position);
    float h = gs_portal_height(p, t);
    vec2 slope = vec2(gs_portal_height(p + vec2(0.06, 0.0), t) - h, gs_portal_height(p + vec2(0.0, 0.06), t) - h) / 0.06;

    // Behind the sheet, bent by the ripples (less from afar, and not if that would show something in front).
    vec2 ruv = clamp(i.screen + slope * vec2(1.0, -1.0) * 0.02 / (1.0 + dist * 0.1), vec2(0.001), vec2(0.999));
    if (gs_behind(ruv) < dist) {
        ruv = i.screen;
    }
    vec3 behind = gs_opaque_color(ruv);

    vec3 v = normalize(-i.position);
    float facing = abs(dot(i.normal, v));
    vec3 glow = mix(vec3(0.10, 0.01, 0.24), vec3(0.50, 0.14, 0.85), smoothstep(0.45, 1.2, h));
    vec3 col = behind * vec3(0.55, 0.3, 0.8) * 0.55 + glow * (0.55 + 0.1 * sin(t * 1.3));
    // Crests catch the light as thin bright lines; the sheet mirrors violet at a flat angle.
    col += vec3(0.9, 0.6, 1.0) * smoothstep(1.6, 2.6, length(slope)) * 0.35;
    col += vec3(0.6, 0.3, 1.0) * pow(1.0 - facing, 4.0) * 0.6;
    return vec4(col, 1.0);
}

#endif
