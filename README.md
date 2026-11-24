# Hipped´s Galaxie Shader (shaders/ format)

A shader pack for [Sunrise](https://github.com/sunrise-org/sunrise) in the `shaders/` (Iris/OptiFine) format: a
night sky with a nebula, stars, planets, auroras and rare sky events, volumetric clouds, light shafts, a mirrored
water surface, rain puddles, shadows and coloured block light.

By Joeypc6, based on Hipped's Galaxie Shader by HippedPainter68 (https://github.com/HippedPainter68/hippeds-galaxie-shader).

## Licence

Licensed under the PolyForm Shield License 1.0.0 with the Sunrise Additional Terms 1.0 (LICENSE.txt), as in Sunrise's
LICENSE blob b8ca21bee4b3c2e99e6b3b3bcb94a7389ca50d15, or any later version published under its section 5.

## Install

1. Download `GalaxieShader.zip` from the releases page and drop it, unzipped or not, into `shaderpacks/` beside
   `options.txt` (Open Pack Folder on the Shader Packs page opens it).
2. Pick it on Options > Sunrise Settings > Extras > Sunrise Graphics > Shaders > Shader Packs.... Shader Options...
   on the same page changes its settings.

For development, `SUNRISE_SHADER_PACK=GalaxieShader` (the pack's folder or file name in `shaderpacks/`) runs the
pack whatever the page says.

Needs a loader with `customTexture` (Sunrise, Iris); OptiFine does not read the pack's textures.

## About this version

Ported to the shaders/ format by Joeypc6, from the tuned Sunrise WGSL version of the pack (shader API 0.2). The
look, the effects and the options are the WGSL pack's; the code is Galaxie's own, rewritten in GLSL for the
format's programs (gbuffers, shadow, deferred, composite, final). Changed for the format:

- Coloured block light: a light source's own faces take its colour; light that reaches other blocks takes one
  warm colour (option "Block light colour", lava's by default), since the format gives no per-point light colour.
- Water's mirror is traced on screen (as the puddles' is), with the pack's sky where the trace finds nothing.
- Rare sky events (eclipses, comets, second rainbows) are rolled per world day.
- Snow or rain streaks are told apart by the biome at the camera.
- LabPBR relief as geometry (Sunrise's displacement) and Sunrise's dynamic-light colour are not in the format.

## Known engine gaps

These are in Sunrise's `shaders/` loader, not in the pack; the pack looks right once they are fixed.

- [sunrise-org/sunrise#5015](https://github.com/sunrise-org/sunrise/issues/5015): solid and cutout terrain gets
  `mc_Entity` -1 and `at_midBlock` 0 for every block, so effects keyed to block ids (waving plants, emissive
  blocks, per-block materials) fall back to their defaults.
- [sunrise-org/sunrise#5016](https://github.com/sunrise-org/sunrise/issues/5016): distant terrain's water is drawn
  over its land, so far land can vanish behind opaque water.
