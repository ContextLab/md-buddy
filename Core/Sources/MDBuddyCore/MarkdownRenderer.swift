import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Converts Markdown to an HTML fragment using cmark-gfm (CommonMark + GitHub extensions).
public enum MarkdownRenderer {
    /// GFM extensions enabled on every parse. `tagfilter` neutralises the handful of raw
    /// HTML tags GitHub also blocks (script, iframe, style, textarea, ...).
    static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    static let options: Int32 =
        CMARK_OPT_UNSAFE            // keep raw HTML (tagfilter + CSP make this safe to display)
        | CMARK_OPT_FOOTNOTES
        | CMARK_OPT_VALIDATE_UTF8
        | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE

    private static let registerExtensions: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    /// Renders `markdown` to an HTML body fragment. A leading YAML/TOML front-matter block
    /// is shown as a collapsible code block rather than being parsed as Markdown.
    public static func render(_ markdown: String) -> String {
        // Swift treats "\r\n" as one Character, so normalise line endings before splitting.
        let normalized = markdown.contains("\r\n") ? markdown.replacingOccurrences(of: "\r\n", with: "\n") : markdown
        let (frontMatter, body) = FrontMatter.split(normalized)
        var html = ""
        if let frontMatter {
            html += "<details class=\"front-matter\"><summary>Front matter</summary>"
            html += "<pre><code class=\"language-\(frontMatter.language)\">"
            html += HTML.escape(frontMatter.text)
            html += "</code></pre></details>\n"
        }
        html += renderCommonMark(body)
        return html
    }

    static func renderCommonMark(_ markdown: String) -> String {
        _ = registerExtensions
        guard let parser = cmark_parser_new(options) else { return HTML.escape(markdown) }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        markdown.withCString { cmark_parser_feed(parser, $0, strlen($0)) }
        guard let document = cmark_parser_finish(parser) else { return HTML.escape(markdown) }
        defer { cmark_node_free(document) }

        guard let rendered = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
            return HTML.escape(markdown)
        }
        defer { free(rendered) }
        return String(cString: rendered)
    }
}

/// Detects a front-matter block at the very top of a Markdown document.
enum FrontMatter {
    struct Block: Equatable {
        let text: String
        let language: String
    }

    static func split(_ markdown: String) -> (Block?, String) {
        let fences: [(open: String, close: [String], language: String)] = [
            ("---", ["---", "..."], "yaml"),
            ("+++", ["+++"], "toml"),
        ]
        var text = Substring(markdown)
        if text.hasPrefix("\u{FEFF}") { text = text.dropFirst() }

        for fence in fences {
            guard text.hasPrefix(fence.open) else { continue }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
            guard let first = lines.next(), first.trimmingCharacters(in: .whitespacesAndNewlines) == fence.open else { continue }
            var inner: [Substring] = []
            var consumed = first.count + 1
            while let line = lines.next() {
                consumed += line.count + 1
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if fence.close.contains(trimmed) {
                    // An empty "---\n---" pair is a thematic break, not front matter.
                    guard !inner.isEmpty else { return (nil, markdown) }
                    let rest = text.dropFirst(min(consumed, text.count))
                    let body = inner.joined(separator: "\n").trimmingCharacters(in: .newlines)
                    return (Block(text: body, language: fence.language), String(rest))
                }
                inner.append(line)
            }
            return (nil, markdown)
        }
        return (nil, markdown)
    }
}

public enum HTML {
    public static func escape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.utf8.count + string.utf8.count / 8)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
