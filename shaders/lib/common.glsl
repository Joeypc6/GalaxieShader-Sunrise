// Galaxy Sky: helpers shared by every stage (the WGSL pack's common.wgsl). Names start with gs_.
#if !defined GS_COMMON
#define GS_COMMON 1

// The pack's pictures (customTexture in shaders.properties; their .mcmeta set linear and clamp).
uniform sampler2D night_sky;
uniform sampler2D sky_bodies;
uniform sampler2D planet_maps;
uniform sampler2D cloud_noise;
uniform sampler2D cloud_shape;
uniform sampler2D cloud_detail;

// The cloud layer, in world blocks.
const float GS_CLOUD_LOW = 190.0;
const float GS_CLOUD_HIGH = 430.0;
// How much light a block of the densest cloud takes away.
const float GS_CLOUD_SIGMA = 0.03;
// The world's radius for the sky, in blocks: small enough that far clouds sink to the horizon.
const float GS_PLANET = 40000.0;

float gs_luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float gs_max3(vec3 c) {
    return max(c.r, max(c.g, c.b));
}

// A world-aligned unit normal into two numbers (octahedral) and back.
vec2 gs_encode_normal(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 e = n.xz;
    if (n.y < 0.0) {
        e = (1.0 - abs(n.zx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
    }
    return e;
}

vec3 gs_decode_normal(vec2 e) {
    vec3 n = vec3(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
    if (n.y < 0.0) {
        n.xz = (1.0 - abs(n.zx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
    }
    return normalize(n);
}

// The pack works in vanilla's gamma values, as the WGSL pack did inside: the format hands colours over
// as they are stored, so no conversion is needed at the edges.

// Vanilla's fog and sky colours of this frame.
vec3 gs_fog_color() {
    return fogColor;
}

vec3 gs_sky_color() {
    return skyColor;
}

// 1 by day, 0 by night, with a twilight that keeps sunsets bright.
float gs_dayf() {
    return smoothstep(-0.15, 0.05, gs_sun_dir().y);
}

// 1 while the sun sits on the horizon, 0 from a third of the way up.
float gs_sun_low() {
    return 1.0 - smoothstep(0.0, 0.35, abs(gs_sun_dir().y));
}

// The colour of the light that casts shadows: white sun, orange at sunset, pale blue moon.
vec3 gs_light_color() {
    vec3 sun = mix(vec3(1.0, 0.96, 0.9), vec3(1.0, 0.55, 0.25), gs_sun_low());
    vec3 moon = vec3(0.35, 0.45, 0.7) * 0.35;
    float day = smoothstep(-0.05, 0.1, gs_sun_dir().y);
    return mix(moon, sun, day) * (1.0 - 0.6 * rainStrength) * (1.0 - 0.35 * thunderStrength);
}

// Hash functions (Dave Hoskins style): a pseudo-random 0..1 value per point.
float gs_hash13(vec3 p) {
    vec3 q = fract(p * 0.1031);
    q += dot(q, q.zyx + 31.32);
    return fract((q.x + q.y) * q.z);
}

vec3 gs_hash33(vec3 p) {
    vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

// Distant sheet lightning, shared by clouds, rain and reflections; vanilla owns strikes and sound.
float gs_storm_flash() {
    if (gs_dimension() != 0 || thunderStrength <= 0.0 || STORM_FLASHES <= 0.0) {
        return 0.0;
    }
    float slot = floor(gs_time() / 12.0);
    float seed = gs_hash13(vec3(slot, 17.0, 83.0));
    float t = gs_time() - slot * 12.0 - 2.0 - seed * 7.0;
    float first = smoothstep(0.0, 0.025, t) * (1.0 - smoothstep(0.06, 0.16, t));
    float echo = smoothstep(0.23, 0.25, t) * (1.0 - smoothstep(0.28, 0.42, t));
    return (first + echo * 0.55) * step(0.48, seed) * rainStrength * thunderStrength * STORM_FLASHES;
}

// Smooth 3D value noise.
float gs_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    float c000 = gs_hash13(i);
    float c100 = gs_hash13(i + vec3(1.0, 0.0, 0.0));
    float c010 = gs_hash13(i + vec3(0.0, 1.0, 0.0));
    float c110 = gs_hash13(i + vec3(1.0, 1.0, 0.0));
    float c001 = gs_hash13(i + vec3(0.0, 0.0, 1.0));
    float c101 = gs_hash13(i + vec3(1.0, 0.0, 1.0));
    float c011 = gs_hash13(i + vec3(0.0, 1.0, 1.0));
    float c111 = gs_hash13(i + vec3(1.0, 1.0, 1.0));
    return mix(
        mix(mix(c000, c100, u.x), mix(c010, c110, u.x), u.y),
        mix(mix(c001, c101, u.x), mix(c011, c111, u.x), u.y),
        u.z);
}

// A fixed landscape of hollows: falling water levels shrink their edges and empty shallow ones first.
float gs_puddle(vec3 world, float wet) {
    float broad = gs_noise(vec3(world.xz * 0.28, world.y * 0.13));
    float detail = gs_noise(vec3(world.xz * 1.1, world.y * 0.31 + 7.0));
    float hollow = broad * 0.8 + detail * 0.2;
    float waterline = mix(0.86, 0.42, clamp(wet, 0.0, 1.0));
    return smoothstep(waterline, waterline + 0.035, hollow) * smoothstep(0.04, 0.2, wet);
}

// Expanding impact rings at fixed world positions, with independently timed drops in neighbouring cells.
vec2 gs_rain_ripples(vec2 xz) {
    if (gs_dimension() != 0 || biome_precipitation != 1 || rainStrength <= 0.0) {
        return vec2(0.0);
    }
    vec2 p = xz * 3.0;
    vec2 cell = floor(p);
    vec2 slope = vec2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 id = cell + vec2(float(x), float(y));
            vec3 seed = gs_hash33(vec3(id, 29.0));
            float age = fract(gs_time() * 1.8 + seed.z);
            vec2 delta = p - (id + vec2(0.15) + seed.xy * 0.7);
            float dist = length(delta);
            float ring = dist - age * 0.48;
            float envelope = exp(-ring * ring * 700.0) * (1.0 - age) * (1.0 - age) * smoothstep(0.0, 0.1, age);
            slope += delta / max(dist, 0.001) * cos(ring * 85.0) * envelope * step(seed.x, rainStrength);
        }
    }
    return slope * 0.08 * rainStrength;
}

// ---- Wind ----

// Where the wind blows to (xz), and how hard: rain and thunder add to the option.
vec2 gs_wind_dir() {
    return vec2(0.8, 0.6);
}

float gs_wind() {
    return WIND_STRENGTH * (0.6 + 0.9 * rainStrength + 0.5 * thunderStrength);
}

// A gust passing over a world xz position, -1..1: slow swells with quicker flutters on top.
float gs_gust(vec2 xz, float speed) {
    float t = gs_time() * speed;
    float along = dot(xz, gs_wind_dir());
    return sin(along * 0.35 - t * 1.6) * 0.6 + sin(along * 1.3 - t * 2.9 + xz.x * 0.7) * 0.4;
}

// ---- Water level of detail ----
// Far away one pixel covers several wave crests. Sampling the waves at the pixel's centre then gives rings and
// moire, and the sun's glint turns to noise. So every wave fades out as its length nears the pixel's footprint
// on the water, and the slope it would have added becomes roughness: the glint widens instead of sparkling.

// How much of a wave of wavenumber k (radians per block) to keep at a footprint of f blocks per pixel.
float gs_wave_keep(float k, float f) {
    return 1.0 - smoothstep(0.6, 2.2, k * f);
}

// The footprint on the water of the pixel at camera-relative position p, in blocks: the pixel's size at that
// distance, stretched where the view grazes the surface (capped, or the horizon would lose all its waves).
float gs_water_footprint(vec3 p) {
    float dist = length(p);
    float pixel = dist * 2.0 / max(gbufferProjection[1][1] * viewHeight, 1.0);
    float grazing = max(abs(p.y) / max(dist, 0.001), 0.08);
    return pixel / sqrt(grazing);
}

// One wave train: deep-water waves travel at a speed set by their length, and their crests are sharper
// than their troughs. Its slope (d height / d xz) and its height, filtered to footprint f: xy the slope,
// z the height, w the slope variance the filter removed.
vec4 gs_wave_train_lod(vec2 xz, vec2 dir, float k, float amp, float f) {
    float keep = gs_wave_keep(k, f);
    float omega = sqrt(9.8 * k) * 0.45 * WAVE_SPEED;
    float a = dot(xz, dir) * k - gs_time() * omega;
    float s = sin(a) * 0.5 + 0.5;
    float height = amp * (2.0 * pow(s, 1.5) - 1.0);
    float slope = amp * 1.5 * sqrt(s) * cos(a) * k;
    float lost = (amp * k) * (amp * k) * 0.5 * (1.0 - keep * keep);
    return vec4(dir * slope * keep, height * keep, lost);
}

// The waves at footprint f: xyz the surface normal, w the slope variance the filter removed.
vec4 gs_water_normal_lod(vec2 xz, float f) {
    float scale = WAVE_HEIGHT * (1.0 + 0.6 * rainStrength);
    vec4 w = gs_wave_train_lod(xz, vec2(0.8, 0.6), 0.4, 0.42, f);
    w += gs_wave_train_lod(xz, vec2(0.41, 0.91), 0.9, 0.25, f);
    w += gs_wave_train_lod(xz, vec2(1.0, -0.05), 1.7, 0.16, f);
    w += gs_wave_train_lod(xz, vec2(-0.36, 0.93), 3.1, 0.10, f);
    w += gs_wave_train_lod(xz, vec2(0.3, -0.95), 5.3, 0.07, f);
    vec2 slope = w.xy * scale;
    return vec4(normalize(vec3(-slope.x, 1.0, -slope.y)), w.w * scale * scale);
}

// The height of the waves at footprint f (block corners: f is at least the one-block spacing of the
// corners, so waves shorter than two blocks never fold into a coarser false swell).
float gs_wave_lod(vec2 xz, float f) {
    float h = gs_wave_train_lod(xz, vec2(0.8, 0.6), 0.4, 0.42, f).z;
    h += gs_wave_train_lod(xz, vec2(0.41, 0.91), 0.9, 0.25, f).z;
    h += gs_wave_train_lod(xz, vec2(1.0, -0.05), 1.7, 0.16, f).z;
    h += gs_wave_train_lod(xz, vec2(-0.36, 0.93), 3.1, 0.10, f).z;
    h += gs_wave_train_lod(xz, vec2(0.3, -0.95), 5.3, 0.07, f).z;
    return h * WAVE_HEIGHT * (1.0 + 0.6 * rainStrength);
}

// Bright lines of light that dance on the ground under water (caustics), 0..1. They drift with the waves.
float gs_caustics(vec2 xz) {
    float t = gs_time() * 0.8 * WAVE_SPEED;
    vec2 drift = gs_wind_dir() * t * 0.3;
    float a = gs_noise(vec3((xz - drift) * 0.9, t * 0.5));
    float b = gs_noise(vec3((xz + drift.yx) * 1.5 + vec2(3.1, 7.7), -t * 0.6));
    return pow(clamp(1.0 - abs(a - b) * 2.5, 0.0, 1.0), 6.0);
}

// ---- Clouds ----

// How much of the sky the clouds cover right now, 0..1: the option, more in rain.
float gs_cloud_amount() {
    // The weather's mood drifts between a nearly clear sky and a heavy one: a slow swing over the hour the
    // clock runs plus one over half an hour. Both are whole turns per hour, so the hourly wrap of the clock is
    // seamless, and a /time set changes nothing. At load the mood is on the clear side.
    float turn = gs_time() * 0.0017453293;
    float mood = 0.6 * sin(turn + 3.4) + 0.4 * sin(turn * 2.0 + 3.6);
    // Weather: wetness is the rain eased over about 30 s, so clouds gather before rain instead of popping in
    // with it; thunder thickens them as the rain does.
    float wet = wetness;
    return clamp(CLOUD_AMOUNT * (1.0 + mood * mix(0.85, 0.65, step(0.0, mood))) + wet * 0.5 + thunderStrength * wet * 0.2, 0.0, 1.0);
}

// The clouds are real volumes. Their shapes come from two cubes of noise the pack ships as pictures
// (cloud_shape.png and cloud_detail.png: the cube's slices side by side, each with a one-texel border
// copied from its far side).

// A slice's place in its picture: `q` 0..1 across the slice, `n` texels a side, 8 slices a row.
vec2 gs_slice_uv(vec2 q, int slice, float n, vec2 size) {
    vec2 origin = vec2(float(slice % 8), float(slice / 8)) * (n + 2.0);
    return (origin + vec2(1.0) + q * n) / size;
}

// The shape cube at `p` (it spans 0..1 and repeats): two reads, blended between the slices.
vec4 gs_cloud_shape(vec3 p) {
    vec3 q = fract(p);
    float z = q.z * 64.0 - 0.5;
    float z0 = floor(z);
    int s0 = (int(z0) + 64) % 64;
    vec2 size = vec2(528.0, 528.0);
    vec4 a = textureLod(cloud_shape, gs_slice_uv(q.xy, s0, 64.0, size), 0.0);
    vec4 b = textureLod(cloud_shape, gs_slice_uv(q.xy, (s0 + 1) % 64, 64.0, size), 0.0);
    return mix(a, b, z - z0);
}

vec3 gs_cloud_fine(vec3 p) {
    vec3 q = fract(p);
    float z = q.z * 32.0 - 0.5;
    float z0 = floor(z);
    int s0 = (int(z0) + 32) % 32;
    vec2 size = vec2(272.0, 136.0);
    vec4 a = textureLod(cloud_detail, gs_slice_uv(q.xy, s0, 32.0, size), 0.0);
    vec4 b = textureLod(cloud_detail, gs_slice_uv(q.xy, (s0 + 1) % 32, 32.0, size), 0.0);
    return mix(a.rgb, b.rgb, z - z0);
}

float gs_remap(float x, float a, float b) {
    return clamp((x - a) / (b - a), 0.0, 1.0);
}

// How dense the clouds are at a world position (y its height), 0..1.
// `level` 0: the masses only (for light and shadows); 1: with the middle-sized lumps; 2: with frayed edges.
float gs_cloud_density_at(vec3 p, int level) {
#ifndef VOLUMETRIC_CLOUDS
    return 0.0;
#else
    float h = (p.y - GS_CLOUD_LOW) / (GS_CLOUD_HIGH - GS_CLOUD_LOW);
    if (h <= 0.0 || h >= 1.0) {
        return 0.0;
    }
    // Everything drifts slowly east with the wind, about 0.7 blocks a second. Each noise layer moves a whole
    // number of its repeats per hour (fract of the hour), so the hourly wrap of the clock is seamless.
    float hour = gs_time() / 3600.0;

    // Where clouds stand: fields of them with clear sky between, more as the Clouds option and rain rise.
    vec3 w = textureLod(cloud_noise, p.xz * 0.0004 - vec2(fract(hour), 0.0), 0.0).rgb;
    float field = w.r * 0.6 + w.b * 0.4;
    float threshold = mix(0.54, 0.02, gs_cloud_amount());
    float cover = smoothstep(threshold, threshold + 0.3, field);
    if (cover <= 0.0) {
        return 0.0;
    }
    // How tall they grow here: flat bases, and tops that round off lower or higher.
    float kind = clamp(w.b * 0.6 + cover * 0.5 + thunderStrength * wetness * 0.3, 0.0, 1.0);
    float top = mix(0.3, 1.0, kind);
    float gradient = smoothstep(0.0, 0.07, h) * (1.0 - smoothstep(top * 0.4, top, h));

    // The masses: soft noise carved by round billows.
    vec4 s = gs_cloud_shape(p.xzy * 0.0011 - vec3(fract(hour * 3.0), 0.0, 0.0));
    float billows = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
    float base = gs_remap(s.r, billows - 1.0, 1.0) * gradient;
    float d = gs_remap(base, 1.0 - cover, 1.0) * cover;
    if (d <= 0.0) {
        return 0.0;
    }
    if (level >= 1) {
        // Middle-sized billows bite into the mass, most at its edge: the cauliflower look.
        vec4 m = gs_cloud_shape(p.xzy * 0.0037 + vec3(0.31 - fract(hour * 9.0), 0.17, 0.0));
        float lumps = m.g * 0.6 + m.b * 0.4;
        d = gs_remap(d, (1.0 - lumps) * 0.42 * (1.0 - d * 0.5), 1.0);
    }
    if (level >= 2 && d > 0.0) {
        // Fine billows fray the edge: wisps below, puffs above.
        vec3 f = gs_cloud_fine(p.xzy * 0.0075 - vec3(fract(hour * 19.0), 0.0, 0.0));
        float fine = f.r * 0.625 + f.g * 0.25 + f.b * 0.125;
        d = gs_remap(d, mix(fine, 1.0 - fine, clamp(h * 4.0, 0.0, 1.0)) * 0.45, 1.0);
    }
    // Clouds are dense right behind their edge: that is what gives them a firm outline.
    return clamp(d * 3.0, 0.0, 1.0);
#endif
}

// The same, for the ground (cloud shadows) and the puddles' reflections: `detail` asks for the lumps.
float gs_cloud_density(vec3 p, bool detail) {
    return gs_cloud_density_at(p, detail ? 1 : 0);
}

// How much sunlight the clouds let through to a camera-relative point, 0.35..1: the cloud layer where
// the ray to the light crosses it.
float gs_cloud_shadow(vec3 position) {
#ifndef VOLUMETRIC_CLOUDS
    return 1.0;
#else
    vec3 l = gs_light_dir();
    if (l.y < 0.05 || gs_dimension() != 0) {
        return 1.0;
    }
    vec3 world = position + cameraPosition;
    // A quarter of the way up the layer, where every cloud is at its widest.
    float level = GS_CLOUD_LOW + 60.0;
    vec3 hit = world + l * ((level - world.y) / l.y);
    float d = gs_cloud_density(vec3(hit.x, level, hit.z), false);
    return 1.0 - 0.6 * smoothstep(0.0, 0.5, d);
#endif
}

// How strongly a cloud sends light on at an angle to where it came from: mostly straight ahead.
float gs_henyey(float cos_t, float g) {
    return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cos_t, 1.5);
}

// ---- Atmosphere ----

// The colour of the clear sky along a ray: sunlight scattered by the air. Blue overhead, pale at the
// horizon, and at sunrise and sunset the long path through the air leaves the light orange and red.
vec3 gs_atmosphere(vec3 d, vec3 sun) {
    vec3 beta = vec3(0.10, 0.32, 1.0);
    float up = max(d.y, 0.0);
    float air = 1.0 / (up + 0.12);
    float sun_air = 1.0 / (max(sun.y, 0.0) + 0.08);
    vec3 sun_col = exp(-beta * sun_air * 0.30);
    vec3 scattered = 1.0 - exp(-beta * air * 0.22);
    float cos_t = dot(d, sun);
    float phase = 0.75 * (1.0 + cos_t * cos_t);
    vec3 raw = sun_col * scattered * phase * 5.0;
    // Light that bounced more than once keeps the top of the sky blue when the sun is low.
    raw += vec3(0.04, 0.10, 0.26) * smoothstep(-0.2, 0.3, sun.y) * (0.4 + 0.6 * up);
    // Haze around the sun.
    raw += sun_col * pow(max(cos_t, 0.0), 8.0) * 0.5;
    // At sunrise and sunset the sky overhead stays blue instead of turning green.
    float low = 1.0 - smoothstep(0.0, 0.35, abs(sun.y));
    raw += vec3(0.02, 0.04, 0.20) * low * (0.3 + 0.7 * up);
    raw *= vec3(1.0, 1.0 - 0.3 * low, 1.0);
    vec3 col = 1.0 - exp(-raw * 1.4);
    // The Day blue option deepens the blue overhead.
    vec3 grey = vec3(gs_luma(col));
    col = mix(grey, col, 1.0 + (DAY_BLUE - 1.0) * 0.8 * up);
    return max(col, vec3(0.0));
}

// The clouds along a ray, as far as `tmax` blocks: the sky passes no limit, the last pass the distance to
// the terrain, so clouds also stand in front of the ground when the camera flies above or inside them.
// The ray is traced through the cloud layer, which follows the curve of the world, so far clouds sink to
// the horizon. At each step inside a cloud, three looks toward the sun (or moon) measure how much cloud the
// light crossed: tops and sunward sides are bright, cores and bases grey, thin edges before the sun glow.
// `behind` is the colour behind the clouds: far clouds fade into it. rgb is the colour, a how much of what
// is behind they hide.
vec4 gs_clouds_along(vec3 d, vec3 behind, float tmax) {
#ifndef VOLUMETRIC_CLOUDS
    return vec4(0.0);
#else
    vec3 cam = cameraPosition;
    float r0 = GS_PLANET + cam.y;
    float b = r0 * d.y;
    // Where the ray meets the spheres of the layer's base and top: `near` entering, `far` leaving.
    float low_disc = b * b - (r0 * r0 - (GS_PLANET + GS_CLOUD_LOW) * (GS_PLANET + GS_CLOUD_LOW));
    float high_disc = b * b - (r0 * r0 - (GS_PLANET + GS_CLOUD_HIGH) * (GS_PLANET + GS_CLOUD_HIGH));
    float t0 = 0.0;
    float t1 = 0.0;
    if (cam.y < GS_CLOUD_LOW) {
        // Below the clouds: up through the base, out through the top.
        if (d.y < 0.0) {
            return vec4(0.0);
        }
        t0 = -b + sqrt(max(low_disc, 0.0));
        t1 = -b + sqrt(max(high_disc, 0.0));
    } else {
        if (cam.y > GS_CLOUD_HIGH) {
            // Above the clouds: only rays that go down through the top reach them.
            if (high_disc < 0.0 || b > 0.0) {
                return vec4(0.0);
            }
            t0 = -b - sqrt(high_disc);
        }
        // Inside, or after entering from above: on until the ray leaves through the base or the top.
        if (low_disc > 0.0 && -b - sqrt(low_disc) > t0) {
            t1 = -b - sqrt(low_disc);
        } else {
            t1 = -b + sqrt(max(high_disc, 0.0));
        }
    }
    t1 = min(min(t1, t0 + 2600.0), tmax);
    if (t1 <= t0) {
        return vec4(0.0);
    }

    vec3 l = gs_light_dir();
    float dayf = gs_dayf();
    float low = gs_sun_low() * dayf;
    float storm = (1.0 - 0.45 * rainStrength) * (1.0 - 0.3 * thunderStrength);
    vec3 flash = vec3(0.55, 0.65, 0.95) * gs_storm_flash();
    vec3 light = gs_light_color() * 1.3 * storm;
    float cos_t = dot(d, l);
    float phase = clamp(0.6 * gs_henyey(cos_t, 0.6) + 0.4 * gs_henyey(cos_t, -0.25), 0.75, mix(1.7, 3.0, low));
    // The sky's own light on the clouds: blue-white by day, dim violet at sunset, nearly none by night.
    vec3 sky_light = mix(vec3(0.035, 0.045, 0.08), mix(vec3(0.8), vec3(0.22, 0.24, 0.42), low), dayf) * storm;

    int steps = 12 + 10 * CLOUD_QUALITY;
    float dt = (t1 - t0) / float(steps);
    // Each ray starts at its own depth, which turns the steps' bands into fine grain.
    float jitter = gs_hash13(d * 731.0);
    float trans = 1.0;
    vec3 sum = vec3(0.0);
    for (int i = 0; i < steps; i++) {
        float t = t0 + (float(i) + jitter) * dt;
        vec3 rel = vec3(d.x * t, r0 + d.y * t, d.z * t);
        vec3 p = vec3(cam.x + rel.x, length(rel) - GS_PLANET, cam.z + rel.z);
        float dens = gs_cloud_density_at(p, 2);
        if (dens <= 0.004) {
            continue;
        }
        float tau = gs_cloud_density_at(p + l * 10.0, 0) * 20.0
            + gs_cloud_density_at(p + l * 42.0, 0) * 45.0
            + gs_cloud_density_at(p + l * 110.0, 0) * 90.0;
        // Light that reaches here directly, or after bouncing about inside the cloud.
        float energy = max(exp(-tau * GS_CLOUD_SIGMA), exp(-tau * GS_CLOUD_SIGMA * 0.25) * 0.7);
        float h = clamp((p.y - GS_CLOUD_LOW) / (GS_CLOUD_HIGH - GS_CLOUD_LOW), 0.0, 1.0);
        vec3 ambient = mix(vec3(0.34, 0.40, 0.50), vec3(0.58, 0.70, 0.90), h) * sky_light;
        vec3 lit = light * energy * phase + ambient + flash * (0.4 + 0.6 * energy);
        float a = 1.0 - exp(-dens * dt * GS_CLOUD_SIGMA);
        sum += lit * trans * a;
        trans *= 1.0 - a;
        if (trans < 0.02) {
            break;
        }
    }
    float alpha = 1.0 - trans;
    if (alpha < 0.001) {
        return vec4(0.0);
    }
    vec3 col = sum / alpha;
    col = col / (1.0 + 0.35 * col) * 1.2;
    // Far clouds take the colour of the air in front of them.
    col = mix(col, behind, (1.0 - exp(-t0 / 3500.0)) * 0.85);
    return vec4(col, alpha);
#endif
}

// The air of the biome at the camera: rgb a tint for the haze, a how thick it is (1 normal). Jungles are
// humid and green-white, deserts dusty and warm, cold biomes clear and blue.
vec4 gs_biome_air() {
    float temp = temperature;
    float wet = rainfall;
    float humid = smoothstep(0.7, 0.95, temp) * smoothstep(0.6, 0.9, wet);
    float dusty = smoothstep(1.2, 1.9, temp) * (1.0 - smoothstep(0.0, 0.3, wet));
    float cold = 1.0 - smoothstep(0.0, 0.3, temp);
    vec3 tint = vec3(1.0);
    tint = mix(tint, vec3(0.82, 1.0, 0.88), humid);
    tint = mix(tint, vec3(1.0, 0.84, 0.6), dusty);
    tint = mix(tint, vec3(0.8, 0.9, 1.0), cold);
    return vec4(tint, 1.0 + humid * 1.2 + dusty * 0.6 - cold * 0.3);
}

// ---- Rare events in the sky ----
// The chance of an event comes from the world's day number (the WGSL pack, which had none, used the gap
// between game time and the day clock and the third of the session hour): x the day, y unused.
vec2 gs_event_seed() {
    return vec2(float(worldDay), 0.0);
}

// A solar eclipse, on about one noon in fourteen: x how far the moon's disc stands beside the sun's
// (radians, signed; both discs are 0.04 wide), y how dark it is, 0..1. The moon takes a minute to cross,
// a fifth of it total.
vec2 gs_solar_eclipse() {
    float phase = (gs_day_time() - 0.25) / 0.025;
    vec2 seed = gs_event_seed();
    if (gs_dimension() != 0 || abs(phase) >= 1.0 || gs_hash13(vec3(seed, 7.0)) > 0.07) {
        return vec2(1.0, 0.0);
    }
    float x = sign(phase) * max(abs(phase) - 0.2, 0.0) * 0.125;
    float cover = 1.0 - smoothstep(0.0, 0.085, abs(x));
    return vec2(x, cover * cover);
}

// A lunar eclipse, on about one midnight in eleven: how deep the moon is in the shadow, 0..1.
float gs_lunar_eclipse() {
    float phase = (gs_day_time() - 0.75) / 0.04;
    vec2 seed = gs_event_seed();
    if (gs_dimension() != 0 || abs(phase) >= 1.0 || gs_hash13(vec3(seed, 11.0)) > 0.09) {
        return 0.0;
    }
    return smoothstep(1.0, 0.5, abs(phase));
}

// The night sky turning slowly about the zenith, its nebulae billowing: `turns` turns and `swells`
// swells an hour (whole numbers: the clock wraps hourly), `amount` how far the swell pushes.
vec3 gs_sky_drift(vec3 d, float turns, float swells, float amount) {
    float a = gs_time() * turns * 0.0017453293;
    vec3 r = vec3(d.x * cos(a) - d.z * sin(a), d.y, d.x * sin(a) + d.z * cos(a));
    float ph = gs_time() * swells * 0.0017453293;
    return normalize(r + amount * (sin(r.yzx * 6.0 + vec3(ph)) + 0.5 * sin(r.zxy * 11.0 - vec3(2.0 * ph))));
}

// ---- The End ----
// Toward the End's black hole: it hangs over the main island as seen from the arrival platform.
const vec3 GS_END_EYE = vec3(-0.7454, 0.5963, 0.2981);
const vec3 GS_END_LIGHT = vec3(0.62, 0.4, 1.0);

// The black hole along a ray: a black disc, a thin bright ring of bent light around it and a glowing
// disc of dust seen nearly edge-on, turning once a minute. rgb is the light, a how much of the sky
// behind is hidden.
vec4 gs_end_eye(vec3 d) {
    float z = dot(d, GS_END_EYE);
    if (z < 0.55) {
        return vec4(0.0);
    }
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), GS_END_EYE));
    vec3 up = cross(GS_END_EYE, right);
    vec2 p = vec2(dot(d, right), dot(d, up)) / z;
    float r0 = 0.11;
    float r = length(p) / r0;
    // The dust disc: tilted 15 degrees and squashed, its lower half in front of the hole.
    vec2 q = vec2(p.x * 0.966 + p.y * 0.259, (p.y * 0.966 - p.x * 0.259) * 5.5) / r0;
    float dr = length(q);
    float spin = gs_time() * 0.104719755;
    vec2 cs = vec2(cos(spin + dr * 0.8), sin(spin + dr * 0.8));
    vec2 turned = vec2(q.x * cs.x - q.y * cs.y, q.x * cs.y + q.y * cs.x);
    float streaks = 0.45 + 0.55 * gs_noise(vec3(turned * 1.6, dr * 3.0));
    float disc = smoothstep(1.25, 1.7, dr) * (1.0 - smoothstep(2.4, 4.6, dr)) * streaks;
    disc *= 0.65 + 0.35 * q.x / max(dr, 0.001);
    if (r < 1.0 && q.y > 0.0) {
        disc = 0.0;
    }
    float ring = smoothstep(0.98, 1.03, r) * exp(-(r - 1.0) * 9.0);
    float glow = exp(-r * 0.55) * smoothstep(0.98, 1.2, r);
    vec3 disc_col = mix(vec3(1.0, 0.9, 1.0), vec3(0.7, 0.2, 1.0), smoothstep(1.5, 3.8, dr));
    vec3 rgb = disc_col * disc * 1.5 + vec3(1.0, 0.75, 1.0) * ring * 1.4 + vec3(0.4, 0.12, 0.7) * glow * 0.6;
    return vec4(rgb, max(1.0 - smoothstep(0.97, 1.0, r), min(disc, 1.0)));
}

// The End's sky: the night sky's nebulae in violet and teal, turning once an hour, mirrored into the void
// below, stars, and the black hole.
vec3 gs_end_sky(vec3 d) {
    vec3 e = gs_sky_drift(d, 6.0, 60.0, 0.06);
    float u = atan(e.z, e.x) / 6.2831853 + 0.5;
    float v = (1.5707963 - asin(clamp(abs(e.y), 0.0, 1.0))) / 1.8849556;
    vec3 t = textureLod(night_sky, vec2(u, clamp(v, 0.001, 0.999)), 0.0).rgb;
    float lum = gs_luma(t);
    float teal = smoothstep(0.35, 0.7, gs_noise(d * 2.5 + vec3(4.0, 1.0, 7.0)));
    vec3 col = mix(vec3(0.75, 0.2, 1.0), vec3(0.15, 0.9, 0.7), teal) * lum * 2.2;
    col += vec3(0.03, 0.012, 0.06) + vec3(0.07, 0.02, 0.12) * pow(1.0 - abs(d.y), 3.0);
    vec3 cell = floor(d * 140.0);
    float h = gs_hash13(cell);
    if (h > 0.93) {
        vec3 star = normalize(cell + gs_hash33(cell) * 0.6 + vec3(0.2));
        col += vec3(0.85, 0.8, 1.0) * smoothstep(0.3, 0.0, length(d - star) * 140.0) * (h - 0.93) * 20.0;
    }
    vec4 eye = gs_end_eye(d);
    return col * (1.0 - eye.a) + eye.rgb;
}

#endif
