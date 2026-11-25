# Notebook Previews and Typeset Math Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quick Look shows `.ipynb` files as fully rendered static notebooks, and `$…$` math is typeset in every Markdown preview.

**Architecture:** A Swift scanner lifts math out of Markdown before cmark and puts it back as `.math` elements that bundled KaTeX typesets in the page script. A Swift notebook parser and renderer turn notebook JSON into HTML for the existing page shell; untrusted HTML fragments (Markdown cells, HTML outputs) are emitted escaped and inserted by the page script so they cannot leak markup or CSS.

**Tech Stack:** Swift 5 / SwiftPM (`Core/`), cmark-gfm, WKWebView, highlight.js (bundled), KaTeX (new, bundled), XCTest with real WKWebView.

**Spec:** `docs/superpowers/specs/2026-11-24-notebooks-and-math-design.md`. Read it before any task.

## Global Constraints

- The Content Security Policy in `PreviewDocument.page` is not loosened. No new source, no `unsafe-eval`, no iframe.
- No network at preview time; no runtime dependency outside the app bundle.
- Pages without math must not contain KaTeX (script or stylesheet). Pages without code must not contain highlight.js (unchanged).
- A notebook that fails to parse shows the highlighted JSON view, never a blank or error-only panel.
- Notebooks are read whole up to 50 MB (`PreviewDocument.maxNotebookBytes = 50 * 1024 * 1024`); larger ones show a notice with the file size.
- Tests are real: real cmark, real WKWebView, a really executed example notebook. No mocks. Never weaken an existing test; fix the code.
- KaTeX `trust` stays off.
- American English in code comments and docs.
- After any fix made to pass one check, rerun all checks (`cd Core && swift test`).
- Commit after every task, by path (`git add <paths>`), on branch `notebooks-and-math`. Commit messages end with:
  ```
  Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01DcKtypQy4efSDbm3KwPibs
  ```
- Nothing is pushed, tagged or published without Jeremy's say-so.

## Review Focus

Each line has a test in the named task.

1. A notebook that was never run (no outputs, `execution_count: null`) renders every cell with an empty `[ ]:` prompt. (Task 5)
2. A `$` inside code cells, stream output, tracebacks or `text/plain` output is never typeset. (Task 5)
3. A Markdown cell or HTML output with an unclosed tag (`<div>`, `<b>`, `<details>`) does not swallow, hide or restyle the cells after it. (Task 6)
4. Loose notebook JSON: `source` as one string instead of a list, missing `outputs`/`metadata`, an unknown `cell_type`, a MIME value given as a list of lines. All render; nothing crashes. (Task 4)
5. A 20 MB notebook full of base64 figures produces its HTML in under 2 seconds and is not truncated. (Task 5)

## File Structure

| File | Responsibility |
|-|-|
| `Core/Sources/MDBuddyCore/MathScanner.swift` (new) | Find math in Markdown source, swap it for placeholders, restore as `.math` elements |
| `Core/Sources/MDBuddyCore/MarkdownRenderer.swift` | Calls the scanner around cmark |
| `Core/Sources/MDBuddyCore/Resources/katex.min.js`, `katex.min.css` (new, generated) | Vendored KaTeX; fonts inlined in the CSS |
| `scripts/vendor_katex.py` (new) | Regenerates the two KaTeX files from a pinned, checksummed release |
| `Core/Sources/MDBuddyCore/Resources.swift`, `PreviewDocument.swift` | Include KaTeX only when the page has math; notebook kind, limits, fallback |
| `Core/Sources/MDBuddyCore/Notebook.swift` (new) | Parse nbformat 4 and 3 JSON into a small model |
| `Core/Sources/MDBuddyCore/ANSI.swift` (new) | ANSI escape codes to HTML spans |
| `Core/Sources/MDBuddyCore/NotebookRenderer.swift` (new) | Model to HTML |
| `Core/Sources/MDBuddyCore/Resources/app.js`, `style.css` | Fragment insertion, math typesetting, notebook styles |
| `Core/Tests/MDBuddyCoreTests/MathTests.swift`, `NotebookTests.swift` (new) | Unit tests |
| `Core/Tests/MDBuddyCoreTests/WebKitTests.swift` | Real-WebView tests for math and notebooks |
| `scripts/make_example_notebook.py` (new), `examples/notebook.ipynb` (new) | Builds and really executes the example notebook |

---

### Task 1: Prove Quick Look will hand `.ipynb` to MD Buddy

The notebook half rests on this. Do it before anything else; today's JSON view is enough to prove routing.

**Files:**
- Modify: `scripts/gen_types.py` (`RESERVED`), `Core/Tests/MDBuddyCoreTests/RoutingTests.swift` (`reserved`)
- Regenerated: `App/Info.plist`, `PreviewExtension/Info.plist`

- [ ] **Step 1:** Remove `"ipynb"` from `RESERVED` and from `RoutingTests.reserved`.
- [ ] **Step 2:** Run `python3 scripts/gen_types.py`. Expected: `ipynb` appears in the `org.contextlab.mdbuddy.source` extension list in `App/Info.plist` (it is a dynamic type on this Mac, so the existing mechanism imports it).
- [ ] **Step 3:** `make install`, then `mdls -name kMDItemContentType <any .ipynb>`. Expected: `org.contextlab.mdbuddy.source`.
- [ ] **Step 4:** Select a real `.ipynb` in Finder and press Space (reuse the `capture` approach in `scripts/screenshots.sh`); save the panel screenshot to the scratchpad and look at it. Expected: MD Buddy's highlighted JSON view.
- [ ] **Step 5:** If it does not route, stop and report to Jeremy with the `mdls` output and screenshot. Do not continue to notebook tasks on a guess. If another app on a user's Mac declares its own notebook type, that identifier must be claimed too: search the web for the identifiers VS Code and JupyterLab Desktop declare for `.ipynb`, verify each against the app's actual `Info.plist` source, and add confirmed ones to `BASE_TYPES`.
- [ ] **Step 6:** `cd Core && swift test`. Expected: all pass, including `testEveryKnownExtensionIsClaimed`.
- [ ] **Step 7:** Commit: "Route .ipynb to MD Buddy".

---

### Task 2: Math scanner

**Files:**
- Create: `Core/Sources/MDBuddyCore/MathScanner.swift`, `Core/Tests/MDBuddyCoreTests/MathTests.swift`
- Modify: `Core/Sources/MDBuddyCore/MarkdownRenderer.swift`

**Interfaces:**
- Produces:
  ```swift
  struct MathSpan: Equatable { let tex: String; let display: Bool }
  enum MathScanner {
      /// Replaces each math span with a placeholder cmark passes through untouched.
      static func protect(_ markdown: String, bareEnvironments: Bool) -> (text: String, spans: [MathSpan], token: String)
      /// Replaces placeholders in rendered HTML with math elements.
      static func restore(_ html: String, spans: [MathSpan], token: String) -> String
  }
  // MarkdownRenderer
  public static func render(_ markdown: String, bareMathEnvironments: Bool = false) -> String
  ```
- Restored element, exactly: `<span class="math math-inline">ESCAPED_TEX</span>` or `<span class="math math-display">ESCAPED_TEX</span>` (TeX without its delimiters, HTML-escaped with `HTML.escape`). Later tasks detect math with `html.contains("class=\"math ")`.
- Placeholder: letters and digits only, with a per-call random `token` so document text cannot collide.

Rules (from the spec):
- `$…$` inline: opening `$` not followed by whitespace; closing `$` not preceded by whitespace and not followed by a digit; no blank line inside. `$$…$$` display, may span lines. `\(…\)` inline, `\[…\]` display. `\$` is a literal dollar.
- Not math: anything inside inline code spans (any backtick run length), fenced code blocks (``` and ~~~), indented code blocks, and the front-matter block.
- `bareEnvironments: true` only: a `\begin{name}…\end{name}` block outside `$` is display math, TeX kept whole including `\begin`/`\end`. Before writing this rule, read how Jupyter decides it (JupyterLab `packages/rendermime/src/latex.ts`, `removeMath`; fetch it from GitHub) and match its rule for which blocks count; quote the lines you relied on in a code comment.

- [ ] **Step 1: Write failing tests** in `MathTests.swift`:

```swift
final class MathScannerTests: XCTestCase {
    private func spans(_ md: String, bare: Bool = false) -> [MathSpan] { MathScanner.protect(md, bareEnvironments: bare).spans }

    func testInlineAndDisplay() {
        XCTAssertEqual(spans("Euler: $e^{i\\pi}+1=0$ and\n\n$$\n\\int_0^1 x\\,dx\n$$"),
                       [MathSpan(tex: "e^{i\\pi}+1=0", display: false), MathSpan(tex: "\n\\int_0^1 x\\,dx\n", display: true)])
    }
    func testParenAndBracketDelimiters() {
        XCTAssertEqual(spans("\\(a\\) then \\[b\\]"), [MathSpan(tex: "a", display: false), MathSpan(tex: "b", display: true)])
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
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">a_i + b_i</span>"))
        XCTAssertTrue(html.contains("<span class=\"math math-inline\">c_j * d_j * e</span>"))
        XCTAssertFalse(html.contains("<em>"))
    }
    func testTexIsEscaped() {
        XCTAssertTrue(MarkdownRenderer.render("$a < b & c$").contains("<span class=\"math math-inline\">a &lt; b &amp; c</span>"))
    }
    func testBareEnvironmentOnlyWhenAsked() {
        let md = "Text\n\n\\begin{align}\na &= b \\\\\nc &= d\n\\end{align}\n"
        XCTAssertEqual(spans(md), [])
        XCTAssertEqual(spans(md, bare: true), [MathSpan(tex: "\\begin{align}\na &= b \\\\\nc &= d\n\\end{align}", display: true)])
    }
    func testNoMathMeansNoMathMarkup() {
        XCTAssertFalse(MarkdownRenderer.render("# Plain\n\nNo math, $5 only.").contains("class=\"math "))
    }
    func testPlaceholderLikeTextIsUntouched() {
        let md = "MDBMATH0X and $x$"
        XCTAssertTrue(MarkdownRenderer.render(md).contains("MDBMATH0X"))
    }
    func testFrontMatterIsNotScanned() {
        XCTAssertFalse(MarkdownRenderer.render("---\nprice: $x$\n---\n\nBody").contains("class=\"math "))
    }
}
```

- [ ] **Step 2:** `cd Core && swift test --filter MathScannerTests`. Expected: compile failure (no `MathScanner`).
- [ ] **Step 3:** Implement `MathScanner` and call it in `MarkdownRenderer.render` around `renderCommonMark(body)` (after the front-matter split).
- [ ] **Step 4:** `cd Core && swift test`. Expected: all pass, including every existing renderer test unchanged.
- [ ] **Step 5:** Commit: "Lift math out of Markdown before cmark".

---

### Task 3: KaTeX bundled and typesetting in the page

**Files:**
- Create: `scripts/vendor_katex.py`, `Core/Sources/MDBuddyCore/Resources/katex.min.js`, `Core/Sources/MDBuddyCore/Resources/katex.min.css`
- Modify: `Resources.swift`, `PreviewDocument.swift`, `Resources/app.js`, `Resources/style.css`, `THIRD_PARTY_NOTICES.md`, `examples/showcase.md`, `Core/Tests/MDBuddyCoreTests/{RendererTests,WebKitTests}.swift`

**Interfaces:**
- Consumes: `.math.math-inline` / `.math.math-display` elements from Task 2.
- Produces:
  ```swift
  // Resources
  static let mathScript: String        // katex.min.js
  static let mathStylesheet: String    // katex.min.css, fonts inlined as data: woff2
  static func appScript(highlight: Bool, math: Bool = false) -> String
  // PreviewDocument
  static func page(title:codeFontSize:bodyClass:body:script:math: Bool = false) -> String  // adds mathStylesheet in its own <style> when math
  ```
- `app.js` gains `typesetMath(root)`: for each `.math`, `katex.render(el.textContent, el, {displayMode: el.classList.contains("math-display"), throwOnError: false, trust: false, strict: "ignore"})`. Runs after heading anchors are added (so heading slugs use the TeX source text consistently) and is a no-op when `katex` is undefined.

- [ ] **Step 1:** Write `scripts/vendor_katex.py`: download the newest stable KaTeX release tarball from the project's GitHub releases, pin its exact version and SHA-256 as constants in the script, verify the checksum, write `katex.min.js` as shipped, and write `katex.min.css` with every `url(fonts/….woff2)` replaced by a `data:font/woff2;base64,…` URI and the `.woff`/`.ttf` sources removed from each `src`. Print the two output sizes. Run it. Verify the release URL and the license text by opening them, not from memory.
- [ ] **Step 2: Write failing tests.**

In `RendererTests.swift`:
```swift
func testMathPageIncludesKaTeXAndOthersDoNot() {
    let math = PreviewDocument(fileName: "m.md", data: Data("$x^2$".utf8)).html
    XCTAssertTrue(math.contains("katex"))
    XCTAssertTrue(math.contains("data:font/woff2;base64,"))
    let plain = PreviewDocument(fileName: "p.md", data: Data("costs $5 and $10".utf8)).html
    XCTAssertFalse(plain.contains("katex"))
    XCTAssertFalse(PreviewDocument(fileName: "a.py", data: Data("x = '$y$'".utf8)).html.contains("katex"))
}
func testKaTeXFontsAreInlinedCompletely() {
    XCTAssertFalse(Resources.mathStylesheet.contains("url(fonts/"))
    XCTAssertGreaterThan(Resources.mathScript.count, 100_000)
}
```
In `WebKitTests.swift`:
```swift
func testMathIsTypeset() async throws {
    let page = try await render("Inline $a_i^2$ and\n\n$$\\frac{1}{2}$$\n\nMoney: $5 and $10. Code: `$x$`.")
    XCTAssertEqual(try await string(page, "String(document.querySelectorAll('.math .katex').length)"), "2")
    XCTAssertEqual(try await string(page, "String(document.querySelectorAll('.math-display .katex-display').length)"), "1")
    XCTAssertEqual(try await string(page, "String(document.querySelectorAll('.mfrac').length)"), "1")
    XCTAssertEqual(try await string(page, "document.querySelector('code').textContent"), "$x$")
    XCTAssertTrue(try await string(page, "document.body.innerText").contains("$5 and $10"))
}
func testMathUsesKaTeXFonts() async throws {
    let page = try await render("$x$")
    _ = try await page.evaluate("document.fonts.ready.then(() => 1)")
    XCTAssertTrue(try await string(page, "getComputedStyle(document.querySelector('.katex')).fontFamily").contains("KaTeX_Main"))
    XCTAssertEqual(try await string(page, "String(document.fonts.check('16px KaTeX_Main'))"), "true")
}
func testBadTeXShowsSourceNotBlank() async throws {
    let page = try await render("$\\frac{1$ after")
    XCTAssertTrue(try await string(page, "document.querySelector('.math').textContent").contains("\\frac{1"))
    XCTAssertTrue(try await string(page, "document.body.innerText").contains("after"))
}
```
If `renderer.evaluate` cannot await a promise, add an `evaluateAsync` to `WebPageRenderer` using `callAsyncJavaScript`.
- [ ] **Step 3:** Run them. Expected: FAIL (no KaTeX in page).
- [ ] **Step 4:** Implement the interfaces above. `PreviewDocument` passes `math: body.contains("class=\"math ")` for Markdown. Add to `style.css`: display math scrolls sideways instead of overflowing (`.math-display { overflow-x: auto; }`), and math inherits the text color in dark mode.
- [ ] **Step 5:** Add a "Math" section to `examples/showcase.md` (inline, display, an aligned block inside `$$`, a currency sentence) and extend `testShowcaseRendersEveryFeature` to assert `class="math math-display"`.
- [ ] **Step 6:** Add KaTeX and its fonts to `THIRD_PARTY_NOTICES.md` with the license text copied from the vendored release.
- [ ] **Step 7:** `cd Core && swift test`. Expected: all pass.
- [ ] **Step 8:** Render `examples/showcase.md` to PNG in light and dark with `mdbuddy-render --png … --full --appearance light|dark` into the scratchpad and look at both images. Expected: math typeset, legible in both.
- [ ] **Step 9:** Commit: "Typeset math with bundled KaTeX".

---

### Task 4: Notebook model

**Files:**
- Create: `Core/Sources/MDBuddyCore/Notebook.swift`, `Core/Tests/MDBuddyCoreTests/NotebookTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct Notebook {
      let language: String                 // highlight.js name; "python" when unknown
      let cells: [Cell]
      enum Cell {
          case markdown(source: String, attachments: [String: [String: String]])  // name → mime → base64
          case code(source: String, executionCount: Int?, outputs: [Output])
          case raw(source: String)
      }
      enum Output {
          case stream(name: String, text: String)                       // "stdout" / "stderr"
          case data(bundle: [String: Any], metadata: [String: Any], executionCount: Int?)  // display_data, execute_result
          case error(name: String, value: String, traceback: [String])
      }
      /// nil when `data` is not a JSON object with a list of cells (v4) or worksheets (v3).
      static func parse(_ data: Data) -> Notebook?
      /// A MIME value as text: a String as is, an array of Strings joined with "".
      static func text(_ value: Any?) -> String?
  }
  ```
- Language: `metadata.language_info.name`, else `metadata.kernelspec.language`, else `"python"`; lowercased; map `"ir"`/`"R"` to `"r"`.
- nbformat 3: cells are `worksheets[*].cells`; code source is `input`, count is `prompt_number`; output types `pyout` → data with `prompt_number`, `pyerr` → error, `display_data`, `stream` (field `stream` instead of `name`); short keys map to MIME types (`png` → `image/png`, `jpeg` → `image/jpeg`, `svg` → `image/svg+xml`, `html` → `text/html`, `latex` → `text/latex`, `text` → `text/plain`, `json` → `application/json`); `heading` cells become Markdown with `level` `#` marks.
- An unknown `cell_type` becomes `.raw`. Missing `outputs`, `metadata`, `source` are empty.

- [ ] **Step 1: Write failing tests** `NotebookModelTests` using inline JSON literals: `testV4CellsAndLanguage` (one of each cell type, `language_info.name = "julia"`), `testSourceAsStringOrList` (both give the same source), `testMissingKeysAndUnknownCellType` (cell with only `cell_type: "weird"` → `.raw(source: "")`; code cell with no `outputs`), `testMimeValueAsListOfLines` (`Notebook.text(["a\n","b"]) == "a\nb"`), `testV3Worksheets` (input/prompt_number/pyout/pyerr/heading mapped as above), `testNotANotebook` (`parse` is nil for `[]`, `{"a":1}`, truncated JSON, empty data), `testKernelspecFallbackAndDefault`.
- [ ] **Step 2:** Run. Expected: compile failure.
- [ ] **Step 3:** Implement with `JSONSerialization`.
- [ ] **Step 4:** `cd Core && swift test`. Expected: all pass.
- [ ] **Step 5:** Commit: "Parse nbformat 4 and 3 notebooks".

---

### Task 5: Notebook rendering in Swift

**Files:**
- Create: `Core/Sources/MDBuddyCore/ANSI.swift`, `Core/Sources/MDBuddyCore/NotebookRenderer.swift`
- Modify: `DocumentKind.swift`, `PreviewDocument.swift`, `PreviewExtension/PreviewViewController.swift`, `Core/Sources/mdbuddy-render/main.swift` (only if a switch needs the new case), `NotebookTests.swift`, `RendererTests.swift` (`testDetection`)

**Interfaces:**
- Consumes: `Notebook` (Task 4); `MarkdownRenderer.render(_:bareMathEnvironments:)` (Task 2); `page(…math:)`, `appScript(highlight:math:)` (Task 3).
- Produces:
  ```swift
  // DocumentKind
  case notebook            // detect(): "ipynb" → .notebook, checked before LanguageMap
  // ANSI
  enum ANSI { static func html(_ text: String) -> String }   // escaped text; SGR codes → <span class="ansi-…">
  // NotebookRenderer
  enum NotebookRenderer { static func render(_ notebook: Notebook) -> String }
  // PreviewDocument
  public static let maxNotebookBytes = 50 * 1024 * 1024
  ```
- HTML contract (Task 6's script and CSS rely on these exact names):
  - Wrapper: `<article class="markdown-body notebook">`; body class `notebook`.
  - Each cell: `<section class="nb-cell nb-markdown|nb-code|nb-raw">`.
  - Markdown cell body: `<div class="nb-fragment" data-mode="light" hidden>ESCAPED_RENDERED_HTML</div>` (HTML from `MarkdownRenderer.render(source, bareMathEnvironments: true)` then `RemoteImages.rewrite`, then `HTML.escape`).
  - Code cell: `<div class="nb-prompt">[3]:</div>` (`[ ]:` when the count is nil) and `<pre class="nb-source"><code class="language-LANG">…</code></pre>`; over `maxHighlightBytes` the code class is `nohighlight`.
  - Outputs: `<div class="nb-output nb-stream nb-stdout|nb-stderr">`, `nb-error`, `nb-result` (with its `[n]:` prompt for `execute_result`), `nb-display`.
  - HTML output: `<div class="nb-fragment" data-mode="shadow" hidden>ESCAPED_OUTPUT_HTML</div>`.
  - ANSI classes: `ansi-bold`, `ansi-fg-{black,red,green,yellow,blue,magenta,cyan,white}`, the same with `bright-`, and `ansi-bg-…`; 256-color and truecolor codes become inline `style="color:#rrggbb"`.
- Output MIME order: `text/html`, `image/svg+xml`, `image/png`, `image/jpeg`, `image/gif`, `text/markdown`, `text/latex`, `application/json`, `text/plain`.
  - `text/html` is skipped when it is a script shell: after removing `<script>…</script>` and `<style>…</style>` it has no non-whitespace text and none of `<img`, `<table`, `<svg`, `<video`, `<canvas`.
  - Images, SVG included, are `<img src="data:MIME;base64,…">` (SVG text is base64-encoded first; whitespace stripped from base64 payloads). `metadata[mime].width/height` become `width`/`height` attributes.
  - `text/markdown` and `text/latex` go through `MarkdownRenderer.render(_, bareMathEnvironments: true)` as a light fragment.
  - `application/json` is pretty-printed (sorted keys) in `<pre><code class="language-json">`.
  - `text/plain` and streams: `<pre>` with `ANSI.html`. Tracebacks: lines joined with `\n`, `ANSI.html`.
  - No renderable MIME: `<div class="nb-output nb-unsupported">Output of type TYPES can't be shown in a static preview.</div>` listing the bundle's keys.
- Attachments: in a Markdown cell's source, `attachment:NAME` becomes `data:MIME;base64,…` before rendering.
- `PreviewDocument.init` for `.notebook`: no 8 MB truncation; over `maxNotebookBytes` → notice page "This notebook is SIZE, too large to preview (limit 50 MB)."; `Notebook.parse` nil → continue as `.code(language: "json")` with the existing limits and `kind` set to that; otherwise render with `highlight:` true when any `<code class="language-` is present (including inside escaped fragments) and `math:` true when `class=&quot;math ` or `class="math ` is present.
- `PreviewViewController`: `.notebook` uses `NSSize(width: 900, height: 900)`.

- [ ] **Step 1: Write failing tests** in `NotebookTests.swift` (`NotebookRendererTests`, `ANSITests`), each building a small real notebook JSON string and rendering it through `PreviewDocument(fileName: "n.ipynb", data:)`:
  - `testDetectionAndKind`: `DocumentKind.detect(fileName: "A.IPYNB") == .notebook`; update `testDetection` accordingly.
  - `testNeverRunNotebook`: two code cells, no outputs, null counts → two `[ ]:` prompts, no `nb-output`.
  - `testCodeCellLanguageAndPrompt`: R notebook → `class="language-r"`, `[7]:`.
  - `testDollarsInCodeAndOutputsAreNotMath`: code `cost = "$x$"`, stream `$a$ $b$`, traceback with `$`, `text/plain` `$y$` → html contains no `class="math ` and no `class=&quot;math `, and no `katex`.
  - `testMarkdownCellMathAndBareEnvironment`: cell `$x$` plus a bare `\begin{align}` → fragment contains `class=&quot;math math-inline&quot;` and `math-display`; page contains `katex`.
  - `testAttachmentBecomesDataImage`: `![a](attachment:p.png)` with a 1×1 PNG attachment → `src=&quot;data:image/png;base64,`.
  - `testMimePriority`: bundle with html+png+plain → shadow fragment, no `<img`; png+plain → `<img src="data:image/png;base64,`; plain only → `<pre>`.
  - `testScriptShellFallsBackToImage`: html `<div id="p"></div><script>Plotly.newPlot()</script>` + png → `<img`, and the html contains no `Plotly`.
  - `testSVGOutputIsAnImage`: svg containing `<script>` → `data:image/svg+xml;base64,` and no raw `<svg`.
  - `testImageSizeMetadata`: `metadata: {"image/png": {"width": 320, "height": 200}}` → `width="320" height="200"`.
  - `testJSONOutputPrettyPrinted`, `testMarkdownAndLatexOutputs`, `testUnsupportedOutputNote` (bundle with only `application/vnd.jupyter.widget-view+json`).
  - `testStreamsAndTraceback`: stderr gets `nb-stderr`; traceback `"\u{1B}[0;31mZeroDivisionError\u{1B}[0m: division by zero"` → `<span class="ansi-fg-red">ZeroDivisionError</span>: division by zero`.
  - `ANSITests`: bold, bright colors, background, reset mid-line, 256-color `38;5;196`, truecolor `38;2;1;2;3`, unknown/cursor codes dropped, text HTML-escaped (`<b>` → `&lt;b&gt;`).
  - `testMalformedNotebookFallsBackToJSON`: `{"cells": [` → `kind == .code(language: "json")`, html contains `class="code-view"`.
  - `testOversizeNotebookNotice`: data of `maxNotebookBytes + 1` bytes → "too large to preview", no `nb-cell`.
  - `testBigNotebookIsWholeAndFast`: 20 code cells each with a 1 MB base64 PNG output (valid PNG header, padded) → all 20 `<img` present, no "Showing the first", `measure`d under 2 s (assert with a wall-clock check).
  - `testCSPUnchangedForNotebook`: the CSP line equals the one produced for a `.md` file apart from the nonce.
- [ ] **Step 2:** Run. Expected: compile failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `cd Core && swift test`. Expected: all pass.
- [ ] **Step 5:** Commit: "Render notebooks to HTML".

---

### Task 6: Notebook page script, styles and the example notebook

**Files:**
- Create: `scripts/make_example_notebook.py`, `examples/notebook.ipynb`
- Modify: `Resources/app.js`, `Resources/style.css`, `WebKitTests.swift`, `scripts/requirements.txt` (create if missing: the packages the example script needs)

**Interfaces:**
- Consumes: the HTML contract in Task 5.
- `app.js`, new first step `insertFragments()`, before anchors, alerts, images, math and highlighting:
  - `data-mode="light"`: `host.innerHTML = host.textContent; host.hidden = false` (the fragment parser closes any open tags inside the host).
  - `data-mode="shadow"`: `host.textContent` is saved, the host emptied, `attachShadow({mode: "open"})`, shadow content = `<style>` holding the text of `<style id="nb-output-style">` + the saved HTML; `host.hidden = false`.
  - `PreviewDocument.page` emits `<style id="nb-output-style">` (table, image and text rules for outputs, using the page's CSS variables, which inherit into shadow roots) for notebook pages.
  - Heading anchors, alerts and broken-image handling then run over the whole `.markdown-body`; highlighting runs over `pre code` in the light DOM (code inside HTML outputs is left as is).
- `style.css`: Jupyter-style layout from the spec sketch. Prompts in a fixed left gutter in the code font, muted color; code cells in the existing code-block box; outputs aligned under the code; wide outputs (`pre`, tables, shadow hosts) scroll sideways; images `max-width: 100%`; `nb-stderr` tinted; ANSI classes defined for light and dark with readable contrast on both backgrounds.

- [ ] **Step 1:** Write `scripts/make_example_notebook.py`: builds a notebook with `nbformat` and executes it for real with `nbclient` (Python kernel from the anaconda install; see the recorded notes `conda-env-location` and `venv-nbconvert-uses-other-jupyter` via `/Users/jmanning/claude-skill-compounder/bin/compound show <name>` before running). Cells: title and prose with inline math, `$$` display math and a bare `\begin{align}` block; a Markdown cell with an attached PNG; a pandas DataFrame; a pandas Styler with a background gradient; a matplotlib PNG figure; an SVG figure; stdout and stderr prints; a raised exception (allowed to fail); `display(Markdown(...))`; `display(Math(...))`; `display(JSON-like dict via a raw mime bundle)`; a mime bundle with script-only `text/html` plus `image/png`; a raw cell. Run it; commit the executed `examples/notebook.ipynb`. Keep it under 1 MB.
- [ ] **Step 2: Write failing WebKit tests** (a `renderFile(_ url:)` helper that loads a file from disk):
  - `testExampleNotebookRendersEverything`: on `examples/notebook.ipynb`: `.nb-cell` count equals the notebook's cell count; `.hljs-keyword` exists inside `.nb-source`; `.math .katex` count ≥ 3; every `img` has `naturalWidth > 0`; a shadow root contains a `table` whose computed `border-collapse` is `collapse`; `.ansi-fg-red` (or the traceback's color class) exists inside `.nb-error`; `document.body.innerText` contains no `Plotly`.
  - `testUnclosedTagsDoNotLeak`: notebook with Markdown cell `<div style="display:none"><b>open`, then Markdown cell `<details>hidden?`, then a code cell `x = 1` with HTML output `<table><tr><td>cell</td>` + `<style>body{display:none} .nb-source{color:red}</style>`, then Markdown cell `visible end`. Expect: the code cell's `.nb-source` has non-zero `offsetHeight`, is not inside a `b` or `details` (`closest('b, details') === null`), its computed color is not `rgb(255, 0, 0)`; `getComputedStyle(document.body).display !== "none"`; the last cell's text is visible (`offsetHeight > 0`).
  - `testScriptsInNotebookNeverRun`: Markdown cell and HTML output each with `<script>window.pwned=1</script>` and `<img src=x onerror="window.pwned=1">` → `String(window.pwned)` is `"undefined"`.
  - `testRelativeImageInMarkdownCell`: a notebook in the scratch folder with Markdown cell `![p](images/landscape.png)` → that `img` has `naturalWidth > 0`; `![m](images/missing.png)` becomes an `.image-placeholder`.
  - `testNotebookLightAndDark`: snapshot the example in `.aqua` and `.darkAqua`; body backgrounds are `rgb(255, 255, 255)` and `rgb(13, 17, 23)`.
- [ ] **Step 3:** Run. Expected: FAIL.
- [ ] **Step 4:** Implement the script and styles.
- [ ] **Step 5:** `cd Core && swift test`. Expected: all pass.
- [ ] **Step 6:** Render the example to full-height PNGs in light and dark at width 900 into the scratchpad and examine both: prompts aligned, tables styled, figures sized, traceback colored and readable, math typeset, nothing clipped. Fix what looks wrong; rerun Step 5 after any change.
- [ ] **Step 7:** Commit: "Notebook page script, styles and example".

---

### Task 7: Installed-app check, docs, notes

**Files:**
- Modify: `README.md`, `scripts/screenshots.sh`, `docs/screenshots/` (new notebook and math shots), `notes/2026-11-24-notebooks-and-math.md`, `project.yml` (only if Jeremy says so)

- [ ] **Step 1:** `python3 scripts/gen_types.py && make install`. Press Space in Finder on `examples/notebook.ipynb`, on `examples/showcase.md`, and on two of Jeremy's real notebooks (pick ones with figures from `/Users/jmanning/llm-course`); capture each panel and look at it. Expected: rendered notebook, math typeset, no blank panel, opens without a visible delay.
- [ ] **Step 2:** Measure the installed app (`du -sh "/Applications/MD Buddy.app"`) and the KaTeX files; use the measured numbers in the README.
- [ ] **Step 3:** README: add "Jupyter notebooks" and math to Features; replace the "Math and diagrams" limitation with a Mermaid-only one plus the notebook limits (static only, interactive outputs fall back, 50 MB, KaTeX vs MathJax environment coverage); correct the "installed app is 1 MB" and "highlight.js" lines; add the notebook branch to the "How it works" diagram; add a notebook screenshot (extend `scripts/screenshots.sh` to capture it). Describe only what the code does.
- [ ] **Step 4:** Full check: `cd Core && swift test`, `make build`. Expected: all pass, build clean. Check the diff for secrets and stray files (`git status`, no scratch files in the repo).
- [ ] **Step 5:** Update the session notes with what was built, measured sizes and anything learned.
- [ ] **Step 6:** Commit: "Docs and screenshots for notebooks and math".
- [ ] **Step 7:** Stop and ask Jeremy: whether to change the app's internal version from 1.0.0 for the v0.2 release, and whether to push, tag and publish.
