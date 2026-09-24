# MD Buddy: build session (2026-09-23)

## Goal
Lightweight Quick Look preview extension for macOS Finder: Markdown (full GFM, raw HTML, images,
code highlighting), later extended by the user to plain-text and source-code files with highlighting.
Install it, test it via computer control (screenshots), document it with screenshots, and make it easy to install.

## Architecture decisions
- Core/ = SwiftPM package MDBuddyCore: cmark-gfm (swiftlang/swift-cmark >= 0.9.0) -> HTML fragment,
  PreviewDocument builds a self-contained page (inline CSS/JS, CSP with nonce; tagfilter blocks <script>).
- highlight.js 11.11.1 (cdnjs, BSD-3) + 19 extra languages merged into highlight-extra.min.js.
  Only inlined when the page has code to highlight.
- Extension: view-based QLPreviewingController + WKWebView (JS needed for hljs); custom URL scheme
  `mdbuddy-local:` serves relative images from disk (the base URL is the file's directory).
- No signing identity on this machine -> ad-hoc signing.
- Syntax Highlight.app (claimed code types) was moved to the Trash by the user (flagged "unsafe").

## Status
- [x] Core renderer + 28 passing tests (swift test in Core/)
- [ ] Xcode project (xcodegen project.yml), host app, extension
- [ ] install script / Makefile, install, test with qlmanage + Finder
- [ ] screenshots, README, commit/push
