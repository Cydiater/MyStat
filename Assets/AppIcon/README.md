# MyStat app icon

The signal-shaped M uses the app's CPU orange and memory teal on graphite. The wide stroke and simple silhouette keep it legible at small sizes.

- `MyStat-iOS.png`: original full-square artwork from the built-in image-generation tool.
- `MyStat-macOS.png`: transparent rounded-square variant from the same tool.
- `AppIcon.icns`: packaged Mac icon, copied into the app by `build.sh`.
- The iPhone icon lives in `MyStat-iOS/MyStat-iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

Regenerate the platform assets from the approved artwork on a Mac:

```sh
swift scripts/generate-app-icons.swift
./build.sh
```

The packaging script resizes and encodes the images. The iOS asset is 1024 × 1024, opaque sRGB. The Mac icon contains standard 16–1024 pixel representations and preserves the generated transparency. No image-generation service or API key is required to build the app.

## Generation prompts

Both images were made with the built-in image-generation tool, not the CLI fallback. The macOS export includes a second background-extraction pass to produce a genuine alpha channel.

### macOS transparency correction

Use case: background-extraction. The supplied image has an INCORRECT BAKED GRAY CHECKERBOARD outside the rounded-square app icon. Remove only that gray checkerboard background completely and make those exterior pixels genuinely transparent using a PNG ALPHA CHANNEL. This is an actual cutout / transparent-background editing request, not a picture illustrating transparency. Return an RGBA PNG with alpha=0 outside the dark rounded square; do not draw any gray grid, white backdrop, black backdrop or replacement solid color. Preserve the entire dark rounded square and the orange-and-teal M artwork exactly. Preserve the source canvas dimensions, existing placement, shape, colors and edges. Do not add shadow. The existing icon is the sole foreground object; extract it cleanly, antialiasing its curved perimeter. All four image corners and the margin around the tile MUST be actual transparent pixels.

### iOS master

Use case: logo-brand. Asset type: production app icon master for MyStat, a native Mac system monitor that streams CPU, memory, network and power readings to an iPhone. Create one finished 1024 x 1024 square icon, not a presentation or mockup. Design a single distinctive, bold, sculptural signal-wave monogram that suggests an M: two rounded peaks with a deep central valley, built from a continuous thick ribbon with precise smooth geometry. The left peak uses warm CPU orange and the right peak uses luminous memory teal, a tasteful transition at the central join. Subtle premium satin depth and restrained edge lighting, almost flat, readable at 32 pixels. Center this symbol at roughly 62 percent of the square width, with generous quiet margins. Background is opaque edge-to-edge very dark graphite, with only a subtle soft tonal gradient. This is the unmasked iOS icon artwork: full square corners, no outer frame or inset rounded-square tile, no exterior margins, no transparency. No text, no numerals, no tiny details, no grids, no extra charts, no devices, no Apple logo, no watermark. Strong simple silhouette, polished native utility-app character. Orange and teal match the app's existing CPU and memory graphs.

### macOS variant

Use case: precise-object-edit. Edit target: the supplied MyStat iOS icon. Create the macOS app-icon variant of this exact approved artwork. Preserve the orange-to-teal sculptural M waveform, graphite background, lighting, composition, proportions, and colors exactly; do not redesign or reinterpret the mark. Change only its outer silhouette and placement: scale the entire existing square artwork uniformly into a centered rounded-square tile with gently continuous macOS-style corners. The tile should occupy about 82 percent of the canvas width and height, leaving approximately 9 percent transparent padding on every side. Clip the graphite background cleanly to the rounded-square silhouette. The exterior of the tile must be genuinely transparent alpha, not a black, white or checkerboard background. No added frame, text, objects, border, extra symbol or mockup. Straight-on flat icon, no perspective, no external cast shadow. Output a square transparent PNG suitable for packaging into an ICNS icon. Preserve the approved artwork inside the tile.
