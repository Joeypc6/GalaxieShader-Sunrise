// Galaxy Sky: how surfaces look (the WGSL pack's material.wgsl).
// Terrain: sun shadows and cloud shadows, coloured block light, sunlight through leaves, smooth and
// metallic materials with highlights (LabPBR maps when a resource pack ships them), wet ground and puddles
// after rain (marked here, drawn in composite4), glowing ores, lava.
// Water: waves and ripples, refraction, colour by depth, foam, caustics below, the mirror and sun glints.
#if !defined GS_MATERIAL
#define GS_MATERIAL 1

// block.properties ids (mc_Entity.x).
const int GS_WATER = 1;
const int GS_LAVA = 2;
const int GS_LEAVES = 10;
const int GS_PLANTS = 11;
const int GS_WATER_PLANTS = 12;
const int GS_SNOW = 13;
const int GS_ICE = 14;
const int GS_METAL = 15;
const int GS_GLOSSY = 16;
const int GS_ORE = 18;
const int GS_PORTAL = 23;
const int GS_REDSTONE_ORE = 37;

// What the material stage of the WGSL pack was handed (MaterialInput), worked out by the programs.
struct GsSurfaceIn {
    vec4 albedo;        // the texture
    vec3 tint;          // vertex colour (biome tint, AO) times vanilla's face shade
    vec3 lightmap;      // vanilla's light colour at this point
    vec2 light;         // block and sky light, 0..1
    vec3 position;      // camera-relative, world-aligned
    vec3 normal;        // world-aligned
    vec4 tangent;       // world-aligned xyz, w the bitangent's sign
    vec2 uv;            // atlas
    vec4 normal_map;    // the normals atlas here (LabPBR)
    vec4 specular_map;  // the specular atlas here (LabPBR)
    vec2 screen;        // 0..1 from the bottom left
    int material;       // block.properties id
    float emission;     // the block's own light, 0..1
    bool translucent;
    bool top;           // an upward face (water)
};

// The surface data the later passes read (colortex2): the normal, smoothness, and `data`: > 0 how much
// rain falls here (the wet ground in composite4), < 0 lava's glow for the bloom.
struct GsSurfaceOut {
    vec4 color;         // in the pack's gamma values
    vec3 normal;
    float smoothness;
    float data;
};

// The colour a light source gives (the WGSL manifest's [[lights]], in vanilla's gamma values), by its
// block.properties id; `fallback` for every other source.
vec3 gs_source_color(int id, vec3 fallback) {
    if (id == 30) return vec3(0.3, 0.7, 1.0);       // soul fire
    if (id == 31 || id == GS_REDSTONE_ORE) return vec3(1.0, 0.22, 0.15);
    if (id == 32 || id == GS_PORTAL) return vec3(0.6, 0.3, 1.0);
    if (id == 33) return vec3(0.55, 0.9, 1.0);      // sea lantern, conduit, beacon
    if (id == 34) return vec3(0.2, 0.75, 0.85);     // sculk, glow lichen
    if (id == 35) return vec3(0.5, 1.0, 0.6);       // verdant froglight
    if (id == 36) return vec3(1.0, 0.6, 0.9);       // pearlescent froglight
    if (id == 38) return vec3(0.9, 0.92, 1.0);      // end rod
    if (id == GS_LAVA || id == 39) return vec3(1.0, 0.42, 0.12);
    if (id == 40) return vec3(1.0, 0.72, 0.38);     // torches, lanterns, glowstone
    return fallback;
}

// Block light away from a source's own faces: the format has no colour of the light that reaches a
// point, so it takes one warm colour (the option; lava's by default, as the WGSL pack past its grid).
vec3 gs_block_light_hue() {
#if BLOCK_LIGHT_HUE == 1
    return vec3(1.0, 0.72, 0.38);
#elif BLOCK_LIGHT_HUE == 2
    return vec3(1.0, 0.86, 0.66);
#else
    return vec3(1.0, 0.42, 0.12);
#endif
}

#include "/lib/shadow.glsl"

GsSurfaceOut gs_terrain(GsSurfaceIn i) {
    vec4 base = vec4(i.albedo.rgb * i.tint, i.albedo.a);
    vec3 v = normalize(-i.position);
    vec3 world = i.position + cameraPosition;
    bool overworld = gs_dimension() == 0;
    float sky_w = smoothstep(0.3, 0.9, i.light.y);
    bool leafy = i.material == GS_LEAVES || i.material == GS_PLANTS || i.material == GS_WATER_PLANTS;
    vec3 l = gs_light_dir();

    // ---- What the surface is made of ----
    vec3 n = i.normal;
    float smoothness = 0.05;
    float f0 = 0.04;
    float metal = 0.0;
    float ao = 1.0;
    float emit = i.emission;
    if (i.material == GS_SNOW) smoothness = 0.5;
    if (i.material == GS_ICE) smoothness = 0.85;
    if (i.material == GS_METAL) { smoothness = 0.8; metal = 1.0; }
    if (i.material == GS_GLOSSY) smoothness = 0.65;
    // LabPBR maps (the format gives a flat normal and no specular without a resource pack's maps).
    {
        vec4 nm = i.normal_map;
        vec4 sm = i.specular_map;
        vec2 txy = nm.xy * 2.0 - 1.0;
        float tz = sqrt(max(1.0 - dot(txy, txy), 0.0));
        vec3 bitangent = cross(i.normal, i.tangent.xyz) * i.tangent.w;
        n = normalize(i.tangent.xyz * txy.x + bitangent * txy.y + i.normal * tz);
        ao = nm.b;
        if (sm.r + sm.g + sm.b + sm.a > 0.0) {
            smoothness = max(smoothness, sm.r);
            if (sm.g > 0.9) {
                metal = 1.0;
            } else {
                f0 = max(f0, sm.g);
            }
            if (sm.a < 0.999) {
                emit = max(emit, sm.a);
            }
        }
    }

    // ---- Light ----
    vec3 light = i.lightmap * ao;

    // Block light takes the colour of its sources: lava orange, soul fire blue, redstone red. A source's own
    // faces take its own colour; light that reached a block from elsewhere takes the option's warm colour.
    // (Its weight is 0 without block light, so the work is skipped there: same picture, less work.)
    if (COLORED_LIGHT > 0.0 && i.light.x > 0.0) {
        vec3 cl = i.emission > 0.0 ? gs_source_color(i.material, vec3(1.0, 0.86, 0.66)) : gs_block_light_hue();
        float w = smoothstep(0.0, 0.5, i.light.x) * (1.0 - 0.75 * sky_w * gs_dayf()) * min(COLORED_LIGHT, 1.0);
        vec3 hue = cl / max(gs_max3(cl), 0.001);
        light *= mix(vec3(1.0), hue * (1.0 + 0.25 * COLORED_LIGHT), w);
    }
    // Sun or moon: shadows, cloud shadows, colour through stained glass, caustics under water.
    // A shadow only takes away the sun's or moon's light. Where a torch lights a spot more than the sky
    // does, its light fills the shadow: a torch casts no shadow of its own.
    vec3 sun_col = gs_light_color();
    float direct = 0.0;
    if (overworld) {
        float s = 1.0;
        vec3 tint = vec3(1.0);
        float ndl = dot(n, l);
        float facing = smoothstep(0.0, 0.2, ndl);
        // The shadow s only ever reaches the picture through direct (s * facing) and, for leaves, through;
        // both are then weighted by sky_w (except the snow glitter, which uses direct alone). Where facing is 0
        // on a non-leaf, or sky_w is 0 off snow, s cannot change a pixel: skip the shadow maps and the cloud
        // shadow there (same picture, less work).
        bool needs_shadow = (facing > 0.0 || leafy) && (sky_w > 0.0 || i.material == GS_SNOW);
        if (needs_shadow) {
#ifdef SHADOWS
            vec3 bias = i.normal * (GS_SHADOW_TEXEL * 2.0 + 0.03);
            vec3 sp = gs_shadow_position(i.position + bias);
            s = textureLod(shadowtex1, sp, 0.0);
            // Past the map's edge everything counts as lit.
            float fade = smoothstep(GS_SHADOW_DISTANCE * 0.85, GS_SHADOW_DISTANCE, length(i.position.xz));
            s = mix(s, 1.0, fade);
            // Lit in the solid map but not through translucent terrain: under water or stained glass.
            // (The translucent map is read only where s > 0.5, the only place its answer is used.)
            if (s > 0.5) {
                float st = textureLod(shadowtex0, sp, 0.0);
                if (st < 0.5) {
                    ivec2 size = textureSize(shadowcolor0, 0);
                    ivec2 texel = clamp(ivec2(sp.xy * vec2(size)), ivec2(0), size - ivec2(1));
                    vec4 sc = texelFetch(shadowcolor0, texel, 0);
                    if (sc.a >= 1.0) {
                        tint = vec3(0.45, 0.85, 1.0) * (0.35 + 2.0 * gs_caustics(world.xz));
                    } else {
                        tint = sc.rgb;
                    }
                }
            }
#endif
            // A fully shadowed point stays 0 whatever the clouds do.
            if (s > 0.0) {
                s *= gs_cloud_shadow(i.position);
            }
        }
        direct = s * facing;

        // Thin things let the sun through: a leaf seen against the light glows yellow-green.
        float through = 0.0;
        if (leafy) {
            through = s * (0.35 + 0.65 * pow(max(dot(-v, l), 0.0), 4.0)) * (1.0 - facing);
        }

        vec3 sun_tint = sun_col / max(gs_max3(sun_col), 0.001) * tint;
        // By night the moon tints only a little, or snow turns deep blue.
        float tint_amount = mix(0.15, 0.45, gs_dayf());
        vec3 factor = mix(vec3(0.58), mix(vec3(1.0), sun_tint, tint_amount) * 1.02, direct);
        factor += sun_tint * vec3(1.0, 1.05, 0.55) * through * 0.55;
        // Near a light source its light fills every shadow, by day too: within about three blocks of a
        // torch (block light 11 of 15 and more) no shadow is left, and by seven blocks they are back.
        float block = i.light.x;
        float sky_share = 1.0 - smoothstep(0.45, 0.72, block);
        light *= mix(vec3(1.0), factor, sky_w * sky_share);
    }

    // The End: a dim violet glow from everywhere, and the black hole's disc lights what faces it.
    if (gs_dimension() == 1) {
        // Scaled back when too bright, or the End's own purple flashes burn the ground out.
        light += GS_END_LIGHT * (0.55 + 0.45 * max(dot(n, GS_END_EYE), 0.0));
        light *= min(1.0, 1.1 / gs_max3(light));
    }

    // The Nether: the air glows in the colour of the biome's fog (red wastes, blue soul valleys, teal
    // warped forests), and the lava sea lights what is low from below.
    if (gs_dimension() == -1) {
        vec3 air = gs_fog_color() / max(gs_max3(gs_fog_color()), 0.05);
        float lava = (1.0 - smoothstep(31.0, 75.0, world.y)) * (0.45 - 0.35 * n.y);
        light = light * 1.2 + mix(vec3(1.0), air, 0.5) * 0.4 + vec3(1.0, 0.4, 0.1) * lava;
    }

    // ---- Highlights and reflections: smooth things shine, metals reflect in their own colour ----
    vec3 shine = vec3(0.0);
    if (smoothness > 0.06) {
        vec3 half_vec = normalize(l + v);
        float nh = max(dot(n, half_vec), 0.0);
        float power = exp2(1.0 + smoothness * 10.0);
        float fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(n, v), 0.0), 5.0);
        vec3 shine_col = mix(vec3(1.0), base.rgb, metal);
        shine = sun_col * shine_col * pow(nh, power) * (power + 8.0) / 40.0 * smoothness * direct * sky_w;
        shine += gs_sky_color() * shine_col * mix(fresnel, 0.6, metal) * smoothness * smoothness * sky_w;
        // Snow glitters: a few crystals catch the sun, by day only.
        if (i.material == GS_SNOW) {
            float crystal = step(0.996, gs_hash13(floor(world * 24.0) + floor(v * 6.0)));
            shine += sun_col * crystal * pow(nh, 12.0) * direct * gs_dayf();
        }
    }

    vec3 col = base.rgb * light * (1.0 - 0.4 * metal * smoothness) + shine;
    col += base.rgb * emit * 0.5;
    // Lava keeps its texture's own light and dark, with a gentle drifting heat on top.
    if (i.material == GS_LAVA) {
        float heat = gs_noise(vec3(world.xz * 0.6, world.y * 0.6 + gs_time() * 0.3));
        col = base.rgb * vec3(1.05, 0.95, 0.85) * (0.92 + 0.3 * heat);
        // Its glow is marked for the bloom (surface data below 0), not baked into the colour: a far pool covers
        // few pixels, so its glow must grow with the square of the distance to stay visible out to ~1000
        // blocks, and that much brightness in the colour itself tone-maps to white.
    }
    // Ores: their coloured specks glow where it is dark.
    if (i.material == GS_ORE || i.material == GS_REDSTONE_ORE) {
        vec3 a = i.albedo.rgb;
        float colourful = smoothstep(0.25, 0.6, gs_max3(a) - min(a.r, min(a.g, a.b)));
        col += a * colourful * (1.0 - min(gs_luma(i.lightmap), 1.0)) * 0.9;
    }
    // Skylight approximates rain shelter.
    bool receives_rain = overworld && biome_precipitation == 1 && !leafy && i.material != GS_SNOW
        && i.material != GS_ICE && i.material != GS_LAVA && !i.translucent && i.emission == 0.0;
    float rain_exposure = receives_rain ? smoothstep(0.85, 0.99, i.light.y) : 0.0;
    // composite4 keeps rainwater longer than wetness and shades only visible solid terrain.
    // Lava: data < 0 is its glow strength for the glow passes (rain only reads data > 0).
    float data = rain_exposure;
    if (i.material == GS_LAVA) {
        float d = max(length(i.position) - 16.0, 0.0) / 60.0;
        data = -min(1.0 + d * d, 200.0);
    }
    GsSurfaceOut o;
    o.color = vec4(col, base.a);
    o.normal = n;
    o.smoothness = smoothness;
    o.data = data;
    return o;
}

#endif
