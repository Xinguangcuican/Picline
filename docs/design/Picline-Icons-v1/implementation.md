# Picline icon integration

The selected design is the off-white tile with two hanging aqua photographs and teal clips, confirmed by the user via the original image attachment. It corresponds to `Picline-A-hanging-cards.png`, regardless of the earlier A/B/C ordering confusion.

- Approved source: `Sources/Tendedero/Resources/Artwork/Picline-AppIcon.png`, copied unchanged from the selected concept.
- Artwork provenance and original built-in imagegen prompt: [prompts.md](prompts.md), concept A.
- Exporter: `scripts/make-picline-icon.swift`. It exports the native rounded tile at 16–1024 pixels with Retina representations, retaining the illustration, and supplies a solid porcelain backing within the tile mask to keep the outer alpha clean.
- Export preview: [Picline-AppIcon-final.png](Picline-AppIcon-final.png).
- Menu bar: `Sources/Tendedero/MenuBarIcon.swift`, drawn with AppKit/CoreGraphics at 20 × 18 points. A curved cord, a short clip, and one photo frame form a monochrome template image. The frame fills when clipboard intake is enabled. The system controls tint for light, dark and highlighted states.
- Menu bar preview: [Picline-MenuBar-preview.png](Picline-MenuBar-preview.png), showing light and dark backgrounds, outline/filled states, and both enlarged and actual-size drawings.

The application keeps its existing bundle identifier and data-directory compatibility. The 0.1.6 package is built into a separate output directory so the previous package remains available.
