import Foundation

/// Renders a notebook as the body of a preview page.
///
/// Markup from the notebook itself is never written into the page directly. Rendered
/// Markdown cells and HTML outputs are emitted *escaped* inside
/// `<div class="nb-fragment" data-mode="light|shadow" hidden>`, and the page script inserts
/// each one into its own container (HTML outputs into a shadow root). An unclosed tag or a
/// `<style>` block in one cell therefore cannot swallow or restyle the cells after it.
enum NotebookRenderer {
    struct Page {
        var html = ""
        /// Whether the page needs KaTeX / highlight.js.
        var math = false
        var highlight = false
    }

    /// The richest static form wins, in this order.
    static let mimeOrder = ["text/html", "image/svg+xml", "image/png", "image/jpeg", "image/gif",
                            "text/markdown", "text/latex", "application/json", "text/plain"]

    /// Image types a Markdown cell attachment may be inlined as.
    static let attachmentTypes = ["image/png", "image/jpeg", "image/gif", "image/svg+xml", "image/webp", "image/bmp"]

    static func render(_ notebook: Notebook) -> Page {
        var page = Page()
        if notebook.cells.isEmpty {
            page.html = "<p class=\"nb-empty\">This notebook has no cells.</p>"
            return page
        }
        for cell in notebook.cells {
            switch cell {
            case let .markdown(source, attachments):
                let html = markdown(inlineAttachments(source, attachments))
                page.html += "<section class=\"nb-cell nb-markdown\">\(fragment(html, mode: "light", page: &page))</section>\n"

            case let .raw(source):
                page.html += "<section class=\"nb-cell nb-raw\"><pre>\(HTML.escape(source))</pre></section>\n"

            case let .code(source, executionCount, outputs):
                let highlighted = source.utf8.count <= PreviewDocument.maxHighlightBytes
                if highlighted { page.highlight = true }
                page.html += "<section class=\"nb-cell nb-code\"><div class=\"nb-input\">"
                page.html += "<div class=\"nb-prompt\">[\(executionCount.map(String.init) ?? " ")]:</div>"
                page.html += "<pre class=\"nb-source\"><code class=\"\(highlighted ? "language-\(notebook.language)" : "nohighlight")\">"
                page.html += HTML.escape(source)
                page.html += "</code></pre></div>"
                let rendered = outputs.map { output($0, page: &page) }.joined()
                if !rendered.isEmpty { page.html += "<div class=\"nb-outputs\">\(rendered)</div>" }
                page.html += "</section>\n"
            }
        }
        return page
    }

    // MARK: Markdown

    private static func markdown(_ source: String) -> String {
        RemoteImages.rewrite(MarkdownRenderer.render(source, bareMathEnvironments: true))
    }

    /// Escaped HTML for the page script to insert; notes what the fragment needs from the page.
    private static func fragment(_ html: String, mode: String, page: inout Page) -> String {
        if mode == "light" {
            if html.contains("class=\"math ") { page.math = true }
            if html.contains("<code class=\"language-") { page.highlight = true }
        }
        return "<div class=\"nb-fragment\" data-mode=\"\(mode)\" hidden>\(HTML.escape(html))</div>"
    }

    /// Replaces `attachment:name` references with the attached image as a data: URI.
    private static func inlineAttachments(_ source: String, _ attachments: [String: [String: String]]) -> String {
        guard !attachments.isEmpty, source.contains("attachment:") else { return source }
        var result = source
        for name in attachments.keys.sorted(by: { $0.count > $1.count }) {
            guard let bundle = attachments[name],
                  let mime = attachmentTypes.first(where: { bundle[$0] != nil }),
                  let data = base64(bundle[mime]) else { continue }
            let uri = "data:\(mime);base64,\(data)"
            var spellings = ["attachment:\(name)"]
            if let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), encoded != name {
                spellings.append("attachment:\(encoded)")
            }
            for spelling in spellings {
                result = result.replacingOccurrences(of: spelling, with: uri)
            }
        }
        return result
    }

    // MARK: Outputs

    private static func output(_ output: Notebook.Output, page: inout Page) -> String {
        switch output {
        case let .stream(name, text):
            return wrap("nb-stream nb-\(name)", body: "<pre>\(ANSI.html(text))</pre>")

        case let .error(name, value, traceback):
            let text = traceback.isEmpty ? "\(name): \(value)" : traceback.joined(separator: "\n")
            return wrap("nb-error", body: "<pre>\(ANSI.html(text))</pre>")

        case let .data(bundle, metadata, executionCount):
            guard !bundle.isEmpty else { return "" }
            for mime in mimeOrder {
                if let body = body(for: mime, in: bundle, metadata: metadata, page: &page) {
                    return wrap(executionCount == nil ? "nb-display" : "nb-result",
                                prompt: executionCount.map { "[\($0)]:" } ?? "", body: body)
                }
            }
            let types = HTML.escape(bundle.keys.sorted().joined(separator: ", "))
            return "<div class=\"nb-output nb-unsupported\">Output of type \(types) can&#39;t be shown in a static preview.</div>"
        }
    }

    private static func wrap(_ classes: String, prompt: String = "", body: String) -> String {
        "<div class=\"nb-output \(classes)\"><div class=\"nb-prompt\">\(prompt)</div>"
            + "<div class=\"nb-body\">\(body)</div></div>"
    }

    /// The HTML for one MIME type of an output bundle, or nil when the bundle has no usable
    /// value of that type.
    private static func body(for mime: String, in bundle: [String: Any], metadata: [String: Any],
                             page: inout Page) -> String? {
        guard let value = bundle[mime] else { return nil }
        switch mime {
        case "text/html":
            guard let html = Notebook.text(value), !isScriptShell(html) else { return nil }
            return fragment(html, mode: "shadow", page: &page)

        case "image/svg+xml":
            guard let svg = Notebook.text(value), !svg.isEmpty else { return nil }
            return image(mime, Data(svg.utf8).base64EncodedString(), metadata)

        case "image/png", "image/jpeg", "image/gif":
            guard let data = base64(value), !data.isEmpty else { return nil }
            return image(mime, data, metadata)

        case "text/markdown", "text/latex":
            guard let text = Notebook.text(value) else { return nil }
            return fragment(markdown(text), mode: "light", page: &page)

        case "application/json":
            let text: String
            if let string = Notebook.text(value) {
                text = string
            } else if let data = try? JSONSerialization.data(withJSONObject: value,
                                                             options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
                text = String(decoding: data, as: UTF8.self)
            } else {
                return nil
            }
            page.highlight = true
            return "<pre><code class=\"language-json\">\(HTML.escape(text))</code></pre>"

        case "text/plain":
            guard let text = Notebook.text(value) else { return nil }
            return "<pre>\(ANSI.html(text))</pre>"

        default:
            return nil
        }
    }

    private static func image(_ mime: String, _ base64: String, _ metadata: [String: Any]) -> String {
        var size = ""
        if let info = metadata[mime] as? [String: Any] {
            for key in ["width", "height"] {
                if let number = info[key] as? NSNumber, number.intValue > 0 { size += " \(key)=\"\(number.intValue)\"" }
            }
        }
        return "<img src=\"data:\(mime);base64,\(base64)\"\(size) alt=\"\">"
    }

    /// Base64 text with everything outside the base64 alphabet removed (notebooks wrap long
    /// payloads over lines), so the value is safe inside a quoted attribute.
    private static func base64(_ value: Any?) -> String? {
        guard let text = Notebook.text(value) else { return nil }
        func allowed(_ byte: UInt8) -> Bool {
            (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57)
                || byte == 43 || byte == 47 || byte == 61
        }
        if text.utf8.allSatisfy(allowed) { return text }
        return String(decoding: text.utf8.filter(allowed), as: UTF8.self)
    }

    private static let scriptOrStyle = try! NSRegularExpression(
        pattern: #"<(script|style)\b[^>]*>.*?(</\1\s*>|\z)"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let visibleElement = try! NSRegularExpression(
        pattern: #"<(img|table|svg|video|audio|canvas|math)\b"#, options: [.caseInsensitive])
    private static let anyTag = try! NSRegularExpression(pattern: #"<[^>]*>"#)

    /// True for HTML that shows nothing unless its scripts run (Plotly, Bokeh, widgets):
    /// no text and no image, table or drawing once `<script>` and `<style>` are removed.
    /// Scripts never run in a preview, so such an output falls back to its image or text form.
    static func isScriptShell(_ html: String) -> Bool {
        func strip(_ regex: NSRegularExpression, _ text: String) -> String {
            regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        let content = strip(scriptOrStyle, html)
        if visibleElement.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            return false
        }
        return strip(anyTag, content).allSatisfy { $0.isWhitespace }
    }
}
