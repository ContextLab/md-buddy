import Foundation

/// Converts terminal output (notebook streams and tracebacks) to HTML.
///
/// The text is HTML-escaped; SGR color codes become `<span class="ansi-…">` (the 16 named
/// colors and bold, styled in style.css for light and dark) or an inline color for 256-color
/// and truecolor codes. Every other escape sequence is dropped. A carriage return moves back
/// to the start of the line and what follows is written over what was there, as in a
/// terminal, so a progress bar shows only its final state.
enum ANSI {
    private static let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

    private struct Style: Equatable {
        var bold = false
        var foregroundClass: String?
        var backgroundClass: String?
        var foregroundColor: String?
        var backgroundColor: String?

        var openingTag: String? {
            var classes: [String] = []
            if bold { classes.append("ansi-bold") }
            if let foregroundClass { classes.append(foregroundClass) }
            if let backgroundClass { classes.append(backgroundClass) }
            var styles: [String] = []
            if let foregroundColor { styles.append("color:\(foregroundColor)") }
            if let backgroundColor { styles.append("background-color:\(backgroundColor)") }
            if classes.isEmpty && styles.isEmpty { return nil }
            var tag = "<span"
            if !classes.isEmpty { tag += " class=\"\(classes.joined(separator: " "))\"" }
            if !styles.isEmpty { tag += " style=\"\(styles.joined(separator: ";"))\"" }
            return tag + ">"
        }
    }

    static func html(_ text: String) -> String {
        let scalars = Array(overwriteLines(text).unicodeScalars)
        var out = ""
        out.reserveCapacity(scalars.count + scalars.count / 8)
        var style = Style()
        var run = String.UnicodeScalarView()

        func flush() {
            guard !run.isEmpty else { return }
            let escaped = HTML.escape(String(run))
            if let tag = style.openingTag {
                out += tag + escaped + "</span>"
            } else {
                out += escaped
            }
            run = String.UnicodeScalarView()
        }

        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            guard scalar == "\u{1B}" else {
                run.append(scalar)
                i += 1
                continue
            }
            // ESC [ parameters final-byte. Anything else after ESC: drop the ESC alone.
            guard i + 1 < scalars.count, scalars[i + 1] == "[" else {
                i += 1
                continue
            }
            var j = i + 2
            var parameters = ""
            while j < scalars.count, !(0x40...0x7E).contains(scalars[j].value) {
                parameters.unicodeScalars.append(scalars[j])
                j += 1
            }
            if j < scalars.count, scalars[j] == "m" {
                var next = style
                apply(parameters, to: &next)
                if next != style {
                    flush()
                    style = next
                }
            }
            i = j + 1
        }
        flush()
        return out
    }

    /// Applies carriage returns the way a terminal (and Jupyter) does: the text after one is
    /// written over the start of the line, and whatever it does not cover stays. So
    /// "abcdef\rxy" shows "xycdef", and a "\r" with nothing after it changes nothing.
    private static func overwriteLines(_ text: String) -> String {
        guard text.unicodeScalars.contains("\r") else { return text }
        var out = String.UnicodeScalarView()
        var line: [Unicode.Scalar] = []
        var segment: [Unicode.Scalar] = []
        func overwrite() {
            guard !segment.isEmpty else { return }
            line = segment + line.dropFirst(segment.count)
            segment = []
        }
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                overwrite()
            case "\n":
                overwrite()
                out.append(contentsOf: line)
                out.append(scalar)
                line = []
            default:
                segment.append(scalar)
            }
        }
        overwrite()
        out.append(contentsOf: line)
        return String(out)
    }

    private static func apply(_ parameters: String, to style: inout Style) {
        let codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var k = 0
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0: style = Style()
            case 1: style.bold = true
            case 22: style.bold = false
            case 30...37:
                style.foregroundClass = "ansi-fg-\(names[code - 30])"
                style.foregroundColor = nil
            case 90...97:
                style.foregroundClass = "ansi-fg-bright-\(names[code - 90])"
                style.foregroundColor = nil
            case 39:
                style.foregroundClass = nil
                style.foregroundColor = nil
            case 40...47:
                style.backgroundClass = "ansi-bg-\(names[code - 40])"
                style.backgroundColor = nil
            case 100...107:
                style.backgroundClass = "ansi-bg-bright-\(names[code - 100])"
                style.backgroundColor = nil
            case 49:
                style.backgroundClass = nil
                style.backgroundColor = nil
            case 38, 48:
                let foreground = code == 38
                var named: String?
                var color: String?
                if k + 2 < codes.count, codes[k + 1] == 5 {
                    let n = codes[k + 2]
                    if (0..<8).contains(n) {
                        named = names[n]
                    } else if (8..<16).contains(n) {
                        named = "bright-" + names[n - 8]
                    } else {
                        color = paletteColor(n)
                    }
                    k += 2
                } else if k + 4 < codes.count, codes[k + 1] == 2 {
                    color = hex(codes[k + 2], codes[k + 3], codes[k + 4])
                    k += 4
                } else {
                    k = codes.count
                    continue
                }
                if foreground {
                    style.foregroundClass = named.map { "ansi-fg-\($0)" }
                    style.foregroundColor = color
                } else {
                    style.backgroundClass = named.map { "ansi-bg-\($0)" }
                    style.backgroundColor = color
                }
            default:
                break
            }
            k += 1
        }
    }

    /// Colors 16–255 of the xterm palette: a 6×6×6 cube, then 24 grays.
    private static func paletteColor(_ n: Int) -> String? {
        guard (16...255).contains(n) else { return nil }
        if n >= 232 {
            let level = 8 + 10 * (n - 232)
            return hex(level, level, level)
        }
        let levels = [0, 95, 135, 175, 215, 255]
        let index = n - 16
        return hex(levels[index / 36], levels[(index / 6) % 6], levels[index % 6])
    }

    private static func hex(_ r: Int, _ g: Int, _ b: Int) -> String {
        func clamp(_ value: Int) -> Int { min(max(value, 0), 255) }
        return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
    }
}
