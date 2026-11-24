// Galaxie: the kind of a terrain quad when its block.properties id is missing.
#if !defined GS_GUESS
#define GS_GUESS 1

// Without the block's id (Sunrise currently hands terrain mc_Entity -1 for every quad), the kinds the
// pack treats apart are told by their look: the sprite's average (`avg`, its smallest mip), the vertex
// tint and the face normal `n`. Water: a tinted, see-through sprite with a blue tint. Plants: a cutout
// sprite on a diagonal face (cross models). Leaves: a tinted cutout sprite on a block face. Lava: an
// untinted orange sprite in full block light. An id from block.properties always wins.
int gs_guess_id(int id, vec4 avg, vec3 t, vec3 n, float block_light) {
    if (id > 0) {
        return id;
    }
    bool tinted = max(t.r, max(t.g, t.b)) - min(t.r, min(t.g, t.b)) > 0.08;
    bool cutout = avg.a < 0.97;
    bool diagonal = abs(n.x) > 0.3 && abs(n.z) > 0.3;
    if (tinted && cutout && t.b > t.r + 0.1 && t.b >= t.g) {
        return 1;
    }
    if (cutout && diagonal) {
        return 11;
    }
    if (tinted && cutout && t.g > t.b) {
        return 10;
    }
    if (!tinted && avg.r > 0.7 && avg.g > 0.2 && avg.g < 0.65 && avg.b < 0.2 && block_light > 0.9) {
        return 2;
    }
    return id;
}

#endif
