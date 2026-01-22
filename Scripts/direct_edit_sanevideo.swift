import Cocoa
import CoreImage

let sourcePath = "../../web/saneapps.com/icons/sanevideo-icon.png"
let clipPath = "../SaneClip/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"

// 1. Sample SaneClip Color
func sampleColor(at point: NSPoint, from path: String) -> NSColor? {
    guard let img = NSImage(contentsOfFile: path),
          let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.colorAt(x: Int(point.x), y: Int(point.y))
}
let clipGlow = sampleColor(at: NSPoint(x: 512, y: 512), from: clipPath) ?? .cyan

// 2. Load Original SaneVideo
guard let sourceImage = NSImage(contentsOfFile: sourcePath),
      let tiffData = sourceImage.tiffRepresentation,
      let ciImage = CIImage(data: tiffData) else {
    print("Error: Could not load \(sourcePath)")
    exit(1)
}

// 3. Apply "Tighten" Filters directly to the original image
// Increase contrast to shrink the soft glow edges, decrease brightness to keep background black
let processed = ciImage
    .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 2.8,
        kCIInputBrightnessKey: -0.15
    ])
    .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: clipGlow.redComponent, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: clipGlow.greenComponent, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: clipGlow.blueComponent, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.0)
    ])

// 4. Save result
let context = CIContext()
if let cgImage = context.createCGImage(processed, from: processed.extent) {
    let size = NSSize(width: cgImage.width, height: cgImage.height)
    let finalImg = NSImage(cgImage: cgImage, size: size)
    if let finalTiff = finalImg.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: finalTiff),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_DirectEdit.png"))
        print("SaneVideo_DirectEdit.png created from original source")
    }
}
