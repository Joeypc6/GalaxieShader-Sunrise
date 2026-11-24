#version 330 compatibility
// Galaxie: the lens, last (the WGSL pack's post/lens.wgsl): smooth edges, then the optional camera effects
// (depth of field, motion blur, chromatic aberration) and the vignette. Each optional effect costs nothing
// while its option is 0. The hand is left as composite4 left it.
#include "/lib/settings.glsl"
#include "/lib/frame.glsl"
#include "/lib/buffers.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 out_color;

vec3 gs_tap(vec2 uv) {
    return textureLod(colortex0, uv, 0.0).rgb;
}

// How far a point is from the camera, in blocks; the sky is far away.
float gs_distance(vec2 uv) {
    float depth = textureLod(depthtex0, uv, 0.0).r;
    if (depth >= 1.0) {
        return 2000.0;
    }
    return length(gs_player_pos(uv, depth));
}

void main() {
    vec2 uv = texcoord;
    vec2 px = 1.0 / gs_resolution();
    vec3 c = texelFetch(colortex0, ivec2(gl_FragCoord.xy), 0).rgb;
    if (texelFetch(colortex2, ivec2(gl_FragCoord.xy), 0).z < -0.5) {
        out_color = vec4(c, 1.0);
        return;
    }

    // Smooth edges: where the brightness jumps, blend along the edge.
#ifdef FXAA
    {
        vec3 n = gs_tap(uv + vec2(0.0, px.y));
        vec3 s = gs_tap(uv + vec2(0.0, -px.y));
        vec3 w = gs_tap(uv + vec2(-px.x, 0.0));
        vec3 e = gs_tap(uv + vec2(px.x, 0.0));
        float lc = gs_luma(c);
        float ln = gs_luma(n);
        float ls = gs_luma(s);
        float lw = gs_luma(w);
        float le = gs_luma(e);
        float lo = min(lc, min(min(ln, ls), min(lw, le)));
        float hi = max(lc, max(max(ln, ls), max(lw, le)));
        float contrast = hi - lo;
        if (contrast > max(0.05, hi * 0.125)) {
            // Blend across the edge: sideways for a vertical edge, up and down for a horizontal one.
            bool horizontal = abs(ln + ls - 2.0 * lc) >= abs(lw + le - 2.0 * lc);
            float amount = clamp(contrast / max(hi, 0.001), 0.0, 1.0) * 0.5;
            vec3 blurred = horizontal ? (n + s) * 0.5 : (w + e) * 0.5;
            c = mix(c, blurred, amount);
        }
    }
#endif

    // Depth of field: focus on the middle of the screen, blur by how far off the focus a point is.
    if (DEPTH_OF_FIELD > 0.0) {
        float focus = gs_distance(vec2(0.5));
        float here = gs_distance(uv);
        float coc = clamp(abs(here - focus) / max(focus, 1.0), 0.0, 1.0) * DEPTH_OF_FIELD;
        if (coc > 0.02) {
            float radius = coc * 8.0 * gs_resolution().y / 720.0;
            vec3 sum = c;
            for (int i = 0; i < 8; i++) {
                float a = float(i) * 0.7853982;
                sum += gs_tap(uv + vec2(cos(a), sin(a)) * radius * px);
            }
            c = sum / 9.0;
        }
    }

    // Motion blur: smear along the way the point moved on screen since last frame (camera motion).
    if (MOTION_BLUR > 0.0) {
        float depth = textureLod(depthtex0, uv, 0.0).r;
        vec3 p = depth >= 1.0 ? gs_view_dir(uv) * 2000.0 : gs_player_pos(uv, depth);
        vec4 before = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(p + cameraPosition - previousCameraPosition, 1.0));
        if (before.w > 0.0) {
            vec2 prev_uv = before.xy / before.w * 0.5 + 0.5;
            vec2 vel = (uv - prev_uv) * MOTION_BLUR * 0.5;
            float len = length(vel);
            vel *= min(len, 0.03) / max(len, 0.00001);
            vec3 sum = c;
            for (int i = 1; i < 6; i++) {
                sum += gs_tap(uv - vel * (float(i) / 5.0));
            }
            c = sum / 6.0;
        }
    }

    // Chromatic aberration: red and blue drift apart toward the corners.
    if (CHROMATIC_ABERRATION > 0.0) {
        vec2 off = (uv - vec2(0.5)) * CHROMATIC_ABERRATION * 0.012;
        c = vec3(mix(c.r, gs_tap(uv + off).r, 0.8), c.g, mix(c.b, gs_tap(uv - off).b, 0.8));
    }

#ifdef VIGNETTE
    {
        float aspect = gs_resolution().x / gs_resolution().y;
        float d = length((uv - 0.5) * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.55, 1.1, d) * 0.3;
    }
#endif
    out_color = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
