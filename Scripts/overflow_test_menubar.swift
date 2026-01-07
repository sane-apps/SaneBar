#!/usr/bin/swift

import Foundation
import AppKit

print("🧪 --- [ MENU BAR OVERFLOW STRESS TEST ] ---")

var items: [NSStatusItem] = []
let count = 100

print("📦 Creating \(count) dummy status items with LONG titles to force overflow...")

for i in 1...count {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
        button.title = "Extremely Long Title For Dummy App Number \(i) - Overflow Testing"
    }
    items.append(item)
}

print("✅ Created \(count) long-title items.")
print("The menu bar should be severely overflowed now.")
print("Press Enter to clean up and exit...")

_ = readLine()

print("🧹 Cleaning up...")
items.removeAll()
print("Done!")
