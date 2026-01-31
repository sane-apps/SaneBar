import Cocoa

// Fix SaneBar icon: composite existing icon onto full-square opaque background
// macOS applies its own squircle mask — we must NOT bake one in.

let iconSetPath = "Resources/Assets.xcassets/AppIcon.appiconset"
let fileManager = FileManager.default

// Restore icons from git first, then composite onto opaque background
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

// Background color sampled from the icon's dominant dark navy
let bgColor = NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.06, alpha: 1.0)

do {
    for (filename, pixelSize) in sizes {
        let fullPath = "\(iconSetPath)/\(filename)"
        guard let sourceImage = NSImage(contentsOfFile: fullPath) else {
            print("Skipped \(filename) — not found")
            continue
        }

        let size = CGSize(width: pixelSize, height: pixelSize)

        let outputBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputBitmap)

        // 1. Fill entire canvas with solid dark navy (no transparency)
        bgColor.setFill()
        CGRect(origin: .zero, size: size).fill()

        // 2. Draw the existing icon on top (transparent corners become navy)
        sourceImage.draw(in: CGRect(origin: .zero, size: size),
                        from: NSRect(origin: .zero, size: sourceImage.size),
                        operation: .sourceOver,
                        fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        if let pngData = outputBitmap.representation(using: .png, properties: [:]) {
            try pngData.write(to: URL(fileURLWithPath: fullPath))
            print("Fixed \(filename) — composited onto opaque background")
        }
    }
    print("\nDone. All icons are now full-square with no transparency.")
} catch {
    print("Error: \(error)")
}
