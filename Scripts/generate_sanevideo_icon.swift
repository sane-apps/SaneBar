import Cocoa
import CoreGraphics

let size = CGSize(width: 1024, height: 1024)
let renderer = NSImage(size: size)

renderer.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// --- Colors: The "Sane" Palette ---
let topColor = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.15, alpha: 1.0)
let bottomColor = NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.05, alpha: 1.0)
let neonPurple = NSColor(calibratedRed: 0.8, green: 0.2, blue: 1.0, alpha: 1.0) // SaneVideo primary
let neonViolet = NSColor(calibratedRed: 0.9, green: 0.5, blue: 1.0, alpha: 1.0) // Highlight

// --- 1. Background Squircle ---
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: iconRect.width * 0.22, yRadius: iconRect.height * 0.22)

context.saveGState()
squircle.addClip()
let backgroundGradient = NSGradient(starting: topColor, ending: bottomColor)
backgroundGradient?.draw(in: iconRect, angle: -90)
context.restoreGState()

// --- 2. Tight Glow Symbol Logic ---
func drawCameraSymbol(in context: CGContext, color: NSColor, blur: CGFloat, lineWidth: CGFloat) {
    context.saveGState()
    if blur > 0 {
        context.setShadow(offset: .zero, blur: blur, color: color.cgColor)
    }
    color.setStroke()
    
    let midX = size.width / 2
    let midY = size.height / 2
    
    // Main Camera Body (Rounded Rect)
    let bodyRect = CGRect(x: midX - 180, y: midY - 140, width: 300, height: 280)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 40, yRadius: 40)
    
    // Lens (Triangle/Trapezoid)
    let lensPath = NSBezierPath()
    lensPath.move(to: CGPoint(x: bodyRect.maxX + 10, y: midY - 60))
    lensPath.line(to: CGPoint(x: bodyRect.maxX + 130, y: midY - 110))
    lensPath.line(to: CGPoint(x: bodyRect.maxX + 130, y: midY + 110))
    lensPath.line(to: CGPoint(x: bodyRect.maxX + 10, y: midY + 60))
    lensPath.close()
    
    bodyPath.lineWidth = lineWidth
    lensPath.lineWidth = lineWidth
    bodyPath.stroke()
    lensPath.stroke()
    
    context.restoreGState()
}

// --- 3. Layering the Tight Glow ---
// Layer 1: Wide but very faint base
drawCameraSymbol(in: context, color: neonPurple.withAlphaComponent(0.2), blur: 40, lineWidth: 12)
// Layer 2: Medium tight glow
drawCameraSymbol(in: context, color: neonPurple.withAlphaComponent(0.5), blur: 15, lineWidth: 10)
// Layer 3: The "Core" - Bright and sharp
drawCameraSymbol(in: context, color: neonViolet, blur: 4, lineWidth: 8)

// --- 4. Finishing Touch: Subtle Glass Reflection ---
let topGloss = NSBezierPath(ovalIn: CGRect(x: -200, y: 650, width: 1424, height: 800))
context.saveGState()
squircle.addClip()
NSColor.white.withAlphaComponent(0.03).setFill()
topGloss.fill()
context.restoreGState()

renderer.unlockFocus()

if let tiffData = renderer.tiffRepresentation, 
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneVideo_TightGlow_Preview.png"))
    print("SaneVideo_TightGlow_Preview.png created")
}
