import Cocoa
import CoreGraphics

let sourcePath = "/Users/sj/Desktop/Screenshots/sanesync.png"
let websiteIconPath = "../../web/saneapps.com/icons/sanesync-icon.png"
let projectRoot = "../SaneSync/SaneSync/"
let xcassetsPath = "\(projectRoot)Assets.xcassets/"
let appIconPath = "\(xcassetsPath)AppIcon.appiconset/"

guard let img = NSImage(contentsOfFile: sourcePath) else {
    print("Error: Could not load \(sourcePath)")
    exit(1)
}

// 1. Ensure directory structure exists
let fm = FileManager.default
try? fm.createDirectory(atPath: appIconPath, withIntermediateDirectories: true)

// 2. Create Contents.json for AppIcon
let contentsJson = """
{
  "images": [
    { "size": "16x16", "idiom": "mac", "filename": "icon_16x16.png", "scale": "1x" },
    { "size": "16x16", "idiom": "mac", "filename": "icon_16x16@2x.png", "scale": "2x" },
    { "size": "32x32", "idiom": "mac", "filename": "icon_32x32.png", "scale": "1x" },
    { "size": "32x32", "idiom": "mac", "filename": "icon_32x32@2x.png", "scale": "2x" },
    { "size": "128x128", "idiom": "mac", "filename": "icon_128x128.png", "scale": "1x" },
    { "size": "128x128", "idiom": "mac", "filename": "icon_128x128@2x.png", "scale": "2x" },
    { "size": "256x256", "idiom": "mac", "filename": "icon_256x256.png", "scale": "1x" },
    { "size": "256x256", "idiom": "mac", "filename": "icon_256x256@2x.png", "scale": "2x" },
    { "size": "512x512", "idiom": "mac", "filename": "icon_512x512.png", "scale": "1x" },
    { "size": "512x512", "idiom": "mac", "filename": "icon_512x512@2x.png", "scale": "2x" }
  ],
  "info": { "version": 1, "author": "xcode" }
}
"""
try? contentsJson.write(toFile: "\(appIconPath)Contents.json", atomically: true, encoding: .utf8)

// 3. Squircle Generator
func createSquircleIcon(image: NSImage, size: CGSize, outputPath: String) {
    let renderer = NSImage(size: size)
    renderer.lockFocus()
    let rect = CGRect(origin: .zero, size: size)
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

// 4. Generate All Files
createSquircleIcon(image: img, size: CGSize(width: 1024, height: 1024), outputPath: "SaneSync_Final_Squircle.png")
createSquircleIcon(image: img, size: CGSize(width: 512, height: 512), outputPath: websiteIconPath)

let sizes = [16, 32, 128, 256, 512]
for s in sizes {
    createSquircleIcon(image: img, size: CGSize(width: s, height: s), outputPath: "\(appIconPath)icon_\(s)x\(s).png")
    createSquircleIcon(image: img, size: CGSize(width: s*2, height: s*2), outputPath: "\(appIconPath)icon_\(s)x\(s)@2x.png")
}

print("Success: SaneSync assets created and icon updated everywhere.")
