import AppKit

let app = NSApplication.shared
// Accessory: no Dock icon, just the status item.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
