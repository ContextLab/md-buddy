import Foundation

/// Bundled CSS/JS, loaded once per extension process and inlined into every page
/// (the page has no network or file access for its own assets).
enum Resources {
    static func load(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            // A missing resource is a packaging bug; make it visible rather than silently unstyled.
            return "/* MD Buddy: missing resource \(name) */"
        }
        return text
    }

    static let stylesheet: String = {
        // highlight.js themes are scoped to the colour scheme so one page works in light and dark mode.
        load("style.css")
            + "\n@media (prefers-color-scheme: light) {\n" + load("github.min.css") + "\n}\n"
            + "@media (prefers-color-scheme: dark) {\n" + load("github-dark.min.css") + "\n}\n"
    }()

    static let appJS = load("app.js")
    static let highlighter = load("highlight.min.js") + "\n" + load("highlight-extra.min.js")

    /// The page script; highlight.js (~180 KB) is only included when there is code to colour.
    static func appScript(highlight: Bool) -> String {
        highlight ? highlighter + "\n" + appJS : appJS
    }
}
