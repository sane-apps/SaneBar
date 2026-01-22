import Cocoa
import CoreGraphics

let sourcePath = "/Users/sj/Desktop/Screenshots/SaneVideo.png"
let websiteIconPath = "../../web/saneapps.com/icons/sanevideo-icon.png"
let projectAssetsPath = "../SaneVideo/SaneVideo/Assets.xcassets/AppIcon.appiconset/"

guard let img = NSImage(contentsOfFile: sourcePath) else {
    print("Error: Could not load your edited image")
    exit(1)
}

func createSquircleIcon(image: NSImage, size: CGSize, outputPath: String) {
    let renderer = NSImage(size: size)
    renderer.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    
    let rect = CGRect(origin: .zero, size: size)
    
    // Create the professional macOS squircle mask (approx 22% corner radius)
    let path = NSBezierPath(roundedRect: rect, xRadius: size.width * 0.22, yRadius: size.height * 0.22)
    path.addClip()
    
    image.draw(in: rect)
    
    renderer.unlockFocus()
    
    if let tiff = renderer.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: outputPath))
    }
}

// 1. Create Final Preview
createSquircleIcon(image: img, size: CGSize(width: 1024, height: 1024), outputPath: "SaneVideo_Final_Squircle.png")

// 2. Update Website
createSquircleIcon(image: img, size: CGSize(width: 512, height: 512), outputPath: websiteIconPath)

// 3. Update Project Assets
let sizes = [16, 32, 128, 256, 512]
for s in sizes {
    createSquircleIcon(image: img, size: CGSize(width: s, height: s), outputPath: "\(projectAssetsPath)icon_\(s)x\(s).png")
    createSquircleIcon(image: img, size: CGSize(width: s*2, height: s*2), outputPath: "\(projectAssetsPath)icon_\(s)x\(s)@2x.png")
}

print("Success: SaneVideo icon updated in project, website, and final preview created.")
