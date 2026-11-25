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

## State (branch `notebooks-and-math`)
- Design: docs/superpowers/specs/2026-11-24-notebooks-and-math-design.md
- Plan: docs/superpowers/plans/2026-11-24-notebooks-and-math.md
- Tasks 1–7 built; final whole-branch review done and its findings fixed (below).
  116 tests pass (`cd Core && swift test`), app installed in /Applications from this branch.
- 2026-11-25, Jeremy: app version → 1.1.0 (was 1.0.0); push the branch when the review is
  clean; "sync the tags with the actual version numbers". Done: tag `v0.1` renamed to `v1.0.0`
  (same commit 7adecb0, GitHub release retitled "MD Buddy v1.0.0", asset unchanged).
- 2026-11-25, Jeremy: "Merge to main and release as v1.1.0". main fast-forwarded to the branch;
  tag `v1.1.0`; release https://github.com/ContextLab/md-buddy/releases/tag/v1.1.0 with
  MD-Buddy-1.1.0.zip (arm64, ad hoc signed, sha256 aad89af8…72995).
- `make dist` now zips without extended attributes: the zip (and the old 1.0.0 one) failed
  `codesign --verify` when unpacked with unzip(1) because com.apple.provenance came out as
  `._` files inside the bundle. Finder's unzip was unaffected. The 1.0.0 asset was not rebuilt.

## Final review (independent reviewer, 2026-11-25): fixed
- `isScriptShell` used regexes that took 285 s on 300 KB of unclosed `<`; now one pass over bytes.
- Carriage returns overwrite in place like a terminal ("abcdef\rxy" → "xycdef"; trailing "\r"
  no longer blanks the line).
- Math inside a tag (image alt text, raw HTML attribute) is restored as plain `$…$` text.
- Inline math stops at the next list item; math in a block quote drops the `>` markers; a
  backslash at a line end no longer lets math cross a blank line.
- Remote images in HTML outputs go through `mdbuddy-remote:` and get the placeholder chip.
- `.nb-body { contain: layout paint }`: an output's CSS cannot cover the page.
- After the push, the automated security review flagged two more, both fixed (118 tests):
  carriage returns now use a write cursor (a long line rewritten 200,000 times took ~48 s),
  and inlined attachment data is capped in total at the 50 MB notebook limit.
- `safe_replace.py` (compound lesson script) doubled the indent of a replacement's first line
  and doubled final newlines; fixed there, and the damage in this branch repaired.

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
- `$HOME:$PATH` in prose is read as math (the GitHub/Pandoc rule as specified).
- Raw `<pre>`/`<code>` HTML in Markdown is not protected from math (backtick spans and fenced
  or indented blocks are).
- Math inside HTML outputs (`<td>$\alpha$</td>`) is not typeset; Jupyter typesets it.
- CSP still allows remote `img-src *`; Quick Look's sandbox has no network, so `srcset`,
  `<video poster>` and CSS `url()` in outputs simply fail to load (no placeholder).
- The math pre-scan made large Markdown about 2× slower to convert (still 0.26 s per 1.3 MB).
- A notebook containing bare `NaN` in its JSON (Python writes it, strict JSON forbids it) would
  fall back to the JSON view; not seen in 178 real notebooks.
