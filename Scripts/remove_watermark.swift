import Cocoa
import CoreGraphics

let path = "/Users/sj/Desktop/Screenshots/SaneVideo.png"
guard let img = NSImage(contentsOfFile: path),
      let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else {
    print("Error: Could not load image")
    exit(1)
}

// 1. Sample background color from top-left (0,0)
let bgColor = bitmap.colorAt(x: 10, y: 10) ?? .black

// 2. Draw background color over the bottom-right watermark area
// The image is 2048x2048. We'll cover a reasonable corner area.
let size = CGSize(width: 2048, height: 2048)
let renderer = NSImage(size: size)
renderer.lockFocus()
img.draw(in: CGRect(origin: .zero, size: size))

// Assuming the watermark is in the bottom right corner. 
// We'll cover the bottom 15% of the right side.
let coverRect = CGRect(x: 1600, y: 0, width: 448, height: 300)
bgColor.set()
coverRect.fill()

renderer.unlockFocus()

// 3. Save
if let finalTiff = renderer.tiffRepresentation,
   let finalBitmap = NSBitmapImageRep(data: finalTiff),
   let pngData = finalBitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_Clean.png"))
    print("SaneVideo_Clean.png created")
}
