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

@MainActor
final class CodeFontSizeTests: XCTestCase {
    private func fontSize(of selector: String, in file: String, content: String, size: Double? = nil) async throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mdbuddy-font-\(UUID().uuidString)-\(file)")
        try Data(content.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = WebPageRenderer()
        if let size {
            _ = try await renderer.load(fileURL: url, codeFontSize: size)
        } else {
            _ = try await renderer.load(fileURL: url)
        }
        return try await renderer.evaluate("getComputedStyle(document.querySelector('\(selector)')).fontSize") as? String ?? ""
    }

    func testDefaultCodeSizeIs14px() async throws {
        let code = try await fontSize(of: ".code-view .source", in: "a.py", content: "x = 1\n")
        XCTAssertEqual(code, "14px")
        let gutter = try await fontSize(of: ".code-view .gutter", in: "a.py", content: "x = 1\n")
        XCTAssertEqual(gutter, "14px", "line numbers must match the code so rows stay aligned")
        let fenced = try await fontSize(of: ".markdown-body pre", in: "a.md", content: "```\nx\n```\n")
        XCTAssertEqual(fenced, "14px")
        let text = try await fontSize(of: "pre.plaintext", in: "a.log", content: "line\n")
        XCTAssertEqual(text, "14px")
    }

    func testCustomCodeSizeApplies() async throws {
        let code = try await fontSize(of: ".code-view .source", in: "a.py", content: "x = 1\n", size: 17)
        XCTAssertEqual(code, "17px")
        let fenced = try await fontSize(of: ".markdown-body pre", in: "a.md", content: "```\nx\n```\n", size: 17)
        XCTAssertEqual(fenced, "17px")
    }
}

final class CodeFontPreferenceTests: XCTestCase {
    private func size(_ value: Any?) -> Double {
        PreviewDocument.preferredCodeFontSize(globalPreferences: value.map { ["NSFixedPitchFontSize": $0] } ?? [:])
    }

    func testUsesExplicitSystemFixedPitchSize() {
        XCTAssertEqual(size(16.0), 16)
        XCTAssertEqual(size("15"), 15)
    }

    func testFallsBackTo14WhenUnsetOrInvalid() {
        XCTAssertEqual(size(nil), 14)
        XCTAssertEqual(PreviewDocument.preferredCodeFontSize(globalPreferences: nil), 14)
        XCTAssertEqual(size("big"), 14)
        XCTAssertEqual(size(0.0), 14)
    }

    func testClampsExtremeValues() {
        XCTAssertEqual(size(4.0), 8)
        XCTAssertEqual(size(200.0), 48)
    }

    /// AppKit registers NSFixedPitchFontSize = 11 as a fallback, so a plain
    /// UserDefaults lookup reports 11 even when the user never set anything.
    func testIgnoresAppKitRegisteredFallback() throws {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if global?["NSFixedPitchFontSize"] != nil {
            throw XCTSkip("NSFixedPitchFontSize is set on this Mac")
        }
        UserDefaults.standard.register(defaults: ["NSFixedPitchFontSize": 11])
        XCTAssertEqual(UserDefaults.standard.double(forKey: "NSFixedPitchFontSize"), 11)
        XCTAssertEqual(PreviewDocument.preferredCodeFontSize(), 14)
    }
}
