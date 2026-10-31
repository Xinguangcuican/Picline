import CoreGraphics
import ImageIO
import Foundation

// Convert the approved artwork into a full macOS ICNS family. The source PNG
// stays unchanged; the native tile silhouette clips stray edge alpha on export.
guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    fputs("Usage: swift scripts/make-picline-icon.swift output.icns [preview.png]\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/Tendedero/Resources/Artwork/Picline-AppIcon.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height, artwork.width >= 1024 else {
    fputs("Could not load the approved square Picline artwork.\n", stderr)
    exit(1)
}
func uint32(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
func png(at size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let tile = canvas.insetBy(dx: CGFloat(size) * 0.075, dy: CGFloat(size) * 0.075)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.21,
                           cornerHeight: tile.height * 0.21, transform: nil))
    context.clip()
    // An opaque porcelain underlay keeps the exported tile's alpha a single
    // clean contour even where the generated source has small edge holes.
    context.setFillColor(CGColor(srgbRed: 0.97, green: 0.965, blue: 0.945, alpha: 1))
    context.fill(tile)
    context.interpolationQuality = .high
    context.draw(artwork, in: canvas)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    return data as Data
}
let representations = [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"),
                       (256, "ic08"), (512, "ic09"), (1024, "ic10"),
                       (32, "ic11"), (64, "ic12"), (256, "ic13"), (512, "ic14")]
var chunks = Data()
var cache: [Int: Data] = [:]
for (size, type) in representations {
    let data = cache[size] ?? png(at: size)
    cache[size] = data
    chunks.append(Data(type.utf8))
    chunks.append(uint32(data.count + 8))
    chunks.append(data)
}
var icon = Data("icns".utf8)
icon.append(uint32(chunks.count + 8))
icon.append(chunks)
try icon.write(to: output)
if CommandLine.arguments.count == 3 {
    try cache[1024]!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
