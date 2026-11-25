# 2026-11-24/25: notebook (.ipynb) previews + typeset math

## Request
- "new feature: add support for ipynb notebooks"
- `$…$` math must be typeset as LaTeX in *all* Markdown files, notebooks included.
- Fully rendered notebook: figures, formatted text, code highlighting, tables, outputs.
  Static only ("it's just a viewer").
- Bare LaTeX blocks in notebooks: "handled however jupyter does".
- "we can bump to 0.2".

## Decisions
- Math engine: KaTeX (Jeremy picked it over Temml and MathJax).
- Notebook rendering in Swift (JSONSerialization), into the existing page shell.
- Execution: native (this session builds every task; one fresh review at the end).

## State (branch `notebooks-and-math`, nothing pushed)
- Design: docs/superpowers/specs/2026-11-24-notebooks-and-math-design.md
- Plan: docs/superpowers/plans/2026-11-24-notebooks-and-math.md
- Tasks 1–7 built and committed. 105 tests pass (`cd Core && swift test`), `make build` clean,
  app installed in /Applications from this branch.
- Left: final whole-branch review; then ask Jeremy about (a) the app's internal version
  (still 1.0.0 in project.yml) for the v0.2 release, (b) push / PR / tag / publish.

## What was built
- `MathScanner.swift`: lifts `$…$`, `$$…$$`, `\(…\)`, `\[…\]` (and bare `\begin{…}` blocks in
  notebooks, Jupyter's rule ported from JupyterLab's latex.ts) out before cmark; restores as
  `<span class="math math-inline|math-display">`. Linear time on unclosed openers
  (`failedBefore` memo) after the automated security review flagged a quadratic scan.
- KaTeX 0.19.1 vendored by `scripts/vendor_katex.py` (pinned + SHA-256), fonts inlined as
  woff2 data URIs; added to a page only when it has math.
- `Notebook.swift` (nbformat 4 + 3 parser), `NotebookRenderer.swift`, `ANSI.swift`.
- Containment: rendered Markdown cells and HTML outputs are emitted escaped in
  `.nb-fragment` holders; `app.js` inserts them (HTML outputs into shadow roots with
  `notebook-output.css` copied in).
- `examples/notebook.ipynb` built and executed by `scripts/make_example_notebook.py`.
- `scripts/qlcapture.sh`: one real Finder Quick Look panel capture (split out of screenshots.sh).

## Measured
- Installed app: 1.8 MB (was about 1 MB). katex.min.js 267 KB, katex.min.css with fonts 360 KB.
- 1.3 MB Markdown (showcase ×400) → page in 0.26 s (was 0.10 s for 1.1 MB before the math scan).
- Example notebook → page in 0.02–0.03 s. A 33 MB real notebook loads in the off-screen
  WebView in about 2.4 s including process start.
- 178 notebooks under llm-course, storytelling-with-data, experimental-psychology: 164 render
  with no broken images, no unfilled fragments, no KaTeX errors; 1 is over 50 MB (notice);
  13 are not valid JSON (merge-conflict markers or empty) and show as JSON by design.

## Findings worth remembering
- `.ipynb` routes through the existing imported source type once unreserved; real Finder panel
  verified. Spotlight's `mdls` can report a stale `org.jupyter.ipynb`; the URL's
  typeIdentifier is what Quick Look uses.
- Regenerating types on a Mac with Pixelmator would have claimed Pixelmator's `.pxd` document
  type; `SHARED = {"pxd"}` in gen_types.py prevents that.
- The anaconda base Python here cannot import pandas/matplotlib (NumPy 2 mismatch); the
  example runs in `build/venv-notebook` (git-ignored, Homebrew python3.13).
- KaTeX numbers `align` rows with `.eqn-num` counters, and the number overhangs the block by
  2 px, which made every numbered equation scrollable until `.math-display` got side padding.
- WKWebView JS exceptions surface in XCTest as "InvalidTransition { phase: idle … }".

## Known limits / deferred
- Plotly outputs saved without a static image show "Output of type text/html can't be shown".
- Math inside an HTML attribute value (`alt="$x$"`) gets a span injected into the attribute.
- The math pre-scan made large Markdown about 2× slower to convert (still 0.26 s per 1.3 MB).
- A notebook containing bare `NaN` in its JSON (Python writes it, strict JSON forbids it) would
  fall back to the JSON view; not seen in 178 real notebooks.
