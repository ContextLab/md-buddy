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

    func testUnclosedCodeSpanAndEscapes() {
        XCTAssertEqual(spans("a ` lone tick and $x$"), [MathSpan(tex: "x", display: false)])
        XCTAssertEqual(spans("$a\\$b$"), [MathSpan(tex: "a\\$b", display: false)])
    }
}
