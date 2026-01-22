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

// To ensure a perfect gradient, we sample from the TOP-LEFT
// and apply it to the BOTTOM-RIGHT.
// Image coordinate system in Cocoa is (0,0) = bottom-left.
// So "Top Left" is high Y, low X.

let sourceX = 100
let targetX = 1600
let widthToCover = 448

// We'll rebuild the entire right side of the gradient from top to bottom
// based on the left side's colors to ensure no seams.
for y in 0..<2048 {
    let sampledColor = bitmap.colorAt(x: sourceX, y: y) // NSBitmapImageRep is also bottom-left (0,0)
    sampledColor?.set()
    
    let rect = CGRect(x: targetX, y: y, width: widthToCover, height: 1)
    rect.fill()
}

renderer.unlockFocus()

if let finalTiff = renderer.tiffRepresentation,
   let finalBitmap = NSBitmapImageRep(data: finalTiff),
   let pngData = finalBitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_TopLeft_Sample_Clean.png"))
    print("SaneVideo_TopLeft_Sample_Clean.png created")
}
