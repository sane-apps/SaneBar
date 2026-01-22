import Cocoa
import CoreGraphics

let size = CGSize(width: 1024, height: 1024)
let renderer = NSImage(size: size)

renderer.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// --- Helper: Continuous Corner Squircle ---
func createSquirclePath(in rect: CGRect) -> NSBezierPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
    return path
}

// --- Colors: "Sane" Family Deep Blue ---
let topColor = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.15, alpha: 1.0)
let bottomColor = NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.05, alpha: 1.0)
let neonBlue = NSColor(calibratedRed: 0.0, green: 0.7, blue: 1.0, alpha: 1.0)
let neonCyan = NSColor(calibratedRed: 0.3, green: 1.0, blue: 1.0, alpha: 1.0)

// --- 1. Background Squircle ---
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = createSquirclePath(in: iconRect)
context.saveGState()
squircle.addClip()
let backgroundGradient = NSGradient(starting: topColor, ending: bottomColor)
backgroundGradient?.draw(in: iconRect, angle: -90)
context.restoreGState()

// --- 2. Shield & Globe Design ---
func drawSymbols(in context: CGContext, color: NSColor, glow: CGFloat) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: glow, color: color.cgColor)
    color.setStroke()
    
    // Elegant Shield (Badge style)
    let sW: CGFloat = 340
    let sH: CGFloat = 420
    let sX = 512 - sW/2
    let sY = 512 - sH/2 + 20
    
    let shield = NSBezierPath()
    shield.move(to: CGPoint(x: 512, y: sY + sH))
    shield.line(to: CGPoint(x: sX + sW, y: sY + sH - 60))
    shield.curve(to: CGPoint(x: 512, y: sY), 
                 controlPoint1: CGPoint(x: sX + sW, y: sY + sH * 0.3), 
                 controlPoint2: CGPoint(x: 512 + sW * 0.2, y: sY))
    shield.curve(to: CGPoint(x: sX, y: sY + sH - 60), 
                 controlPoint1: CGPoint(x: 512 - sW * 0.2, y: sY), 
                 controlPoint2: CGPoint(x: sX, y: sY + sH * 0.3))
    shield.close()
    
    shield.lineWidth = 14
    shield.stroke()
    
    // Elegant Globe
    let gR = CGRect(x: 512 - 100, y: 512 - 100 + 40, width: 200, height: 200)
    let globe = NSBezierPath(ovalIn: gR)
    globe.append(NSBezierPath(ovalIn: gR.insetBy(dx: 50, dy: 0)))
    globe.append(NSBezierPath(ovalIn: gR.insetBy(dx: 85, dy: 0)))
    
    let equator = NSBezierPath()
    equator.move(to: CGPoint(x: gR.minX, y: gR.midY))
    equator.line(to: CGPoint(x: gR.maxX, y: gR.midY))
    globe.append(equator)
    
    globe.lineWidth = 8
    globe.stroke()
    
    context.restoreGState()
}

// Draw layered glow
drawSymbols(in: context, color: neonBlue.withAlphaComponent(0.3), glow: 60)
drawSymbols(in: context, color: neonBlue.withAlphaComponent(0.6), glow: 30)
drawSymbols(in: context, color: neonCyan, glow: 10)

// --- 3. Glossy Overlays ---
let topGloss = NSBezierPath(ovalIn: CGRect(x: -200, y: 600, width: 1424, height: 800))
context.saveGState()
squircle.addClip()
NSColor.white.withAlphaComponent(0.05).setFill()
topGloss.fill()
context.restoreGState()

renderer.unlockFocus()

if let tiffData = renderer.tiffRepresentation, 
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "SaneHosts_Preview.png"))
    print("SaneHosts_Preview.png updated with elegant squircle styling")
}