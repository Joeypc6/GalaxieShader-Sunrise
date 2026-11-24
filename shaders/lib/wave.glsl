// Galaxy Sky: where corners are drawn (the WGSL pack's vertex.wgsl). Water rolls with the waves; leaves,
// grass, flowers and water plants move with the wind or the water. Ids are block.properties'.
#if !defined GS_WAVE
#define GS_WAVE 1

// `p` camera-relative, `top` 1 at a sprite's top corners and 0 at its bottom ones, `sky` the sky light 0..1.
vec3 gs_move_corner(vec3 p, int material, float top, float sky) {
    vec3 world = p + cameraPosition;

    // Water: only corners in the top half of a block move, so a block's side and top meet with no gap.
    if (material == 1) {
        if (fract(world.y) > 0.5) {
            p.y += gs_wave_lod(world.xz, max(gs_water_footprint(p), 1.0));
        }
        return p;
    }
    if (material != 10 && material != 11 && material != 12) {
        return p;
    }

    // Each plant column gets its own rhythm, so a meadow does not move as one. (Plants sit inside their
    // block, so every corner of one plant gets the same value.)
    float own = gs_hash13(vec3(floor(world.xz), 7.0));
    // Sheltered plants (no sky above) barely move.
    float open = 0.15 + 0.85 * smoothstep(0.2, 0.8, sky);
    float wind = gs_wind() * open;
    vec2 dir = gs_wind_dir();

    if (material == 10) {
        // Leaves: the whole canopy leans with the gusts and flutters. Leaf blocks share corners, so the
        // motion depends on the position only: a shared corner moves the same for every block.
        float lean = gs_gust(world.xz, 0.8) * 0.035;
        float flutter = sin(gs_time() * 3.1 + dot(world, vec3(1.3, 2.1, 1.7))) * 0.02;
        p += vec3(dir.x * lean + flutter, flutter * 0.6, dir.y * lean - flutter) * wind;
    } else if (material == 11) {
        // Grass, flowers, crops: the root stays, the top bends.
        float bend = (gs_gust(world.xz, 1.0 + own * 0.6) * 0.5 + 0.25) * 0.11 * top * wind;
        float side = sin(gs_time() * (1.7 + own) + own * 30.0) * 0.03 * top * wind;
        p += vec3(dir.x * bend - dir.y * side, -abs(bend) * 0.25, dir.y * bend + dir.x * side);
    } else {
        // Water plants: slow, with the swell, whatever the wind above.
        float t = gs_time() * WAVE_SPEED;
        float sway = sin(dot(world.xz, dir) * 0.6 - t * 1.1 + world.y * 0.8 + own * 6.0) * 0.12 * (0.3 + 0.7 * top);
        p += vec3(dir.x * sway, 0.0, dir.y * sway);
    }
    return p;
}

#endif
