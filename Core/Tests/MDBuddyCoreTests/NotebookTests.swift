import XCTest
@testable import MDBuddyCore

/// A 1×1 transparent PNG.
let tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

final class NotebookModelTests: XCTestCase {
    private func parse(_ json: String) -> Notebook? { Notebook.parse(Data(json.utf8)) }

    func testV4CellsAndLanguage() throws {
        let notebook = try XCTUnwrap(parse("""
        {"nbformat": 4, "nbformat_minor": 5,
         "metadata": {"language_info": {"name": "Julia"}, "kernelspec": {"language": "python"}},
         "cells": [
           {"cell_type": "markdown", "metadata": {}, "source": ["# Title\\n", "text"],
            "attachments": {"p.png": {"image/png": "AAAA"}}},
           {"cell_type": "code", "metadata": {}, "execution_count": 3, "source": ["x = 1\\n", "x"],
            "outputs": [
              {"output_type": "stream", "name": "stderr", "text": ["warn\\n"]},
              {"output_type": "execute_result", "execution_count": 3, "metadata": {"a": 1},
               "data": {"text/plain": ["1"]}},
              {"output_type": "display_data", "metadata": {}, "data": {"image/png": "AAAA"}},
              {"output_type": "error", "ename": "ValueError", "evalue": "bad", "traceback": ["line1", "line2"]}
            ]},
           {"cell_type": "raw", "metadata": {}, "source": "raw text"}
         ]}
        """))
        XCTAssertEqual(notebook.language, "julia")
        XCTAssertEqual(notebook.cells.count, 3)

        guard case let .markdown(source, attachments) = notebook.cells[0] else { return XCTFail("not markdown") }
        XCTAssertEqual(source, "# Title\ntext")
        XCTAssertEqual(attachments, ["p.png": ["image/png": "AAAA"]])

        guard case let .code(code, count, outputs) = notebook.cells[1] else { return XCTFail("not code") }
        XCTAssertEqual(code, "x = 1\nx")
        XCTAssertEqual(count, 3)
        XCTAssertEqual(outputs.count, 4)
        guard case let .stream(name, text) = outputs[0] else { return XCTFail("not stream") }
        XCTAssertEqual(name, "stderr")
        XCTAssertEqual(text, "warn\n")
        guard case let .data(bundle, metadata, resultCount) = outputs[1] else { return XCTFail("not data") }
        XCTAssertEqual(Notebook.text(bundle["text/plain"]), "1")
        XCTAssertEqual(metadata["a"] as? Int, 1)
        XCTAssertEqual(resultCount, 3)
        guard case let .data(display, _, displayCount) = outputs[2] else { return XCTFail("not data") }
        XCTAssertEqual(display["image/png"] as? String, "AAAA")
        XCTAssertNil(displayCount)
        guard case let .error(ename, evalue, traceback) = outputs[3] else { return XCTFail("not error") }
        XCTAssertEqual(ename, "ValueError")
        XCTAssertEqual(evalue, "bad")
        XCTAssertEqual(traceback, ["line1", "line2"])

        guard case let .raw(raw) = notebook.cells[2] else { return XCTFail("not raw") }
        XCTAssertEqual(raw, "raw text")
    }

    func testSourceAsStringOrList() throws {
        func source(_ json: String) throws -> String {
            let notebook = try XCTUnwrap(parse("{\"nbformat\": 4, \"cells\": [{\"cell_type\": \"code\", \"source\": \(json)}]}"))
            guard case let .code(source, _, _) = notebook.cells[0] else { XCTFail("not code"); return "" }
            return source
        }
        XCTAssertEqual(try source("\"a = 1\\nb = 2\""), "a = 1\nb = 2")
        XCTAssertEqual(try source("[\"a = 1\\n\", \"b = 2\"]"), "a = 1\nb = 2")
    }

    func testMissingKeysAndUnknownCellType() throws {
        let notebook = try XCTUnwrap(parse("""
        {"cells": [{"cell_type": "weird"}, {"cell_type": "code"}, {"cell_type": "markdown"}, {}, 7]}
        """))
        XCTAssertEqual(notebook.language, "python")
        XCTAssertEqual(notebook.cells.count, 4)
        guard case let .raw(raw) = notebook.cells[0] else { return XCTFail("unknown type should be raw") }
        XCTAssertEqual(raw, "")
        guard case let .code(source, count, outputs) = notebook.cells[1] else { return XCTFail("not code") }
        XCTAssertEqual(source, "")
        XCTAssertNil(count)
        XCTAssertTrue(outputs.isEmpty)
        guard case let .markdown(text, attachments) = notebook.cells[2] else { return XCTFail("not markdown") }
        XCTAssertEqual(text, "")
        XCTAssertTrue(attachments.isEmpty)
        guard case .raw = notebook.cells[3] else { return XCTFail("cell without a type should be raw") }
    }

    func testMimeValueAsListOfLines() {
        XCTAssertEqual(Notebook.text(["a\n", "b"]), "a\nb")
        XCTAssertEqual(Notebook.text("plain"), "plain")
        XCTAssertNil(Notebook.text(["k": 1]))
        XCTAssertNil(Notebook.text(nil))
    }

    func testV3Worksheets() throws {
        let notebook = try XCTUnwrap(parse("""
        {"nbformat": 3, "metadata": {"name": "old"},
         "worksheets": [{"cells": [
           {"cell_type": "heading", "level": 2, "source": ["Old title"]},
           {"cell_type": "markdown", "source": "text"},
           {"cell_type": "code", "language": "python", "prompt_number": 5, "input": ["print 1\\n", "2"],
            "outputs": [
              {"output_type": "stream", "stream": "stdout", "text": ["1\\n"]},
              {"output_type": "pyout", "prompt_number": 5, "text": ["2"], "html": ["<b>2</b>"], "png": "AAAA"},
              {"output_type": "display_data", "svg": ["<svg/>"], "latex": "$x$", "jpeg": "BBBB", "json": "{}"},
              {"output_type": "pyerr", "ename": "NameError", "evalue": "nope", "traceback": ["tb"]}
            ]}
         ]}]}
        """))
        XCTAssertEqual(notebook.cells.count, 3)
        guard case let .markdown(heading, _) = notebook.cells[0] else { return XCTFail("heading not markdown") }
        XCTAssertEqual(heading, "## Old title")
        guard case let .code(source, count, outputs) = notebook.cells[2] else { return XCTFail("not code") }
        XCTAssertEqual(source, "print 1\n2")
        XCTAssertEqual(count, 5)
        guard case let .stream(name, text) = outputs[0] else { return XCTFail("not stream") }
        XCTAssertEqual(name, "stdout")
        XCTAssertEqual(text, "1\n")
        guard case let .data(result, _, resultCount) = outputs[1] else { return XCTFail("pyout not data") }
        XCTAssertEqual(Set(result.keys), ["text/plain", "text/html", "image/png"])
        XCTAssertEqual(resultCount, 5)
        guard case let .data(display, _, _) = outputs[2] else { return XCTFail("not data") }
        XCTAssertEqual(Set(display.keys), ["image/svg+xml", "text/latex", "image/jpeg", "application/json"])
        guard case let .error(ename, _, traceback) = outputs[3] else { return XCTFail("pyerr not error") }
        XCTAssertEqual(ename, "NameError")
        XCTAssertEqual(traceback, ["tb"])
    }

    func testNotANotebook() {
        XCTAssertNil(parse("[]"))
        XCTAssertNil(parse("{\"a\": 1}"))
        XCTAssertNil(parse("{\"cells\": ["))
        XCTAssertNil(parse("{\"cells\": 5}"))
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("not json at all"))
    }

    func testKernelspecFallbackAndDefault() throws {
        func language(_ metadata: String) throws -> String {
            try XCTUnwrap(parse("{\"cells\": [], \"metadata\": \(metadata)}")).language
        }
        XCTAssertEqual(try language("{\"kernelspec\": {\"language\": \"R\"}}"), "r")
        XCTAssertEqual(try language("{\"kernelspec\": {\"name\": \"ir\", \"language\": \"ir\"}}"), "r")
        XCTAssertEqual(try language("{\"language_info\": {\"name\": \"ipython\"}}"), "python")
        XCTAssertEqual(try language("{}"), "python")
        XCTAssertEqual(try language("{\"language_info\": {\"name\": 7}}"), "python")
        XCTAssertEqual(try language("{\"language_info\": {\"name\": \"<script>\"}}"), "python")
    }
}

// MARK: - Building real notebook files for tests

func notebookData(_ cells: [[String: Any]], metadata: [String: Any] = [:]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["nbformat": 4, "nbformat_minor": 5, "metadata": metadata, "cells": cells])
}

func markdownCell(_ source: String, attachments: [String: Any]? = nil) -> [String: Any] {
    var cell: [String: Any] = ["cell_type": "markdown", "metadata": [String: Any](), "source": source]
    if let attachments { cell["attachments"] = attachments }
    return cell
}

func codeCell(_ source: String, count: Int? = nil, outputs: [[String: Any]] = []) -> [String: Any] {
    ["cell_type": "code", "metadata": [String: Any](), "source": source,
     "execution_count": count.map { $0 as Any } ?? NSNull(), "outputs": outputs]
}

func dataOutput(_ bundle: [String: Any], metadata: [String: Any] = [:], result: Int? = nil) -> [String: Any] {
    var output: [String: Any] = ["output_type": result == nil ? "display_data" : "execute_result",
                                 "data": bundle, "metadata": metadata]
    if let result { output["execution_count"] = result }
    return output
}

func streamOutput(_ text: String, name: String = "stdout") -> [String: Any] {
    ["output_type": "stream", "name": name, "text": text]
}

/// The page's `<body>` without the page script, so assertions see only the document.
func pageBody(_ html: String) -> String {
    guard let start = html.range(of: "<body") else { return html }
    let end = html.range(of: "<script nonce", range: start.lowerBound..<html.endIndex)?.lowerBound ?? html.endIndex
    return String(html[start.lowerBound..<end])
}

final class NotebookRendererTests: XCTestCase {
    private func document(_ cells: [[String: Any]], metadata: [String: Any] = [:]) -> PreviewDocument {
        PreviewDocument(fileName: "n.ipynb", data: notebookData(cells, metadata: metadata))
    }

    private func body(_ cells: [[String: Any]], metadata: [String: Any] = [:]) -> String {
        pageBody(document(cells, metadata: metadata).html)
    }

    func testDetectionAndKind() {
        XCTAssertEqual(DocumentKind.detect(fileName: "A.IPYNB"), .notebook)
        let doc = document([markdownCell("# Hi")])
        XCTAssertEqual(doc.kind, .notebook)
        XCTAssertTrue(doc.html.contains("<body class=\"notebook\">"))
        XCTAssertTrue(doc.html.contains("<article class=\"markdown-body notebook\">"))
    }

    func testNeverRunNotebook() {
        let html = body([codeCell("a = 1"), codeCell("b = 2")])
        XCTAssertEqual(html.components(separatedBy: "<div class=\"nb-prompt\">[ ]:</div>").count - 1, 2)
        XCTAssertEqual(html.components(separatedBy: "class=\"nb-cell nb-code\"").count - 1, 2)
        XCTAssertFalse(html.contains("class=\"nb-output"))
    }

    func testCodeCellLanguageAndPrompt() {
        let html = body([codeCell("x <- c(1, 2) & TRUE", count: 7)], metadata: ["kernelspec": ["language": "R"]])
        XCTAssertTrue(html.contains("<div class=\"nb-prompt\">[7]:</div>"))
        XCTAssertTrue(html.contains("<pre class=\"nb-source\"><code class=\"language-r\">x &lt;- c(1, 2) &amp; TRUE</code></pre>"), html)
    }

    func testDollarsInCodeAndOutputsAreNotMath() {
        let doc = document([codeCell("cost = \"$x$\"", count: 1, outputs: [
            streamOutput("$a$ $b$\n"),
            ["output_type": "error", "ename": "E", "evalue": "$v$", "traceback": ["Traceback $t$ here"]],
            dataOutput(["text/plain": "$y$"], result: 1),
        ])])
        // The document itself (the page script's comments mention the math markup).
        let html = pageBody(doc.html)
        XCTAssertFalse(html.contains("class=\"math "))
        XCTAssertFalse(html.contains("class=&quot;math "))
        XCTAssertFalse(doc.html.contains("/* KaTeX "))
        XCTAssertTrue(html.contains("<pre>$a$ $b$\n</pre>"), html)
        XCTAssertTrue(html.contains("cost = &quot;$x$&quot;"), html)
        XCTAssertTrue(html.contains("<pre>$y$</pre>"), html)
    }

    func testMarkdownCellMathAndBareEnvironment() {
        let doc = document([markdownCell("Inline $x_1$.\n\n\\begin{align}\na &= b\n\\end{align}\n")])
        let html = pageBody(doc.html)
        XCTAssertTrue(html.contains("<div class=\"nb-fragment\" data-mode=\"light\" hidden>"), html)
        XCTAssertTrue(html.contains("class=&quot;math math-inline&quot;&gt;x_1&lt;/span&gt;"), html)
        XCTAssertTrue(html.contains("class=&quot;math math-display&quot;&gt;\\begin{align}"), html)
        XCTAssertTrue(doc.html.contains("/* KaTeX "))
    }

    func testMarkdownCellIsEscapedIntoItsFragment() {
        let html = body([markdownCell("**bold** <div>open"), codeCell("x")])
        XCTAssertTrue(html.contains("&lt;strong&gt;bold&lt;/strong&gt;"), html)
        XCTAssertFalse(html.contains("<strong>"))
        XCTAssertFalse(html.contains("<div>open"))
    }

    func testAttachmentBecomesDataImage() {
        let html = body([markdownCell("![a](attachment:p.png) and ![b](attachment:my%20plot.png)",
                                      attachments: ["p.png": ["image/png": tinyPNG],
                                                    "my plot.png": ["image/png": tinyPNG]])])
        XCTAssertEqual(html.components(separatedBy: "src=&quot;data:image/png;base64,iVBOR").count - 1, 2, html)
        XCTAssertFalse(html.contains("attachment:"))
    }

    func testAttachmentWithNonImageTypeIsNotInlined() {
        let html = body([markdownCell("![a](attachment:x.html)",
                                      attachments: ["x.html": ["text/html": "PGI+"]])])
        XCTAssertFalse(html.contains("data:text/html"))
    }

    func testMimePriority() {
        let all = body([codeCell("d", count: 1, outputs: [
            dataOutput(["text/html": "<table><tr><td>1</td></tr></table>", "image/png": tinyPNG, "text/plain": "plain!"], result: 1)])])
        XCTAssertTrue(all.contains("<div class=\"nb-fragment\" data-mode=\"shadow\" hidden>&lt;table&gt;"), all)
        XCTAssertFalse(all.contains("<img"))
        XCTAssertFalse(all.contains("plain!"))

        let image = body([codeCell("d", outputs: [dataOutput(["image/png": tinyPNG, "text/plain": "plain!"])])])
        XCTAssertTrue(image.contains("<img src=\"data:image/png;base64,iVBOR"), image)
        XCTAssertFalse(image.contains("plain!"))

        let plain = body([codeCell("d", count: 2, outputs: [dataOutput(["text/plain": "plain <1>"], result: 2)])])
        XCTAssertTrue(plain.contains("<pre>plain &lt;1&gt;</pre>"), plain)
        XCTAssertTrue(plain.contains("class=\"nb-output nb-result\""), plain)
        XCTAssertEqual(plain.components(separatedBy: "<div class=\"nb-prompt\">[2]:</div>").count - 1, 2)
    }

    func testScriptShellFallsBackToImage() {
        let shell = "<div id=\"p\"></div>\n<script type=\"text/javascript\">Plotly.newPlot('p', [])</script>"
        let html = body([codeCell("fig", outputs: [dataOutput(["text/html": shell, "image/png": tinyPNG])])])
        XCTAssertTrue(html.contains("<img src=\"data:image/png;base64,"), html)
        XCTAssertFalse(html.contains("Plotly"))
        XCTAssertFalse(html.contains("data-mode=\"shadow\""))
    }

    func testSVGOutputIsAnImage() {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4\" height=\"4\"><script>window.pwned=1</script><rect width=\"4\" height=\"4\"/></svg>"
        let html = body([codeCell("s", outputs: [dataOutput(["image/svg+xml": svg])])])
        XCTAssertTrue(html.contains("<img src=\"data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())\""), html)
        XCTAssertFalse(html.contains("<svg"))
        XCTAssertFalse(html.contains("pwned"))
    }

    func testImageSizeMetadataAndDirtyBase64() {
        let wrapped = tinyPNG.prefix(20) + "\n" + tinyPNG.dropFirst(20) + "\n"
        let html = body([codeCell("i", outputs: [
            dataOutput(["image/png": String(wrapped)], metadata: ["image/png": ["width": 320, "height": 200]]),
            dataOutput(["image/jpeg": "AAAA\" onerror=\"x"]),
        ])])
        XCTAssertTrue(html.contains("<img src=\"data:image/png;base64,\(tinyPNG)\" width=\"320\" height=\"200\""), html)
        // Quotes and spaces are gone, so the value cannot leave its attribute ("=" is base64 padding).
        XCTAssertTrue(html.contains("<img src=\"data:image/jpeg;base64,AAAAonerror=x\" alt=\"\">"), html)
    }

    func testJSONOutputPrettyPrinted() {
        let html = body([codeCell("j", outputs: [dataOutput(["application/json": ["b": 1, "a": ["x"]]])])])
        XCTAssertTrue(html.contains("<pre><code class=\"language-json\">{\n  &quot;a&quot; : [\n    &quot;x&quot;\n  ],\n  &quot;b&quot; : 1\n}</code></pre>"), html)
    }

    func testMarkdownAndLatexOutputs() {
        let doc = document([codeCell("m", outputs: [
            dataOutput(["text/markdown": "**strong** out", "text/plain": "<Markdown object>"]),
            dataOutput(["text/latex": "$\\displaystyle x^{2}$", "text/plain": "x**2"]),
            dataOutput(["text/latex": "\\begin{equation}a=b\\end{equation}"]),
        ])])
        let html = pageBody(doc.html)
        XCTAssertTrue(html.contains("&lt;strong&gt;strong&lt;/strong&gt; out"), html)
        XCTAssertTrue(html.contains("class=&quot;math math-inline&quot;&gt;\\displaystyle x^{2}&lt;/span&gt;"), html)
        XCTAssertTrue(html.contains("class=&quot;math math-display&quot;&gt;\\begin{equation}a=b\\end{equation}"), html)
        XCTAssertFalse(html.contains("Markdown object"))
        XCTAssertTrue(doc.html.contains("/* KaTeX "))
    }

    func testUnsupportedOutputNote() {
        let html = body([codeCell("w", outputs: [
            dataOutput(["application/vnd.jupyter.widget-view+json": ["model_id": "abc"]]),
            dataOutput([:]),
        ])])
        XCTAssertTrue(html.contains("<div class=\"nb-output nb-unsupported\">Output of type application/vnd.jupyter.widget-view+json can&#39;t be shown in a static preview.</div>"), html)
        XCTAssertEqual(html.components(separatedBy: "nb-unsupported").count - 1, 1)
    }

    func testStreamsAndTraceback() {
        let html = body([codeCell("1/0", count: 4, outputs: [
            streamOutput("out <1>\n"),
            streamOutput("careful\n", name: "stderr"),
            streamOutput("10%\r50%\r100%\n"),
            ["output_type": "error", "ename": "ZeroDivisionError", "evalue": "division by zero",
             "traceback": ["\u{1B}[0;31mZeroDivisionError\u{1B}[0m: division by zero", "second line"]],
            ["output_type": "error", "ename": "KeyError", "evalue": "'k'", "traceback": [String]()],
        ])])
        XCTAssertTrue(html.contains("class=\"nb-output nb-stream nb-stdout\""), html)
        XCTAssertTrue(html.contains("<pre>out &lt;1&gt;\n</pre>"), html)
        XCTAssertTrue(html.contains("class=\"nb-output nb-stream nb-stderr\""), html)
        XCTAssertTrue(html.contains("<pre>100%\n</pre>"), html)
        XCTAssertTrue(html.contains("class=\"nb-output nb-error\""), html)
        XCTAssertTrue(html.contains("<span class=\"ansi-fg-red\">ZeroDivisionError</span>: division by zero\nsecond line"), html)
        XCTAssertTrue(html.contains("KeyError: &#39;k&#39;"), html)
    }

    func testRawCellAndEmptyNotebook() {
        XCTAssertTrue(body([["cell_type": "raw", "source": "<b>raw</b>"]])
            .contains("<section class=\"nb-cell nb-raw\"><pre>&lt;b&gt;raw&lt;/b&gt;</pre></section>"))
        XCTAssertTrue(body([]).contains("This notebook has no cells."))
    }

    func testHugeCodeCellIsNotHighlighted() {
        let big = String(repeating: "x = 1\n", count: PreviewDocument.maxHighlightBytes / 6 + 10)
        let html = body([codeCell(big), codeCell("y = 2")])
        XCTAssertTrue(html.contains("<code class=\"nohighlight\">x = 1"))
        XCTAssertTrue(html.contains("<code class=\"language-python\">y = 2"))
    }

    func testMalformedNotebookFallsBackToJSON() {
        let doc = PreviewDocument(fileName: "n.ipynb", data: Data("{\"cells\": [".utf8))
        XCTAssertEqual(doc.kind, .code(language: "json"))
        XCTAssertTrue(doc.html.contains("class=\"code-view\""))
        XCTAssertTrue(doc.html.contains("{&quot;cells&quot;: ["))
        let notNotebook = PreviewDocument(fileName: "n.ipynb", data: Data("{\"a\": 1}".utf8))
        XCTAssertEqual(notNotebook.kind, .code(language: "json"))
    }

    func testOversizeNotebookNotice() {
        let data = Data(repeating: UInt8(ascii: " "), count: PreviewDocument.maxNotebookBytes + 1)
        let doc = PreviewDocument(fileName: "n.ipynb", data: data)
        XCTAssertTrue(doc.html.contains("too large to preview (limit 50 MB)"), String(doc.html.suffix(300)))
        XCTAssertFalse(pageBody(doc.html).contains("class=\"nb-cell"))
        XCTAssertLessThan(doc.html.utf8.count, 100_000)
    }

    func testBigNotebookIsWholeAndFast() throws {
        // 20 figures of about 1 MB each: a valid PNG header padded with zero bytes.
        var png = try XCTUnwrap(Data(base64Encoded: tinyPNG))
        png.append(Data(count: 750_000))
        let figure = png.base64EncodedString()
        let data = notebookData((1...20).map { codeCell("plot(\($0))", count: $0, outputs: [dataOutput(["image/png": figure])]) })
        XCTAssertGreaterThan(data.count, 20_000_000)

        let start = Date()
        let doc = PreviewDocument(fileName: "big.ipynb", data: data)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(doc.html.components(separatedBy: "<img src=\"data:image/png;base64,").count - 1, 20)
        XCTAssertFalse(doc.html.contains("Showing the first"))
        XCTAssertTrue(doc.html.hasSuffix("</body>\n</html>\n"))
        XCTAssertLessThan(elapsed, 2.0)
    }

    func testCSPUnchangedForNotebook() throws {
        func csp(_ html: String) throws -> String {
            let line = try XCTUnwrap(html.split(separator: "\n").first { $0.contains("Content-Security-Policy") })
            return line.replacingOccurrences(of: "nonce-[0-9A-F]+", with: "nonce-N", options: .regularExpression)
        }
        let notebook = document([markdownCell("$x$"), codeCell("y", outputs: [dataOutput(["text/html": "<b>h</b>"])])]).html
        let markdown = PreviewDocument(fileName: "p.md", data: Data("text".utf8)).html
        XCTAssertEqual(try csp(notebook), try csp(markdown))
    }
}

final class ANSITests: XCTestCase {
    private let esc = "\u{1B}"

    func testPlainTextIsEscaped() {
        XCTAssertEqual(ANSI.html("<b> & \"q\""), "&lt;b&gt; &amp; &quot;q&quot;")
    }

    func testColorsBoldAndReset() {
        XCTAssertEqual(ANSI.html("a\(esc)[31mb\(esc)[0mc"), "a<span class=\"ansi-fg-red\">b</span>c")
        XCTAssertEqual(ANSI.html("\(esc)[1;92mok\(esc)[0m"), "<span class=\"ansi-bold ansi-fg-bright-green\">ok</span>")
        XCTAssertEqual(ANSI.html("\(esc)[41mX\(esc)[49mY"), "<span class=\"ansi-bg-red\">X</span>Y")
        XCTAssertEqual(ANSI.html("\(esc)[1m\(esc)[34mB\(esc)[22mC\(esc)[39mD"),
                       "<span class=\"ansi-bold ansi-fg-blue\">B</span><span class=\"ansi-fg-blue\">C</span>D")
        XCTAssertEqual(ANSI.html("\(esc)[mplain"), "plain")
    }

    func testExtendedColors() {
        XCTAssertEqual(ANSI.html("\(esc)[38;5;196mr"), "<span style=\"color:#ff0000\">r</span>")
        XCTAssertEqual(ANSI.html("\(esc)[38;5;2mg"), "<span class=\"ansi-fg-green\">g</span>")
        XCTAssertEqual(ANSI.html("\(esc)[38;5;244mg"), "<span style=\"color:#808080\">g</span>")
        XCTAssertEqual(ANSI.html("\(esc)[38;2;1;2;3mt"), "<span style=\"color:#010203\">t</span>")
        XCTAssertEqual(ANSI.html("\(esc)[48;2;255;0;16mt"), "<span style=\"background-color:#ff0010\">t</span>")
    }

    func testOtherEscapesAreDropped() {
        XCTAssertEqual(ANSI.html("\(esc)[2Kline\(esc)[1A"), "line")
        XCTAssertEqual(ANSI.html("\(esc)[?25lhidden cursor\(esc)[?25h"), "hidden cursor")
        XCTAssertEqual(ANSI.html("lone \(esc) escape"), "lone  escape")
    }

    func testCarriageReturnsOverwriteTheLine() {
        XCTAssertEqual(ANSI.html("10%\r50%\r100%\nnext\r\nlast"), "100%\nnext\nlast")
    }
}
