import Cocoa
import CoreGraphics
import UniformTypeIdentifiers

// Simple SaneBar icon: dark gradient background + bright teal bars
// Full-square, no squircle (macOS applies its own mask)

let iconSetPath = "Resources/Assets.xcassets/AppIcon.appiconset"

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let refSize: CGFloat = 512

// Background gradient
let bgTop = NSColor(calibratedRed: 0.102, green: 0.153, blue: 0.267, alpha: 1.0)    // #1a2744
let bgBottom = NSColor(calibratedRed: 0.051, green: 0.082, blue: 0.145, alpha: 1.0)  // #0d1525

// Bright teal bars
let barColor = NSColor(calibratedRed: 0.36, green: 0.91, blue: 1.0, alpha: 1.0)      // #5CE8FF

// Bars at 512px reference: (x, y from TOP, width, height)
// Top bar widest, bottom bar narrowest — all centered
struct Bar { let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat }
let bars = [
    Bar(x: 120, y: 155, w: 272, h: 34),  // top (widest)
    Bar(x: 146, y: 239, w: 220, h: 34),  // middle
    Bar(x: 176, y: 323, w: 160, h: 34),  // bottom (narrowest)
]

for (filename, px) in sizes {
    let size = CGFloat(px)
    let scale = size / refSize

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let fullRect = CGRect(origin: .zero, size: CGSize(width: size, height: size))

    // 1. Background gradient (diagonal)
    let gradient = NSGradient(starting: bgTop, ending: bgBottom)!
    gradient.draw(in: fullRect, angle: -45)

    // 2. Draw bars (y from top: NSGraphicsContext is flipped by default for bitmapImageRep)
    barColor.setFill()
    for bar in bars {
        let rect = CGRect(x: bar.x * scale, y: bar.y * scale, width: bar.w * scale, height: bar.h * scale)
        let path = NSBezierPath(roundedRect: rect, xRadius: (bar.h / 2) * scale, yRadius: (bar.h / 2) * scale)
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    // Flatten onto opaque CGContext (no alpha in final PNG)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let opaqueCtx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { print("FAIL: \(filename) opaque context"); continue }

    // Fill with background base color, then composite rendered icon on top
    opaqueCtx.setFillColor(CGColor(red: 0.051, green: 0.082, blue: 0.145, alpha: 1.0))
    opaqueCtx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    if let cgImg = bitmap.cgImage {
        // NSBitmapImageRep is flipped (y=0 at top), CGContext is not (y=0 at bottom)
        opaqueCtx.translateBy(x: 0, y: CGFloat(px))
        opaqueCtx.scaleBy(x: 1, y: -1)
        opaqueCtx.draw(cgImg, in: CGRect(x: 0, y: 0, width: px, height: px))
    }

    guard let finalImage = opaqueCtx.makeImage() else { print("FAIL: \(filename) makeImage"); continue }
    let url = URL(fileURLWithPath: "\(iconSetPath)/\(filename)") as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        print("FAIL: \(filename) dest"); continue
    }
    CGImageDestinationAddImage(dest, finalImage, nil)
    CGImageDestinationFinalize(dest)
    print("OK \(filename) [opaque]")
}
print("Done.")
