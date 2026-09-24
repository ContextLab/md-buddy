// Prints "<windowID> <width>x<height> <owner>" for on-screen windows whose owner matches argv[1].
// Used by scripts/screenshots.sh to capture only the Quick Look panel.
import CoreGraphics
import Foundation

let pattern = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : "quicklook"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in info {
    let owner = (window[kCGWindowOwnerName as String] as? String) ?? ""
    guard owner.lowercased().contains(pattern),
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          (window[kCGWindowLayer as String] as? Int) ?? 0 >= 0,
          let width = bounds["Width"], let height = bounds["Height"], width > 200, height > 200 else { continue }
    print("\(id) \(Int(width))x\(Int(height)) \(owner)")
}
