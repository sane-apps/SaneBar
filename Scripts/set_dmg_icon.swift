import Cocoa

guard CommandLine.arguments.count == 3 else {
    print("Usage: swift set_dmg_icon.swift <icon_path> <dmg_path>")
    exit(1)
}

let iconPath = CommandLine.arguments[1]
let dmgPath = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: iconPath) else {
    print("Error: Failed to load icon at \(iconPath)")
    exit(1)
}

if NSWorkspace.shared.setIcon(image, forFile: dmgPath, options: []) {
    print("Icon set successfully")
} else {
    print("Error: Failed to set icon")
    exit(1)
}
