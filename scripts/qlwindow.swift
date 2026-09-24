// Finds on-screen windows for the screenshot script.
// Usage: qlwindow OWNER [TITLE]
// Prints "<windowID> <x> <y> <width> <height>" for each window whose owner contains OWNER
// (case-insensitive) and, if given, whose title equals TITLE. Needs Screen Recording
// permission for titles to be visible.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let owner = args.count > 1 ? args[1].lowercased() : "quicklook"
let title = args.count > 2 ? args[2] : nil
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in info {
    let windowOwner = (window[kCGWindowOwnerName as String] as? String) ?? ""
    let windowTitle = (window[kCGWindowName as String] as? String) ?? ""
    guard windowOwner.lowercased().contains(owner), title == nil || windowTitle == title,
          let id = window[kCGWindowNumber as String] as? Int,
          let b = window[kCGWindowBounds as String] as? [String: CGFloat],
          let w = b["Width"], let h = b["Height"], w > 200, h > 200 else { continue }
    print(id, Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(w), Int(h))
}
