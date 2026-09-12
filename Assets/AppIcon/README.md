# MyStat app icon

Designed in Pixelmator Pro using editable vector shapes: three flat bars on a charcoal background. The bars share a baseline, width, and corner radius. Orange identifies the first bar; teal carries the other two. The layered source is the design master.

## Files

- `MyStat.pxd`: editable Pixelmator Pro document, with named CPU, Memory, Network, and Charcoal Background layers.
- `MyStat-iOS.png`: full-size 1024 × 1024 opaque sRGB PNG exported from Pixelmator Pro.
- `MyStat-macOS.png`: the same artwork in a transparent Mac tile, prepared by the packaging script.
- `AppIcon.icns`: standard Mac icon representations, copied into the app by `build.sh`.
- The iPhone's packaged icon is `MyStat-iOS/MyStat-iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Design dimensions

On the 1024 × 1024 canvas, the background is `#171C25`. All bars are 144 pixels wide with 32-pixel corner radii and end at y = 784.

| Layer | Position (x, y) | Height | Fill |
| --- | --- | --- | --- |
| CPU — Short | 224, 544 | 240 | `#FF9F43` |
| Memory — Mid | 440, 400 | 384 | `#50D8C2` |
| Network — Tall | 656, 240 | 544 | `#50D8C2` |

## Editing and export

1. Open `MyStat.pxd` in Pixelmator Pro and edit the named shape layers.
2. Save the document, then export an original-size PNG in sRGB as `MyStat-iOS.png` in this folder.
3. Run the packaging commands from the repository root:

```sh
swift scripts/generate-app-icons.swift
./build.sh
```

The packaging script places the exported artwork inside an 824 × 824 rounded tile with a 100-pixel transparent margin for macOS, and writes the 16–1024 pixel ICNS representations. It also writes the opaque 1024-pixel iPhone asset. The icon artwork itself is authored in Pixelmator; packaging does not redraw the bars.
