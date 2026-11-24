// Galaxy Sky: the sky (the WGSL pack's sky.wgsl). By day sunlight scattered by the air with volumetric
// clouds; by night the pack's painted sky (night_sky.png: a blue gas giant with its moons over glowing
// nebulae) under sharp twinkling stars and, in cold biomes now and then, an aurora. The giant and its moons
// show by day too, pale behind the air. The sun, the moon and the stars are drawn here: shaders.properties
// turns vanilla's off (sun, moon, stars, sky = false).
#if !defined GS_SKY
#define GS_SKY 1

// The painted nebulae along a ray. u is the compass direction, v runs from the zenith (0) to 18 degrees
// below the horizon (1).
vec3 gs_sky_image(vec3 d) {
    float u = atan(d.z, d.x) / 6.2831853 + 0.5;
    float v = (1.5707963 - asin(clamp(d.y, -1.0, 1.0))) / 1.8849556;
    return textureLod(night_sky, vec2(u, clamp(v, 0.001, 0.999)), 0.0).rgb;
}

// One of the giant and its moons: xyz the direction, w the sine of the angular radius.
vec4 gs_body(int i) {
    if (i == 0) return vec4(0.0, 0.5878, -0.8090, 0.2588);
    if (i == 1) return vec4(0.1853, 0.4540, -0.8715, 0.04711);
    if (i == 2) return vec4(-0.2825, 0.7986, -0.5314, 0.02967);
    if (i == 3) return vec4(0.2890, 0.7880, -0.5436, 0.02007);
    return vec4(-0.3234, 0.3256, -0.8885, 0.01222);
}

// How many turns an hour each body makes (whole numbers: the clock wraps hourly).
float gs_body_turns(int i) {
    if (i == 0) return 10.0;
    if (i == 1) return 24.0;
    if (i == 2) return -18.0;
    if (i == 3) return 36.0;
    return 45.0;
}

// The giant and its moons along a ray: a flat picture held up toward the giant in the north, 36 degrees
// up, covering 26 degrees to each side. rgb is the colour times the coverage, a the coverage.
vec4 gs_sky_bodies(vec3 d) {
    vec3 centre = vec3(0.0, 0.5877853, -0.8090170);
    vec3 right = vec3(-1.0, 0.0, 0.0);
    vec3 up = vec3(0.0, 0.8090170, 0.5877853);
    float z = dot(d, centre);
    if (z < 0.5) {
        return vec4(0.0);
    }
    vec2 p = vec2(dot(d, right), dot(d, up)) / (z * 0.4877326);
    if (abs(p.x) >= 0.998 || abs(p.y) >= 0.998) {
        return vec4(0.0);
    }
    vec4 result = textureLod(sky_bodies, vec2(0.5 + p.x * 0.5, 0.5 - p.y * 0.5), 0.0);

    // The painted picture gives the shapes; the surfaces come from planet_maps.png, turned by the time,
    // and are lit here the way the texture generator lit them.
    for (int i = 0; i < 5; i++) {
        vec4 b = gs_body(i);
        vec3 t1 = normalize(cross(vec3(0.0, 1.0, 0.0), b.xyz));
        vec3 t2 = cross(b.xyz, t1);
        vec3 off = d - b.xyz * dot(d, b.xyz);
        vec2 q = vec2(dot(off, t1), dot(off, t2)) / b.w;
        float r = length(q);
        if (r >= 1.0 || dot(d, b.xyz) < 0.0) {
            continue;
        }
        vec3 n = vec3(q, sqrt(1.0 - r * r));
        vec3 s = n;
        float v = 0.0;
        if (i == 0) {
            // The giant turns about its tilted axis.
            s = vec3(n.x * 0.9492 - n.y * 0.3146, n.x * 0.3146 + n.y * 0.9492, n.z);
            v = clamp(0.5 - asin(s.y) / 3.1415927, 0.004, 0.996) / 1.5;
        } else {
            v = (8.0 + float(i - 1) + clamp(0.5 - asin(s.y) / 3.1415927, 0.12, 0.88)) / 12.0;
        }
        float u = atan(s.x, s.z) / 6.2831853 - gs_time() * gs_body_turns(i) / 3600.0;
        vec3 c = textureLod(planet_maps, vec2(u, v), 0.0).rgb;
        float ndl = dot(n, vec3(-0.6211, 0.4208, 0.6612));
        float lit = smoothstep(-0.08, 0.30, ndl) * (0.25 + 0.75 * pow(max(ndl, 0.0), 0.8));
        c *= (0.55 + 0.45 * sqrt(n.z)) * (lit * 1.15 + 0.012);
        if (i == 0) {
            c += vec3(0.25, 0.55, 1.0) * pow(1.0 - n.z, 3.0) * (0.15 + 0.85 * lit) * 0.7;
            c += vec3(0.02, 0.05, 0.12) * (1.0 - lit) * 0.5;
        }
        float cover = 1.0 - smoothstep(1.0 - clamp(0.0015 / b.w, 0.01, 0.3), 1.0, r);
        result = result * (1.0 - cover) + vec4(c * cover, cover);
    }
    return result;
}

// Stars: one per cell of a fine grid over the sky, each with its own brightness, colour and twinkle.
vec3 gs_star_layer(vec3 d, float t, float scale, float chance, float size) {
    vec3 cell = floor(d * scale);
    float h = gs_hash13(cell);
    if (h < 1.0 - chance) {
        return vec3(0.0);
    }
    // The star sits where its cell's point lies on the sky, so it shows from wherever the cell is seen.
    vec3 star_dir = normalize(cell + gs_hash33(cell + vec3(3.0)) * 0.6 + vec3(0.2));
    float dist = length(d - star_dir) * scale;
    float core = smoothstep(size, 0.0, dist);
    float k = gs_hash13(cell + vec3(7.0));
    float bright = mix(0.45, 1.6, pow(k, 3.0));
    float twinkle = 0.75 + 0.25 * sin(t * (1.5 + h * 4.0) + h * 60.0);
    // Most stars are white, some bluish, some warm.
    vec3 colour = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), gs_hash13(cell + vec3(11.0)));
    return mix(vec3(1.0), colour, 0.6) * core * bright * twinkle;
}

// Two layers: fewer bright stars, and many faint ones behind them.
vec3 gs_stars(vec3 d, float t) {
    return gs_star_layer(d, t, 110.0, 0.08 * STAR_DENSITY, 0.3)
        + gs_star_layer(d, t, 230.0, 0.12 * STAR_DENSITY, 0.35) * 0.45;
}

// Aurora: curtains of green light turning violet higher up, with fine vertical rays. Only where the biome
// at the camera is cold, and only now and then: it fades in and out over minutes.
vec3 gs_aurora(vec3 d) {
    float cold = 1.0 - smoothstep(0.0, 0.2, temperature);
    if (AURORA <= 0.0 || cold <= 0.0 || d.y < 0.05) {
        return vec3(0.0);
    }
    float t = gs_time();
    float showing = smoothstep(0.55, 0.72, gs_noise(vec3(t * 0.008, 3.3, 9.1)));
    if (showing <= 0.0) {
        return vec3(0.0);
    }
    vec2 p = d.xz / (d.y + 0.25);
    float glow = 0.0;
    for (int k = 0; k < 3; k++) {
        vec2 q = p * (1.0 + 0.15 * float(k));
        float wave = gs_noise(vec3(q.x * 1.2 + t * 0.02, q.y * 0.3, t * 0.03 + float(k) * 5.0));
        float curtain = pow(clamp(1.0 - abs(wave - 0.5) * 4.0, 0.0, 1.0), 3.0);
        float rays = 0.55 + 0.45 * gs_noise(vec3(q.x * 14.0, q.y * 2.0, t * 0.2));
        glow += curtain * rays;
    }
    vec3 colour = mix(vec3(0.1, 1.0, 0.45), vec3(0.55, 0.2, 0.9), smoothstep(0.25, 0.8, d.y));
    float shape = smoothstep(0.05, 0.25, d.y) * (1.0 - smoothstep(0.75, 1.0, d.y));
    return colour * glow * 0.4 * shape * cold * showing * AURORA;
}

// Shooting stars: time is cut into slots of 12 seconds, and in about one slot of five a single streak
// crosses a random part of the upper sky in under a second: on average one a minute.
vec3 gs_meteor(vec3 d) {
    float slot = floor(gs_time() / 12.0);
    vec3 seed = vec3(slot, 17.0, 4.0);
    float p = (gs_time() - slot * 12.0) / 0.8;
    if (p > 1.0 || gs_hash13(seed) > 0.2 || d.y < 0.0) {
        return vec3(0.0);
    }
    vec3 r = gs_hash33(seed) - 0.5;
    vec3 start = normalize(vec3(r.x, abs(r.y) + 0.25, r.z));
    vec3 along = normalize(cross(start, gs_hash33(seed + vec3(9.0)) - 0.5));
    // The head runs just under 30 degrees; the tail follows a third of the way behind.
    vec3 head = normalize(start + along * 0.5 * p);
    vec3 tail = normalize(start + along * 0.5 * max(p - 0.3, 0.0));
    vec3 seg = head - tail;
    float h = clamp(dot(d - tail, seg) / max(dot(seg, seg), 1.0e-6), 0.0, 1.0);
    float off = length(d - (tail + seg * h));
    float streak = smoothstep(0.0035, 0.0, off) * h * h + smoothstep(0.008, 0.0, length(d - head));
    return vec3(0.85, 0.93, 1.0) * streak * sin(p * 3.1415927) * 1.6;
}

// A great comet, in about one stretch of nights in five, drawn after photographs of Hale-Bopp and NEOWISE:
// a tiny bright nucleus in a green-cyan coma; a broad, curved dust tail that fans out behind the orbit with
// faint striations and fades over some 30 degrees; and a narrow, straight blue ion tail with streamers, both
// pointing away from the sun. It wanders about 20 degrees a night.
vec3 gs_comet(vec3 d) {
    float seed = gs_event_seed().x;
    if (gs_hash13(vec3(seed, 3.0, 1.0)) > 0.2) {
        return vec3(0.0);
    }
    vec3 h = gs_hash33(vec3(seed, 8.0, 2.0));
    float swing = gs_time() * 0.0017453293;
    float az = h.x * 6.2831853 + 0.35 * sin(swing);
    float el = 0.45 + 0.35 * h.y + 0.08 * sin(swing * 2.0);
    vec3 c = vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az));
    float z = dot(d, c);
    if (z < 0.5) {
        return vec3(0.0);
    }
    // Sky coordinates around the head, gnomonic so the long tails stay straight: x away from the sun.
    vec3 sun = gs_sun_dir();
    vec3 away = normalize(c * dot(sun, c) - sun);
    vec3 side = normalize(cross(c, away));
    vec2 p = vec2(dot(d, away), dot(d, side)) / z;
    float r = length(p);
    float s = max(p.x, 0.0);

    float nucleus = exp(-r * r * 60000.0) * 2.2;
    float coma = exp(-r * 90.0) * 0.4 + exp(-r * r * 1500.0) * 0.25;

    // Ion tail: narrow and straight, streamers drifting slowly outward.
    float ion_w = 0.003 + s * 0.03;
    float streamers = 0.5 + 0.5 * gs_noise(vec3(p.y / ion_w * 2.5, s * 5.0 - gs_time() * 0.01, 7.0));
    float ion = exp(-pow(p.y / ion_w, 2.0)) * exp(-s * 2.4) * smoothstep(0.0, 0.03, p.x) * streamers;

    // Dust tail: bends behind the orbit and fans out; striations run out from the nucleus.
    float dy = p.y - s * s * 0.7;
    float dust_w = 0.008 + s * 0.3;
    float striae = 0.7 + 0.3 * gs_noise(vec3(dy / (s + 0.015) * 12.0, s * 1.2, 3.0));
    float dust = exp(-pow(dy / dust_w, 2.0)) * exp(-s * 2.2) * smoothstep(-0.01, 0.04, p.x) * striae;

    return vec3(1.0, 0.98, 0.92) * nucleus + vec3(0.6, 1.0, 0.85) * coma
        + vec3(0.3, 0.55, 1.0) * ion * 0.16 + vec3(1.0, 0.9, 0.72) * dust * 0.85;
}

// The moon: a round, cratered ball (planet_maps.png's grey moon, its face always toward the world) in
// vanilla's phase (the moonPhase uniform), the terminator soft, a faint earthshine on the dark side.
// 4 degrees across. rgb its light, a how much of the sky behind it it hides.
vec4 gs_moon(vec3 d) {
    vec3 m = gs_moon_dir();
    float rad = 0.035;
    vec3 up_ref = abs(m.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 t1 = normalize(cross(up_ref, m));
    vec3 t2 = cross(m, t1);
    vec3 off = d - m * dot(d, m);
    vec2 q = vec2(dot(off, t1), dot(off, t2)) / rad;
    float r = length(q);
    if (r >= 1.0 || dot(d, m) < 0.0) {
        return vec4(0.0);
    }
    vec3 n = vec3(q, sqrt(1.0 - r * r));
    // Phase 0 full, 4 new: the light comes from the viewer's side at full moon, from behind at new moon;
    // waning moons are lit on one side, waxing ones on the other.
    float a = float(moonPhase) * 0.7853982;
    vec3 l = vec3(-sin(a), 0.0, cos(a));
    float lit = smoothstep(-0.04, 0.1, dot(n, l));
    float u = atan(n.x, n.z) / 12.566371 + 0.25;
    float v = (8.0 + clamp(0.5 - asin(n.y) / 3.1415927, 0.12, 0.88)) / 12.0;
    vec3 tex = textureLod(planet_maps, vec2(u, v), 0.0).rgb;
    // Dark grey seas, bright highlands and crater rims.
    vec3 grey = mix(vec3(0.33, 0.33, 0.36), vec3(0.93, 0.92, 0.88), smoothstep(0.12, 0.7, gs_luma(tex)));
    float limb = 0.75 + 0.25 * sqrt(n.z);
    vec3 rgb = grey * limb * (lit * 1.05 + 0.035);
    float cover = 1.0 - smoothstep(0.97, 1.0, r);
    return vec4(rgb * cover, cover);
}

// The Overworld's sky along the ray d, in the pack's gamma values (the WGSL sky stage).
vec3 gs_sky(vec3 d) {
    vec3 sun = gs_sun_dir();
    // A solar eclipse turns the day sky to dusk: the stars come out.
    vec2 ecl = gs_solar_eclipse();
    float dayf = gs_dayf() * (1.0 - 0.88 * ecl.y);
    float clear = 1.0 - rainStrength;
    vec3 ecl_side = normalize(cross(sun, vec3(0.0, 0.0, 1.0)));
    vec3 ecl_moon = normalize(sun + ecl_side * ecl.x);
    float hidden = 1.0 - smoothstep(0.040, 0.043, acos(clamp(dot(d, ecl_moon), -1.0, 1.0)));
    vec4 bodies = gs_sky_bodies(d);

    // Day: the scattered sky, greyer in rain, and the sun's disc in the colour its light arrives with.
    vec3 day = gs_atmosphere(d, sun);
    // The giant and its moons hang in the day sky like the moon does: their lit parts pale through the
    // air, their dark parts the colour of the sky.
    float body = clamp(gs_luma(bodies.rgb) * 1.6, 0.0, 1.0);
    day = mix(day, day * 0.65 + bodies.rgb * 0.35 + vec3(0.55, 0.62, 0.7) * body, body * 0.75);
    day = mix(day, vec3(gs_luma(day)) * 0.7, rainStrength * 0.75);
    float toward = max(dot(d, sun), 0.0);
    day += gs_light_color() * smoothstep(0.9992, 0.9996, toward) * 2.5 * clear * (1.0 - hidden);
    // The moon by day: its lit part pale through the air, its dark part the colour of the sky.
    vec4 moon = gs_moon(d);
    day += moon.rgb * 0.45 * clear;

    // Night: the painted sky, the nebulae brightened by the option, stars everywhere but in front of the
    // giant and its moons, a glow around the moon, the aurora. The nebulae and the stars turn once an hour;
    // the nebulae also billow.
    vec3 night = gs_sky_image(gs_sky_drift(d, 1.0, 20.0, 0.025)) * 1.6 * GALAXY_BRIGHTNESS
        + gs_stars(gs_sky_drift(d, 1.0, 0.0, 0.0), gs_time());
    // The giant's blue glow, around the giant itself.
    float giant_ang = acos(clamp(dot(d, vec3(0.0, 0.5878, -0.8090)), -1.0, 1.0));
    night += vec3(0.10, 0.30, 0.55) * 0.3 * exp(-max(giant_ang - 0.2618, 0.0) / 0.2618 * 5.0);
    night = night * (1.0 - bodies.a) + bodies.rgb;
    // The moon hides the stars behind it; its glow grows with the lit part.
    night = night * (1.0 - moon.a) + moon.rgb;
    float moon_lit = 0.5 + 0.5 * cos(float(moonPhase) * 0.7853982);
    night += vec3(0.15, 0.2, 0.35) * pow(max(dot(d, gs_moon_dir()), 0.0), 24.0) * 0.4 * moon_lit;
    night += gs_aurora(d) + gs_meteor(d) + gs_comet(d);
    night *= 1.0 - 0.8 * rainStrength;

    vec3 col = mix(night, day, dayf);
    if (ecl.y > 0.0) {
        // The moon's black disc, the corona streaming out around it at totality, and a sunset glow
        // all around the horizon.
        col = mix(col, vec3(0.004, 0.005, 0.01), hidden * smoothstep(0.1, 0.5, ecl.y));
        float ang = acos(clamp(toward, -1.0, 1.0));
        vec2 around = vec2(dot(d, ecl_side), dot(d, cross(ecl_side, sun))) / max(sin(ang), 0.001);
        float streaks = 0.45 + 0.75 * gs_noise(vec3(around * 3.5, 2.0)) * gs_noise(vec3(around * 9.0, 5.0));
        float corona = (exp(-max(ang - 0.04, 0.0) * 16.0) * streaks + exp(-max(ang - 0.04, 0.0) * 70.0))
            * smoothstep(0.7, 1.0, ecl.y) * (1.0 - hidden) * step(0.0, toward);
        col += vec3(1.0, 0.96, 0.9) * corona * 1.2 * clear;
        col += vec3(0.9, 0.45, 0.2) * pow(1.0 - max(d.y, 0.0), 6.0) * 0.3 * ecl.y * clear;
    }
    vec4 clouds = gs_clouds_along(d, col, 1.0e9);
    col = mix(col, clouds.rgb * (1.0 - 0.8 * ecl.y), clouds.a);
    vec3 storm_sky = mix(vec3(0.012, 0.018, 0.03), vec3(0.17, 0.21, 0.28), dayf);
    col = mix(col, storm_sky, rainStrength * thunderStrength * 0.35);
    col += vec3(0.35, 0.45, 0.7) * gs_storm_flash() * 0.3;
    // Below the horizon the sky shows only past the farthest land: there it turns into the haze far land
    // takes in composite4, not into the night's nebulae or the day's bright horizon.
    float below = smoothstep(0.0, -0.1, d.y);
    if (below > 0.0) {
        vec3 flat_d = normalize(vec3(d.x, 0.03, d.z));
        vec3 haze = mix(gs_fog_color(), gs_atmosphere(flat_d, sun), 0.5 * gs_dayf() * (1.0 - rainStrength));
        col = mix(col, haze * gs_biome_air().rgb, below);
    }
    return clamp(col, vec3(0.0), vec3(1.0));
}

#endif
