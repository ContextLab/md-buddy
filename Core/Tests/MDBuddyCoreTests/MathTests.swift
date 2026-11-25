import XCTest
@testable import MDBuddyCore

final class MathScannerTests: XCTestCase {
    private func spans(_ md: String, bare: Bool = false) -> [MathSpan] {
        MathScanner.protect(md, bareEnvironments: bare).spans
    }

    func testInlineAndDisplay() {
        XCTAssertEqual(spans("Euler: $e^{i\\pi}+1=0$ and\n\n$$\n\\int_0^1 x\\,dx\n$$"),
                       [MathSpan(tex: "e^{i\\pi}+1=0", display: false),
                        MathSpan(tex: "\n\\int_0^1 x\\,dx\n", display: true)])
    }

    func testParenAndBracketDelimiters() {
        XCTAssertEqual(spans("\\(a\\) then \\[b\\]"),
                       [MathSpan(tex: "a", display: false), MathSpan(tex: "b", display: true)])
    }

    func testCurrencyIsNotMath() {
        XCTAssertEqual(spans("costs $5 and $10 today"), [])
        XCTAssertEqual(spans("a $ b $ c"), [])
        XCTAssertEqual(spans("price is \\$5 or $x$"), [MathSpan(tex: "x", display: false)])
    }

    func testCodeIsNotMath() {
        XCTAssertEqual(spans("`$a$` and ``x `$b$` y``"), [])
        XCTAssertEqual(spans("```sh\necho $HOME $PATH\n```\n\n~~~\n$c$\n~~~\n\n    $d$ indented"), [])
    }

    func testUnderscoresSurviveCmark() {
        let html = MarkdownRenderer.render("$a_i + b_i$ and $c_j * d_j * e$")
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">a_i + b_i</span>"), html)
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">c_j * d_j * e</span>"), html)
        XCTAssertFalse(html.contains("<em>"), html)
    }

    func testTexIsEscaped() {
        let html = MarkdownRenderer.render("$a < b & c$")
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">a &lt; b &amp; c</span>"), html)
    }

    func testBareEnvironmentOnlyWhenAsked() {
        let md = "Text\n\n\\begin{align}\na &= b \\\\\nc &= d\n\\end{align}\n"
        XCTAssertEqual(spans(md), [])
        XCTAssertEqual(spans(md, bare: true),
                       [MathSpan(tex: "\\begin{align}\na &= b \\\\\nc &= d\n\\end{align}", display: true)])
    }

    func testNoMathMeansNoMathMarkup() {
        XCTAssertFalse(MarkdownRenderer.render("# Plain\n\nNo math, $5 only.").contains("class=\"math "))
    }

    func testPlaceholderLikeTextIsUntouched() {
        let html = MarkdownRenderer.render("MDBMATH0X and $x$")
        XCTAssertTrue(html.contains("MDBMATH0X"), html)
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">x</span>"), html)
    }

    func testFrontMatterIsNotScanned() {
        XCTAssertFalse(MarkdownRenderer.render("---\nprice: $x$\n---\n\nBody").contains("class=\"math "))
    }

    func testDisplayMathInsideParagraphAndList() {
        let html = MarkdownRenderer.render("- item with $x_1$\n    - nested $y_2$\n\nBefore $$a_1 = b_1$$ after.")
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">x_1</span>"), html)
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">y_2</span>"), html)
        XCTAssertTrue(html.contains("<span class=\"math math-display\">a_1 = b_1</span>"), html)
    }

    func testMathDoesNotCrossParagraphs() {
        XCTAssertEqual(spans("open $x and\n\nclose y$ here"), [])
        XCTAssertEqual(spans("$$a\n\nb$$"), [])
    }

    func testCodeSpanIsNeverInsideInlineMath() {
        XCTAssertEqual(spans("Money: $5 and $10. Code: `$x$`."), [])
        XCTAssertEqual(spans("$a$ then `$b` and $c$"),
                       [MathSpan(tex: "a", display: false), MathSpan(tex: "c", display: false)])
    }

    /// Openers that never close must not make the scan quadratic: each failed search is
    /// remembered up to the end of its paragraph.
    func testUnclosedDelimitersScanInLinearTime() {
        for unit in ["$a ", "\\(a ", "\\begin{a} ", "`a ``b "] {
            let text = String(repeating: unit, count: 400_000 / unit.count)
            let start = Date()
            XCTAssertEqual(MathScanner.protect(text, bareEnvironments: true).spans, [], unit)
            XCTAssertLessThan(Date().timeIntervalSince(start), 3.0, "slow on repeated \(unit)")
        }
    }

    func testUnclosedCodeSpanAndEscapes() {
        XCTAssertEqual(spans("a ` lone tick and $x$"), [MathSpan(tex: "x", display: false)])
        XCTAssertEqual(spans("$a\\$b$"), [MathSpan(tex: "a\\$b", display: false)])
    }
}

final class MathPageTests: XCTestCase {
    func testMathPageIncludesKaTeXAndOthersDoNot() {
        let math = PreviewDocument(fileName: "m.md", data: Data("$x^2$".utf8)).html
                // "/* KaTeX " opens both vendored files; "KaTeX_Main" is a font only its stylesheet names.
        // (The page's own script and stylesheet mention "katex" on every page.)
        XCTAssertEqual(math.components(separatedBy: "/* KaTeX ").count - 1, 2)
        XCTAssertTrue(math.contains("data:font/woff2;base64,"))
        let plain = PreviewDocument(fileName: "p.md", data: Data("costs $5 and $10".utf8)).html
        let code = PreviewDocument(fileName: "a.py", data: Data("x = '$y$'".utf8)).html
        for page in [plain, code] {
            XCTAssertFalse(page.contains("/* KaTeX "))
            XCTAssertFalse(page.contains("KaTeX_Main"))
            XCTAssertFalse(page.contains("data:font/woff2"))
            XCTAssertLessThan(page.utf8.count, 250_000)
        }
    }

    func testKaTeXFontsAreInlinedCompletely() {
        XCTAssertFalse(Resources.mathStylesheet.contains("url(fonts/"))
        XCTAssertGreaterThan(Resources.mathScript.count, 100_000)
    }

    func testCSPIsTheSameWithMath() throws {
        func csp(_ html: String) throws -> String {
            let line = try XCTUnwrap(html.split(separator: "\n").first { $0.contains("Content-Security-Policy") })
            return line.replacingOccurrences(of: "nonce-[0-9A-F]+", with: "nonce-N", options: .regularExpression)
        }
        let math = PreviewDocument(fileName: "m.md", data: Data("$x^2$".utf8)).html
        let plain = PreviewDocument(fileName: "p.md", data: Data("text".utf8)).html
        XCTAssertEqual(try csp(math), try csp(plain))
    }
}

/// Math typeset by the bundled KaTeX in a real WKWebView.
@MainActor
final class MathWebKitTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mdbuddy-math-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func render(_ markdown: String) async throws -> WebPageRenderer {
        let file = scratch.appendingPathComponent("doc.md")
        try Data(markdown.utf8).write(to: file)
        let renderer = WebPageRenderer()
        _ = try await renderer.load(fileURL: file)
        return renderer
    }

    private func string(_ renderer: WebPageRenderer, _ js: String) async throws -> String {
        try await renderer.evaluate(js) as? String ?? "<non-string>"
    }

    func testMathIsTypeset() async throws {
        let page = try await render("Inline $a_i^2$ and\n\n$$\\frac{1}{2}$$\n\nMoney: $5 and $10. Code: `$x$`.")
        let typeset = try await string(page, "String(document.querySelectorAll('.math .katex').length)")
        XCTAssertEqual(typeset, "2")
        let display = try await string(page, "String(document.querySelectorAll('.math-display .katex-display').length)")
        XCTAssertEqual(display, "1")
        let fractions = try await string(page, "String(document.querySelectorAll('.mfrac').length)")
        XCTAssertEqual(fractions, "1")
        let code = try await string(page, "document.querySelector('code').textContent")
        XCTAssertEqual(code, "$x$")
        let text = try await string(page, "document.body.innerText")
        XCTAssertTrue(text.contains("$5 and $10"), text)
    }

    func testMathUsesKaTeXFonts() async throws {
        let page = try await render("$x$")
        _ = try await page.evaluateAsync("await document.fonts.ready; return 1")
        let family = try await string(page, "getComputedStyle(document.querySelector('.katex')).fontFamily")
        XCTAssertTrue(family.contains("KaTeX_Main"), family)
        let loaded = try await string(page, "String(document.fonts.check('16px KaTeX_Main'))")
        XCTAssertEqual(loaded, "true")
    }

    func testBadTeXShowsSourceNotBlank() async throws {
        let page = try await render("$\\frac{1$ after")
        let math = try await string(page, "document.querySelector('.math').textContent")
        XCTAssertTrue(math.contains("\\frac{1"), math)
        let text = try await string(page, "document.body.innerText")
        XCTAssertTrue(text.contains("after"), text)
    }

    /// A numbered equation's tag sits at the right edge; it must not push the block wider
    /// than the page and summon a scroll bar.
    func testNumberedEquationFitsWithoutScrolling() async throws {
        let page = try await render("$$\n\\begin{align}\ny_i &= \\beta_0 + \\beta_1 x_i \\\\\ne_i &\\sim \\mathcal{N}(0, \\sigma^2)\n\\end{align}\n$$")
                let numbers = try await string(page, "String(document.querySelectorAll('.math-display .eqn-num').length)")
        XCTAssertEqual(numbers, "2")
        let overflow = try await string(page, "(() => { const e = document.querySelector('.math-display'); return String(e.scrollWidth - e.clientWidth); })()")
        XCTAssertEqual(overflow, "0")
    }

    func testHeadingWithMathStillGetsAnAnchor() async throws {
        let page = try await render("# Energy $E = mc^2$\n\ntext")
        let id = try await string(page, "document.querySelector('h1').id")
        XCTAssertTrue(id.hasPrefix("energy"), id)
        let typeset = try await string(page, "String(document.querySelectorAll('h1 .katex').length)")
        XCTAssertEqual(typeset, "1")
    }
}
