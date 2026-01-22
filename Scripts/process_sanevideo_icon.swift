import Cocoa
import CoreGraphics
import CoreImage

let size = CGSize(width: 1024, height: 1024)
let sourcePath = "../../web/saneapps.com/icons/sanevideo-icon.png"

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
    print("Error: Could not load source icon at \(sourcePath)")
    exit(1)
}

let renderer = NSImage(size: size)
renderer.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// --- 1. Sane Family Background: Deep Navy Squircle ---
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: iconRect.width * 0.22, yRadius: iconRect.height * 0.22)

let topColor = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.15, alpha: 1.0)
let bottomColor = NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.05, alpha: 1.0)

context.saveGState()
squircle.addClip()
let backgroundGradient = NSGradient(starting: topColor, ending: bottomColor)
backgroundGradient?.draw(in: iconRect, angle: -90)
context.restoreGState()

// --- 2. Process the Symbol (Tighten Glow & Retint) ---
// We convert to CIImage to apply filters
guard let tiffData = sourceImage.tiffRepresentation,
      let ciImage = CIImage(data: tiffData) else {
    print("Error: Could not process source image data")
    exit(1)
}

// Filter 1: High Contrast / Exposure to sharpen the "tight" glow
let processedSymbol = ciImage
    .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 2.5, // Sharpen the edges
        kCIInputBrightnessKey: 0.1
    ])
    .applyingFilter("CIColorMatrix", parameters: [
        // Tint to Sane Blue/Cyan (matches SaneBar/SaneClip)
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0.7, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 1.0, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.0)
    ])

// --- 3. Draw Processed Symbol onto Background ---
let ciContext = CIContext(cgContext: context, options: nil)
let symbolDestRect = CGRect(x: 212, y: 212, width: 600, height: 600)

// Layer 1: Subtle Atmospheric Glow (Very faint)
context.setAlpha(0.2)
ciContext.draw(processedSymbol.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 30]), 
               in: symbolDestRect, from: ciImage.extent)

// Layer 2: The "Tight" Glow Hug (Moderate blur)
context.setAlpha(0.6)
ciContext.draw(processedSymbol.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10]), 
               in: symbolDestRect, from: ciImage.extent)

// Layer 3: The Sharp Core (No blur)
context.setAlpha(1.0)
context.setBlendMode(.screen)
ciContext.draw(processedSymbol, in: symbolDestRect, from: ciImage.extent)

// --- 4. Glossy Overlay ---
let topGloss = NSBezierPath(ovalIn: CGRect(x: -200, y: 650, width: 1424, height: 800))
context.saveGState()
squircle.addClip()
NSColor.white.withAlphaComponent(0.04).setFill()
topGloss.fill()
context.restoreGState()

renderer.unlockFocus()

if let finalTiff = renderer.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: finalTiff),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_Processed_Icon.png"))
    print("SaneVideo_Processed_Icon.png created successfully")
}
