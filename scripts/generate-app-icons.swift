#!/usr/bin/env swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Package artwork drawn in Pixelmator Pro into platform icon formats.
// Only the Mac tile mask and platform-specific sizes are applied here.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let artwork = root.appendingPathComponent("Assets/AppIcon")
let fm = FileManager.default

func load(_ name: String) throws -> CGImage {
    let url = artwork.appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == image.height else {
        throw NSError(domain: "MyStatIcons", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing or non-square artwork: \(url.path)"])
    }
    return image
}

func write(_ image: CGImage, size: Int, alpha: Bool, to url: URL) throws {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue) else {
        throw NSError(domain: "MyStatIcons", code: 2)
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let resized = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "MyStatIcons", code: 3)
    }
    CGImageDestinationAddImage(destination, resized, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "MyStatIcons", code: 4) }
}

func macTile(from image: CGImage) throws -> CGImage {
    guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "MyStatIcons", code: 6)
    }
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(image, in: tile)
    guard let result = context.makeImage() else { throw NSError(domain: "MyStatIcons", code: 7) }
    return result
}

do {
    let ios = try load("MyStat-iOS.png")
    let mac = try macTile(from: ios)
    try write(mac, size: 1024, alpha: true, to: artwork.appendingPathComponent("MyStat-macOS.png"))
    let catalog = root.appendingPathComponent("MyStat-iOS/MyStat-iOS/Assets.xcassets/AppIcon.appiconset")
    try write(ios, size: 1024, alpha: false, to: catalog.appendingPathComponent("AppIcon.png"))

    let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        try write(mac, size: size, alpha: true, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        try write(mac, size: size * 2, alpha: true, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", artwork.appendingPathComponent("AppIcon.icns").path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "MyStatIcons", code: 5) }
    print("Generated iOS AppIcon.png and macOS AppIcon.icns")
} catch {
    fputs("Icon packaging failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
