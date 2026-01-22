import Cocoa
import CoreGraphics
import CoreImage

let clipPath = "../SaneClip/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
let videoSourcePath = "../../web/saneapps.com/icons/sanevideo-icon.png"
let barPath = "Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"

func sampleColor(at point: NSPoint, from path: String) -> NSColor? {
    guard let img = NSImage(contentsOfFile: path),
          let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.colorAt(x: Int(point.x), y: Int(point.y))
}

// 1. Sample exact colors
// SaneBar Background (Top & Bottom)
let barTop = sampleColor(at: NSPoint(x: 512, y: 200), from: barPath) ?? .black
let barBottom = sampleColor(at: NSPoint(x: 512, y: 800), from: barPath) ?? .black

// SaneClip Glow (Sampling a bright part of the glow)
let clipGlow = sampleColor(at: NSPoint(x: 512, y: 512), from: clipPath) ?? .cyan

print("Sampled Colors:")
print("Background: \(barTop) -> \(barBottom)")
print("Glow: \(clipGlow)")

// 2. Process existing SaneVideo icon
guard let videoImg = NSImage(contentsOfFile: videoSourcePath),
      let tiffData = videoImg.tiffRepresentation,
      let ciImage = CIImage(data: tiffData) else {
    print("Error: Could not load source")
    exit(1)
}

let size = CGSize(width: 1024, height: 1024)
let renderer = NSImage(size: size)
renderer.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// --- Background Squircle ---
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: iconRect.width * 0.22, yRadius: iconRect.height * 0.22)
context.saveGState()
squircle.addClip()
let backgroundGradient = NSGradient(starting: barTop, ending: barBottom)
backgroundGradient?.draw(in: iconRect, angle: -90)
context.restoreGState()

// --- Tighten Glow (Using CIExposureAdjust and CIColorControls) ---
// This pushes the black point way up to "eat" the soft blur edges
let tightened = ciImage
    .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.0])
    .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 3.5, // Aggressive tightening
        kCIInputBrightnessKey: -0.2 // Keep darks dark
    ])

// --- Match SaneClip Color ---
// We use CIColorMatrix to map the purple/white of the original to the sampled Clip Glow
let colorMatched = tightened.applyingFilter("CIColorMatrix", parameters: [
    "inputRVector": CIVector(x: clipGlow.redComponent, y: 0, z: 0, w: 0),
    "inputGVector": CIVector(x: 0, y: clipGlow.greenComponent, z: 0, w: 0),
    "inputBVector": CIVector(x: 0, y: 0, z: clipGlow.blueComponent, w: 0),
    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.0)
])

// --- Draw Symbol ---
let ciContext = CIContext(cgContext: context, options: nil)
let symbolRect = CGRect(x: 212, y: 212, width: 600, height: 600)

// Layer 1: The sharp, color-matched core
context.setBlendMode(.screen)
ciContext.draw(colorMatched, in: symbolRect, from: ciImage.extent)

// Layer 2: A very tight secondary "halo"
context.setAlpha(0.4)
ciContext.draw(colorMatched.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4]), 
               in: symbolRect, from: ciImage.extent)

renderer.unlockFocus()

if let finalTiff = renderer.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: finalTiff),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_ManualAdjust_Icon.png"))
    print("SaneVideo_ManualAdjust_Icon.png created")
}
