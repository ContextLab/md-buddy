# 2026-11-24: notebook (.ipynb) previews + typeset math

## Request
- "new feature: add support for ipynb notebooks"
- Then: `$…$` math must be typeset as LaTeX in *all* Markdown files, notebooks included.
- Fully rendered notebook: figures, formatted text, code highlighting, tables, outputs.
  Static only ("it's just a viewer").

## Decisions so far
- Math engine: KaTeX (Jeremy picked it over Temml and MathJax; app grows ~1 MB → ~2 MB).
- Notebook rendering in Swift (JSONSerialization), into the existing page shell.
- Order: math first, then notebooks.

## State
- Design doc: docs/superpowers/specs/2026-11-24-notebooks-and-math-design.md (uncommitted,
  awaiting a cold-read review, then Jeremy's approval).
- No product code written yet. Next after approval: implementation plan, then build.

## Findings
- `.ipynb` is in the "left to macOS" lists (scripts/gen_types.py RESERVED,
  RoutingTests.reserved) and has a dynamic type on this Mac, so today it gets no MD Buddy
  preview. Routing it is the first thing to verify for real in Finder.
- The 8 MB truncation in PreviewDocument would break notebook JSON; notebooks need their own
  size limit.
- CSP already allows `img-src data:` and `font-src data:` (base64 figures and KaTeX fonts OK).

## To verify during the build
- KaTeX sizes quoted in the design are from memory; measure when vendoring.
- Quick Look hands `.ipynb` to the extension once a type is declared (macOS 26).
