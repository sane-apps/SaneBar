import Cocoa
import CoreImage

let sourcePath = "../../web/saneapps.com/icons/sanevideo-icon.png"

guard let sourceImage = NSImage(contentsOfFile: sourcePath),
      let tiffData = sourceImage.tiffRepresentation,
      let ciImage = CIImage(data: tiffData) else {
    print("Error: Could not load \(sourcePath)")
    exit(1)
}

// Apply only Contrast and Gamma to tighten the glow WITHOUT changing the hue
// This "squeezes" the existing colors closer to the center of the bars
let processed = ciImage
    .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 2.2,
        kCIInputBrightnessKey: -0.1
    ])
    .applyingFilter("CIGammaAdjust", parameters: [
        "inputPower": 1.5 // Darkens the mid-tones (the soft blur) while keeping the brights
    ])

let context = CIContext()
if let cgImage = context.createCGImage(processed, from: ciImage.extent) {
    let finalImg = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    if let finalTiff = finalImg.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: finalTiff),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_OriginalColor_TightGlow.png"))
        print("SaneVideo_OriginalColor_TightGlow.png created")
    }
}
