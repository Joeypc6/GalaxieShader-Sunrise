#version 330 compatibility

// The pack draws its own sky, sun, moon, stars and clouds in deferred: vanilla's draw nothing.
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 out_color;

void main() {
    discard;
}
