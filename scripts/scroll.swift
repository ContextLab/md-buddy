// Posts scroll-wheel events at a screen point (used to exercise live Quick Look panels).
// Usage: scroll X Y LINES   (negative LINES scrolls down)
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count == 4, let x = Double(a[1]), let y = Double(a[2]), let lines = Int32(a[3]) else {
    print("usage: scroll X Y LINES"); exit(2)
}
let point = CGPoint(x: x, y: y)
let saved = CGEvent(source: nil)?.location
CGWarpMouseCursorPosition(point)
usleep(100_000)
for _ in 0..<abs(lines) {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines < 0 ? -1 : 1, wheel2: 0, wheel3: 0)
    event?.location = point
    event?.post(tap: .cghidEventTap)
    usleep(15_000)
}
usleep(100_000)
if let saved { CGWarpMouseCursorPosition(saved) }
