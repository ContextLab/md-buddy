import AppKit
import XCTest
@testable import MDBuddyCore

/// Loads real pages in WKWebView (configured like the extension) and checks the page script's work.
@MainActor
final class WebKitTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mdbuddy-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("images"), withIntermediateDirectories: true)
        for name in ["landscape.png", "diagram.svg"] {
            try FileManager.default.copyItem(at: examplesDir.appendingPathComponent("images/\(name)"),
                                            to: scratch.appendingPathComponent("images/\(name)"))
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func render(_ markdown: String, name: String = "doc.md") async throws -> WebPageRenderer {
        let file = scratch.appendingPathComponent(name)
        try Data(markdown.utf8).write(to: file)
        let renderer = WebPageRenderer()
        _ = try await renderer.load(fileURL: file)
        return renderer
    }

    private func string(_ renderer: WebPageRenderer, _ js: String) async throws -> String {
        try await renderer.evaluate(js) as? String ?? "<non-string>"
    }

    func testHeadingAnchorsAreGitHubStyle() async throws {
        let page = try await render("# Hello, World!\n## Hello, World!\n### Über café\n")
        let ids = try await string(page, "Array.from(document.querySelectorAll('h1,h2,h3')).map(h => h.id).join('|')")
        XCTAssertEqual(ids, "hello-world|hello-world-1|über-café")
    }

    func testAlertsAreStyled() async throws {
        let page = try await render("> [!WARNING]\n> Careful **now**.\n")
        let result = try await string(page, """
            (() => { const b = document.querySelector('blockquote');
              return b.className + '|' + b.querySelector('.alert-title').textContent + '|' + b.innerText.includes('[!') })()
            """)
        XCTAssertEqual(result, "alert alert-warning|Warning|false")
    }

    func testCodeBlocksAreHighlighted() async throws {
        let page = try await render("```python\ndef f(x):\n    return x\n```\n\n```nosuchlang\nplain\n```\n")
        let result = try await string(page, """
            Array.from(document.querySelectorAll('pre code')).map(c => c.classList.contains('hljs') + ':' + c.querySelectorAll('span').length).join('|')
            """)
        let parts = result.split(separator: "|")
        XCTAssertEqual(parts.count, 2, result)
        XCTAssertTrue(parts[0].hasPrefix("true:") && parts[0] != "true:0", result)
        XCTAssertEqual(parts[1], "false:0", result)
    }

    func testCodeFileHighlightingWithExtraLanguage() async throws {
        let page = try await render("function y = square(x)\n  y = x.^2; % comment\nend\n", name: "square.matlab")
        let result = try await string(page, "document.querySelector('.source code').className + '|' + document.querySelectorAll('.source code span.hljs-comment').length")
        XCTAssertEqual(result, "language-matlab hljs|1")
    }

    func testLocalImagesLoadAndMissingOnesBecomePlaceholders() async throws {
        let page = try await render("![png](images/landscape.png) ![svg](images/diagram.svg) ![gone](images/missing.png)\n")
        try await Task.sleep(nanoseconds: 300_000_000)
        let loaded = try await string(page, "Array.from(document.images).map(i => i.naturalWidth > 0).join('|')")
        XCTAssertEqual(loaded, "true|true")
        let chip = try await string(page, "document.querySelector('.image-placeholder').textContent")
        XCTAssertEqual(chip, "gone")
    }

    func testEmbeddedScriptsAndEventHandlersNeverRun() async throws {
        let page = try await render("""
            # Safe
            <script>document.title = 'pwned-script'</script>
            <img src="nope.png" onerror="document.title = 'pwned-onerror'">
            <a href="javascript:document.title='pwned-link'">x</a>
            """)
        try await Task.sleep(nanoseconds: 300_000_000)
        let title = try await string(page, "document.title")
        XCTAssertEqual(title, "doc.md")
    }

    func testSnapshotRendersInLightAndDark() async throws {
        let file = scratch.appendingPathComponent("snap.md")
        try Data("# Title\n\nBody text.".utf8).write(to: file)
        var backgrounds: [String] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let renderer = WebPageRenderer(width: 400, height: 300, appearance: appearance)
            _ = try await renderer.load(fileURL: file)
            backgrounds.append(try await renderer.evaluate("getComputedStyle(document.body).backgroundColor") as? String ?? "")
            let image = try await renderer.snapshot(fullHeight: false)
            XCTAssertGreaterThan(image.size.width, 0)
        }
        XCTAssertEqual(backgrounds, ["rgb(255, 255, 255)", "rgb(13, 17, 23)"])
    }
}
