import XCTest
@testable import MDBuddyCore

/// Repository-level `examples/` folder, shared with the docs and screenshots.
let examplesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("examples")

final class MarkdownRendererTests: XCTestCase {
    func testInlineStyles() {
        let html = MarkdownRenderer.render("**b** *i* ~~s~~ `c` <sub>x</sub>")
        XCTAssertTrue(html.contains("<strong>b</strong>"))
        XCTAssertTrue(html.contains("<em>i</em>"))
        XCTAssertTrue(html.contains("<del>s</del>"))
        XCTAssertTrue(html.contains("<code>c</code>"))
        XCTAssertTrue(html.contains("<sub>x</sub>"))
    }

    func testGFMTableWithAlignment() {
        let html = MarkdownRenderer.render("| a | b |\n|:--|--:|\n| 1 | 2 |\n")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th align=\"left\">a</th>"))
        XCTAssertTrue(html.contains("<td align=\"right\">2</td>"))
    }

    func testTaskListAndAutolink() {
        let html = MarkdownRenderer.render("- [x] done\n- [ ] todo\n\nsee https://example.com\n")
        XCTAssertTrue(html.contains("type=\"checkbox\" checked=\"\" disabled=\"\""))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">https://example.com</a>"))
    }

    func testFootnotes() {
        let html = MarkdownRenderer.render("Text[^n]\n\n[^n]: The note.\n")
        XCTAssertTrue(html.contains("class=\"footnotes\""))
        XCTAssertTrue(html.contains("The note."))
    }

    func testFencedCodeKeepsLanguageClass() {
        let html = MarkdownRenderer.render("```python\nprint('<hi>')\n```\n")
        XCTAssertTrue(html.contains("<pre><code class=\"language-python\">print('&lt;hi&gt;')"))
    }

    func testRawHTMLKeptButDangerousTagsFiltered() {
        let html = MarkdownRenderer.render("<details><summary>s</summary>\n\nx\n\n</details>\n\n<script>alert(1)</script>\n")
        XCTAssertTrue(html.contains("<details><summary>s</summary>"))
        XCTAssertFalse(html.contains("<script>"), html)
        XCTAssertTrue(html.contains("&lt;script>"), html)
    }

    func testYAMLFrontMatterIsCollapsedCodeBlock() {
        let html = MarkdownRenderer.render("---\ntitle: Hi\n---\n# Body\n")
        XCTAssertTrue(html.hasPrefix("<details class=\"front-matter\">"))
        XCTAssertTrue(html.contains("<code class=\"language-yaml\">title: Hi</code>"))
        XCTAssertTrue(html.contains("<h1>Body</h1>"))
        XCTAssertFalse(html.contains("<hr"))
    }

    func testFrontMatterWithCRLFLineEndings() {
        let html = MarkdownRenderer.render("---\r\ntitle: Hi\r\n---\r\n# Body\r\n")
        XCTAssertTrue(html.contains("language-yaml\">title: Hi</code>"), html)
        XCTAssertTrue(html.contains("<h1>Body</h1>"))
    }

    func testTOMLFrontMatter() {
        let (block, body) = FrontMatter.split("+++\ntitle = \"x\"\n+++\ntext")
        XCTAssertEqual(block, FrontMatter.Block(text: "title = \"x\"", language: "toml"))
        XCTAssertEqual(body, "text")
    }

    func testThematicBreakIsNotFrontMatter() {
        let (block, body) = FrontMatter.split("---\n---\nhello")
        XCTAssertNil(block)
        XCTAssertEqual(body, "---\n---\nhello")
        let (unclosed, _) = FrontMatter.split("---\nnot closed\n")
        XCTAssertNil(unclosed)
    }

    func testShowcaseRendersEveryFeature() throws {
        let data = try Data(contentsOf: examplesDir.appendingPathComponent("showcase.md"))
        let doc = PreviewDocument(fileName: "showcase.md", data: data)
        XCTAssertEqual(doc.kind, .markdown)
        for needle in ["<table>", "<del>strikethrough</del>", "language-python", "<img src=\"images/landscape.png\"",
                       "class=\"footnotes\"", "<kbd>Space</kbd>", "front-matter", "hljs", "<mark>highlight</mark>"] {
            XCTAssertTrue(doc.html.contains(needle), "missing \(needle)")
        }
        XCTAssertFalse(doc.html.contains("<script>document.body"), "raw <script> must be filtered")
    }
}

final class DocumentKindTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(DocumentKind.detect(fileName: "README.md"), .markdown)
        XCTAssertEqual(DocumentKind.detect(fileName: "paper.QMD"), .markdown)
        XCTAssertEqual(DocumentKind.detect(fileName: "a.py"), .code(language: "python"))
        XCTAssertEqual(DocumentKind.detect(fileName: "App.tsx"), .code(language: "typescript"))
        XCTAssertEqual(DocumentKind.detect(fileName: "fit.m"), .code(language: "objectivec"))
        XCTAssertEqual(DocumentKind.detect(fileName: "model.jl"), .code(language: "julia"))
        XCTAssertEqual(DocumentKind.detect(fileName: "Makefile"), .code(language: "makefile"))
        XCTAssertEqual(DocumentKind.detect(fileName: "Dockerfile"), .code(language: "dockerfile"))
        XCTAssertEqual(DocumentKind.detect(fileName: "CMakeLists.txt"), .code(language: "cmake"))
        XCTAssertEqual(DocumentKind.detect(fileName: ".zshrc"), .code(language: "bash"))
        XCTAssertEqual(DocumentKind.detect(fileName: ".gitignore"), .code(language: "plaintext"))
        XCTAssertEqual(DocumentKind.detect(fileName: "notes.txt"), .plainText)
        XCTAssertEqual(DocumentKind.detect(fileName: "LICENSE"), .plainText)
        XCTAssertEqual(DocumentKind.detect(fileName: "thing.weird"), .code(language: nil))
    }
}

final class TextDecodingTests: XCTestCase {
    func testUTF8() {
        XCTAssertEqual(TextDecoding.decode(Data("héllo ✓".utf8)), "héllo ✓")
    }

    func testUTF8BOMIsStripped() {
        XCTAssertEqual(TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)), "hi")
    }

    func testUTF16WithBOM() {
        let data = "héllo".data(using: .utf16)!  // Foundation writes a BOM
        XCTAssertEqual(TextDecoding.decode(data), "héllo")
    }

    func testLatin1Fallback() {
        let data = "café résumé".data(using: .isoLatin1)!
        XCTAssertEqual(TextDecoding.decode(data), "café résumé")
    }

    func testBinaryIsRejected() {
        XCTAssertNil(TextDecoding.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0xFF, 0xD8])))
    }

    func testTruncationNeverSplitsACharacter() {
        let data = Data("aé✓".utf8)  // a(1) é(2) ✓(3) = 6 bytes
        for cut in 0...6 {
            let prefix = PreviewDocument.utf8SafePrefix(data, cut)
            XCTAssertNotNil(String(data: prefix, encoding: .utf8), "cut at \(cut)")
        }
        XCTAssertEqual(PreviewDocument.utf8SafePrefix(data, 2).count, 1)
        XCTAssertEqual(PreviewDocument.utf8SafePrefix(data, 5).count, 3)
    }
}

final class PreviewDocumentTests: XCTestCase {
    func testCodeViewLineNumbers() {
        let html = CodeView.render("a\nb\nc\n", language: "python")
        XCTAssertTrue(html.contains("<pre class=\"gutter\" aria-hidden=\"true\">1\n2\n3\n</pre>"))
        XCTAssertTrue(html.contains("<code class=\"language-python\" data-language=\"python\">a\nb\nc\n</code>"))
    }

    func testCodeFileIncludesHighlighterAndEscapes() throws {
        let data = try Data(contentsOf: examplesDir.appendingPathComponent("code/server.ts"))
        let doc = PreviewDocument(fileName: "server.ts", data: data)
        XCTAssertEqual(doc.kind, .code(language: "typescript"))
        XCTAssertTrue(doc.html.contains("Highlight.js v11"))
        XCTAssertTrue(doc.html.contains("IncomingMessage, ServerResponse"))
        XCTAssertTrue(doc.html.contains("&quot;GET&quot; | &quot;POST&quot;"))
    }

    func testPlainTextHasNoScriptOrHighlighter() {
        let doc = PreviewDocument(fileName: "notes.txt", data: Data("<b>not bold</b>".utf8))
        XCTAssertTrue(doc.html.contains("<pre class=\"plaintext\">&lt;b&gt;not bold&lt;/b&gt;</pre>"))
        XCTAssertFalse(doc.html.contains("<script"))
    }

    func testMarkdownWithoutCodeSkipsHighlighter() {
        let doc = PreviewDocument(fileName: "a.md", data: Data("# Hi".utf8))
        XCTAssertFalse(doc.html.contains("Highlight.js"))
        XCTAssertTrue(doc.html.contains("addHeadingAnchors"))
    }

    func testLargeCodeIsNotHighlighted() {
        let big = Data(String(repeating: "x = 1\n", count: PreviewDocument.maxHighlightBytes / 6 + 10).utf8)
        let doc = PreviewDocument(fileName: "big.py", data: big)
        XCTAssertTrue(doc.html.contains("class=\"nohighlight\""))
        XCTAssertFalse(doc.html.contains("Highlight.js"))
    }

    func testHugeFileIsTruncatedWithNotice() {
        let huge = Data(repeating: UInt8(ascii: "a"), count: PreviewDocument.maxBytes + 100)
        let doc = PreviewDocument(fileName: "huge.txt", data: huge)
        XCTAssertTrue(doc.html.contains("class=\"mdb-notice\""))
        XCTAssertLessThan(doc.html.utf8.count, PreviewDocument.maxBytes + 64 * 1024)
    }

    func testBinaryFileShowsNotice() {
        let doc = PreviewDocument(fileName: "x.txt", data: Data([0xFF, 0x00, 0xFE, 0x00, 0x01]))
        XCTAssertTrue(doc.html.contains("does not appear to contain text"))
    }

    func testPageHasCSPAndNonceMatchesScript() throws {
        let html = PreviewDocument(fileName: "a.md", data: Data("# Hi".utf8)).html
        let nonce = try XCTUnwrap(html.range(of: "'nonce-").map { html[$0.upperBound...].prefix(32) })
        XCTAssertTrue(html.contains("<script nonce=\"\(nonce)\">"))
        XCTAssertTrue(html.contains("default-src 'none'"))
    }

    func testBundledResourcesLoad() {
        XCTAssertFalse(Resources.stylesheet.contains("missing resource"))
        XCTAssertFalse(Resources.highlighter.contains("missing resource"))
        XCTAssertFalse(Resources.appJS.contains("missing resource"))
        XCTAssertTrue(Resources.highlighter.contains("grammar compiled for Highlight.js"))
    }

    func testRenderingIsFast() throws {
        // ~1.3 MB of realistic Markdown should render well under a second.
        let showcase = try String(contentsOf: examplesDir.appendingPathComponent("showcase.md"), encoding: .utf8)
        let big = String(repeating: showcase, count: 400)
        let start = Date()
        _ = PreviewDocument(fileName: "big.md", data: Data(big.utf8))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "render took \(elapsed)s")
    }
}
