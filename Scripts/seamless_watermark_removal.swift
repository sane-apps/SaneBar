import Cocoa
import CoreGraphics

let path = "/Users/sj/Desktop/Screenshots/SaneVideo.png"
guard let img = NSImage(contentsOfFile: path),
      let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else {
    print("Error: Could not load image")
    exit(1)
}

let size = CGSize(width: 2048, height: 2048)
let renderer = NSImage(size: size)
renderer.lockFocus()
img.draw(in: CGRect(origin: .zero, size: size))

// To fix the "bald" look, we sample the background from the LEFT side 
// (which should have the same gradient) and copy it to the RIGHT side.
// We'll take a vertical strip from the left and mirror/apply it to the right corner.

let sourceStripX: Int = 100
let targetStripX: Int = 1600
let widthToCover: Int = 448

for y in 0..<500 { // Only need to fix the bottom area
    let sampledColor = bitmap.colorAt(x: sourceStripX, y: 2048 - y) // Sample from left
    sampledColor?.set()
    
    // Draw horizontal lines to rebuild the gradient across the target area
    let rect = CGRect(x: targetStripX, y: y, width: widthToCover, height: 1)
    rect.fill()
}

renderer.unlockFocus()

if let finalTiff = renderer.tiffRepresentation,
   let finalBitmap = NSBitmapImageRep(data: finalTiff),
   let pngData = finalBitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_Seamless_Clean.png"))
    print("SaneVideo_Seamless_Clean.png created")
}
