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
