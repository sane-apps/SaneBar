#!/usr/bin/swift

import Foundation
import AppKit

print("🧪 --- [ MENU BAR STRESS TEST ] ---")

var items: [NSStatusItem] = []
let count = 50

print("📦 Creating \(count) dummy status items...")

for i in 1...count {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
        button.title = "App \(i)"
    }
    items.append(item)
}

print("✅ Created \(count) items. They should be filling up your menu bar now.")
print("Press Enter to clean up and exit...")

_ = readLine()

print("🧹 Cleaning up...")
items.removeAll()
print("Done!")
