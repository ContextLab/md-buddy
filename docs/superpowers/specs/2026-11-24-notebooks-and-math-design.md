# Jupyter notebook previews and typeset math

Date: 2026-11-24. Status: approved 2026-11-24.

## Intent

Pressing Space on a `.ipynb` file in Finder should show the fully rendered notebook: formatted
text, highlighted code, figures, tables and every output, the way a static notebook viewer
shows it. Math written as `$…$` should be typeset as LaTeX in every Markdown file MD Buddy
previews, notebooks included.

Jeremy's words: "the fully rendered notebook, with all content nicely rendered"; "math enclosed
by `$...$` should get rendered as latex in *all* markdown files (including notebooks)";
"non-interactive is fine, it's just a viewer".

## Goals

1. `.ipynb` files are routed to MD Buddy by Quick Look and shown as a rendered notebook.
2. Markdown cells render exactly as a `.md` file does (same renderer, same features).
3. Code cells are syntax-highlighted in the notebook's language, with execution counts.
4. Every output is shown in its richest static form: figures, HTML tables, LaTeX, text,
   coloured tracebacks.
5. `$…$` and `$$…$$` math is typeset in all Markdown previews and in notebook Markdown cells
   and LaTeX outputs.
6. Light and dark appearance both look right.

## Non-goals

- Interactivity: widgets, Plotly/Bokeh JavaScript, running or editing cells.
- Mermaid diagrams (still shown as written).
- Honouring "hidden"/"collapsed" cell flags. It is a viewer; everything is shown.
- Publishing. Jeremy: "we can bump to 0.2", so this work is the v0.2 release, but tagging
  and publishing happen only on his say-so at the end. Whether the app's internal version
  (kept at 1.0.0 for v0.1) also changes is confirmed with him then.

## Anti-goals

- Nothing may loosen the page's Content Security Policy. Scripts inside a notebook never run.
- No network access and no new runtime dependency outside the app bundle.
- Previews of files with no math must not get slower or heavier: the math library is included
  in a page only when that page contains math (the way highlight.js is today).
- A notebook that fails to parse must never show a blank or error-only panel.

## Constraints

- Quick Look extensions have no network (notes, 2026-09-23), so the math library and its fonts
  ship inside the app and are inlined into the page.
- The CSP already allows `img-src data:` and `font-src data:`; base64 images and fonts work
  as is.
- Quick Look routes by exact type identifier. `.ipynb` is currently in the "left to macOS"
  list in `scripts/gen_types.py` and `RoutingTests.reserved`, and on this Mac it has a dynamic
  (unclaimed) type.
- Tests use real rendering (cmark, a real WKWebView); no mocks.

## Approaches

**Notebooks.** One sensible way: parse the JSON in Swift (`JSONSerialization`, no new
dependency) and emit HTML into the existing page shell. Rendering in JavaScript was dropped:
it would move the logic out of the Swift test suite for no gain.

**Math.** Three were considered. Jeremy picked KaTeX.

| |Draws with|Added size (approx.)|Trade-off|
|-|-|-|-|
|**KaTeX (picked)**|HTML + its own fonts|~600 KB|Best-looking and most reliable. App grows from ~1 MB to ~2 MB.|
|Temml|WebKit MathML + system math font|~150–200 KB|Smallest; WebKit's MathML layout is rougher in places.|
|MathJax (SVG)|SVG paths|~2 MB|Widest coverage; largest and slowest.|

The sizes are from memory and must be measured when the files are vendored.

## Design

### Part 1: math in Markdown

- **Delimiters** (Claude's call): `$…$` inline, `$$…$$` display, plus `\(…\)` and `\[…\]`.
  A `$` opens inline math only if the next character is not whitespace; it closes only if the
  previous character is not whitespace and the next is not a digit. So "costs $5 and $10" is
  left alone. `\$` is a literal dollar sign. This is the rule GitHub and Pandoc use.
- **Protection from cmark.** Math is found and lifted out before cmark parses the text, then
  put back afterwards as an element carrying the escaped TeX source (inline vs display marked).
  Otherwise `$a_i + b_i$` has its underscores turned into emphasis. Math inside inline code
  spans and fenced/indented code blocks is not math and must be left untouched.
- **Typesetting.** KaTeX runs in the page script and replaces each math element. A formula
  KaTeX cannot parse is shown as its source in KaTeX's error colour, never dropped.
- **Bundling.** KaTeX's script, stylesheet and fonts (woff2 only, base64 in the stylesheet)
  are vendored under `Resources/`, version pinned, produced by a script in `scripts/` so the
  bundle can be regenerated. Its MIT licence goes in `THIRD_PARTY_NOTICES.md`.
- `.Rmd` and `.qmd` get this for free since they are Markdown kinds.
- **Bare LaTeX environments** (Jeremy: "handled however jupyter does"): in notebook Markdown
  cells, Jupyter treats any `\\begin{name}…\\end{name}` block written without `$` as math and
  hands it to its typesetter. MD Buddy applies the same rule for what counts as math, checked
  against Jupyter's own source rather than assumed. One difference cannot be avoided: Jupyter
  typesets with MathJax and MD Buddy with KaTeX, so an environment KaTeX does not know is
  shown as its source. In `.md` files a bare block stays as written, as on GitHub (Claude's
  call).

### Part 2: notebooks

- **Routing.** New `DocumentKind.notebook` for `.ipynb`. `.ipynb` leaves the reserved lists;
  the app declares a type for it and the extension claims it. First thing to verify in the
  build: that Quick Look really hands the file to MD Buddy once the type is declared
  (installed app, real Finder panel).
- **Formats.** nbformat 4 fully. nbformat 3 best effort (its cells live under `worksheets`
  and use older field names). Anything that does not parse as a notebook falls back to
  today's behaviour for unknown JSON: a highlighted JSON code view (Claude's call).
- **Cells.**
  - Markdown: through `MarkdownRenderer`, including math. Cell attachments
    (`attachment:name.png`) become `data:` images. Relative images resolve next to the file
    as they do for `.md`.
  - Code: highlighted using the language from `metadata.language_info.name`, then
    `metadata.kernelspec.language`, defaulting to Python. Shown with its `[n]:` execution
    count in a left gutter, Jupyter-style.
  - Raw: shown as plain preformatted text.
- **Outputs.** For `display_data`/`execute_result`, pick the first available of:
  `text/html`, `image/svg+xml`, `image/png`, `image/jpeg`, `image/gif`, `text/markdown`,
  `text/latex`, `application/json`, `text/plain`. `stream` output is preformatted text
  (stderr tinted). `error` shows the traceback. ANSI colour codes in streams and tracebacks
  are converted to colours.
  - HTML outputs are contained (Claude's call): an output's own `<style>` rules and any
    unclosed tags must not affect anything outside that output. pandas puts a `<style>` block
    in every DataFrame, and Styler output carries its own CSS, which should still colour its
    own table. The mechanism is the builder's; a shadow root per HTML output, filled by the
    page script and given the page's table styles, is the suggested one. The CSP is not
    changed, and scripts in outputs never run.
  - An HTML output that is only a script shell (Plotly, widgets) and has an image or text
    alternative uses that alternative instead (Claude's call).
  - pandas tables get the same table styling as Markdown tables, scrolling sideways when wide.
  - Image width/height from output metadata is honoured; images never exceed the page width.
- **Size limits.** Today files over 8 MB are cut to 8 MB, which would break a notebook's
  JSON, and notebooks with figures pass 8 MB easily. Notebooks are read whole up to 50 MB
  (Claude's call); beyond that the panel says the notebook is too large to preview and gives
  its size. Code cells over the existing 1 MB highlight limit are shown unhighlighted.
- **Look.** Same GitHub-style page. Roughly:

  ```
  # Analysis title                      ← markdown cell, full width

  Some text with typeset math x² + y².

  [1]: ┌───────────────────────────────┐
       │ import pandas as pd           │  ← code cell, highlighted
       │ df.describe()                 │
       └───────────────────────────────┘
  [1]:    | count | mean |              ← output, aligned under the code
          | 100   | 3.2  |

  [2]: ┌───────────────────────────────┐
       │ plt.plot(x, y)                │
       └───────────────────────────────┘
       [figure]
  ```

### Tests, examples, docs

- Unit tests for the math scanner (currency, escapes, code spans, underscores, display math)
  and for notebook rendering (each cell type, each output type, attachments, v3, malformed
  JSON, oversize).
- WebKit tests on a real WKWebView: KaTeX actually typesets; notebook code is highlighted;
  a script in an HTML output does not run; light/dark snapshots examined by eye.
- `examples/notebook.ipynb`: a real notebook, executed for real, covering the output types.
  `examples/showcase.md` gains a math section.
- README: features, the "Math and diagrams" limitation, the app size line, the "How it
  works" diagram, a notebook screenshot. Routing test and `gen_types.py` lists updated.

## Left to the builder

- How the math scanner is implemented and where its placeholders live.
- Module and file layout for the notebook renderer; CSS details.
- The type identifier for `.ipynb` and whether it is declared as imported or exported,
  decided by what actually routes on macOS 26.
- KaTeX version and options (trust stays off).
- Exact ANSI colour palette for light and dark.

## Order of work

Math first, then notebooks (notebooks depend on it). Each lands with its tests passing.
