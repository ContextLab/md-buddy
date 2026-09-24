import Foundation

/// Builds the complete, self-contained HTML page shown in the Quick Look panel.
public struct PreviewDocument {
    /// Files larger than this are truncated before rendering.
    public static let maxBytes = 8 * 1024 * 1024
    /// Code larger than this is shown without syntax highlighting (highlight.js is ~1 MB/s).
    public static let maxHighlightBytes = 1 * 1024 * 1024
    /// Auto-detecting a language is much slower than highlighting a known one.
    public static let maxAutoDetectBytes = 64 * 1024

    public let kind: DocumentKind
    public let title: String
    public let html: String

    public init(fileName: String, data: Data, kind: DocumentKind? = nil) {
        let kind = kind ?? DocumentKind.detect(fileName: fileName)
        self.kind = kind
        self.title = fileName

        let truncated = data.count > Self.maxBytes
        guard let text = TextDecoding.decode(truncated ? Self.utf8SafePrefix(data, Self.maxBytes) : data) else {
            html = Self.page(title: fileName, bodyClass: "notice",
                             body: "<p>This file does not appear to contain text.</p>", script: nil)
            return
        }

        var notice = ""
        if truncated {
            notice = "<div class=\"mdb-notice\">Showing the first \(Self.maxBytes / 1024 / 1024) MB of "
                + "\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)).</div>"
        }

        switch kind {
        case .markdown:
            let body = MarkdownRenderer.render(text)
            let script = Resources.appScript(highlight: body.contains("<code class=\"language-"))
            html = Self.page(title: fileName, bodyClass: "markdown",
                             body: notice + "<article class=\"markdown-body\">\(body)</article>", script: script)

        case .plainText:
            html = Self.page(title: fileName, bodyClass: "plaintext",
                             body: notice + "<pre class=\"plaintext\">\(HTML.escape(text))</pre>", script: nil)

        case .code(let language):
            let size = text.utf8.count
            let highlightLanguage: String?
            if size > Self.maxHighlightBytes {
                highlightLanguage = nil
            } else if let language {
                highlightLanguage = language == "plaintext" ? nil : language
            } else {
                highlightLanguage = size <= Self.maxAutoDetectBytes ? "auto" : nil
            }
            html = Self.page(title: fileName, bodyClass: "code",
                             body: notice + CodeView.render(text, language: highlightLanguage),
                             script: Resources.appScript(highlight: highlightLanguage != nil))
        }
    }

    /// Cuts `data` to at most `count` bytes without splitting a UTF-8 sequence.
    static func utf8SafePrefix(_ data: Data, _ count: Int) -> Data {
        var end = min(count, data.count)
        guard end < data.count else { return data }
        // Back up over continuation bytes (10xxxxxx) to the start of the cut character.
        var back = 0
        while end > 0, back < 4, data[data.startIndex + end] & 0xC0 == 0x80 {
            end -= 1
            back += 1
        }
        return data.prefix(end)
    }

    static func page(title: String, bodyClass: String, body: String, script: String?) -> String {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        // Raw HTML in Markdown is allowed, but only our own nonce-tagged script may run,
        // and nothing may be fetched except images/media.
        let csp = [
            "default-src 'none'",
            "img-src * data: blob: mdbuddy-local:",
            "media-src * data: blob: mdbuddy-local:",
            "style-src 'unsafe-inline'",
            "font-src data:",
            "script-src 'nonce-\(nonce)'",
        ].joined(separator: "; ")
        var page = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(HTML.escape(title))</title>
        <style>\(Resources.stylesheet)</style>
        </head>
        <body class="\(bodyClass)">
        \(body)

        """
        if let script {
            page += "<script nonce=\"\(nonce)\">\(script)</script>\n"
        }
        page += "</body>\n</html>\n"
        return page
    }
}

/// Renders source code as a line-numbered, optionally highlighted block.
enum CodeView {
    static func render(_ text: String, language: String?) -> String {
        var lineCount = 1
        for byte in text.utf8 where byte == UInt8(ascii: "\n") { lineCount += 1 }
        if text.hasSuffix("\n") { lineCount -= 1 }
        lineCount = max(lineCount, 1)

        var gutter = ""
        gutter.reserveCapacity(lineCount * 5)
        for n in 1...lineCount {
            gutter += String(n)
            gutter += "\n"
        }

        let languageAttr = language.map { " data-language=\"\(HTML.escape($0))\"" } ?? ""
        let codeClass = language.map { $0 == "auto" ? "" : "language-\($0)" } ?? "nohighlight"
        return """
        <div class="code-view"><pre class="gutter" aria-hidden="true">\(gutter)</pre>\
        <pre class="source"><code class="\(codeClass)"\(languageAttr)>\(HTML.escape(text))</code></pre></div>
        """
    }
}
