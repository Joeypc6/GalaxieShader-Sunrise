// Galaxie: the buffers. Every composite-style program includes this, so the formats are read whichever
// program the loader scans.
//   colortex0  the picture, in the pack's gamma values; float, as the WGSL pack's float frame
//   colortex2  the surface: xy its normal (octahedral), z smoothness (-1 marks the hand), w data
//              (> 0 rain reaches it, < 0 lava's glow)
//   colortex3  bloom, half size
//   colortex4  the opaque world with its sky, for water's refraction and mirror (deferred writes it)
//   colortex5  the rain clock, quarter size: r when the rainwater will have dried, g lava's glow gathered,
//              b last frame's blurred glow, reprojected
//   colortex6  the rain clock kept for the next frame: r the same time, g the glow blurred and eased
//   colortex7  the light shafts, half size, blended from frame to frame
/*
const int colortex0Format = RGBA16F;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA32F;
const int colortex6Format = RGBA32F;
const int colortex7Format = RGBA16F;
*/
const bool colortex6Clear = false;
const bool colortex7Clear = false;
