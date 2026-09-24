# MD Buddy: build session (2026-09-23 → 24)

## Goal
Lightweight Quick Look preview extension for macOS Finder: Markdown (full GFM, raw HTML, images,
code highlighting); user later added plain-text and source-code files with highlighting.
Install, test via computer control, document with screenshots, make it easy to install.

## Status: ready for user review (installed at /Applications/MD Buddy.app)
- 36 tests pass (`make test`): renderer, decoding, WebKit page-script tests, routing test.
- Verified live in Finder (select + Space) via AppleScript/System Events: markdown, code, images, alerts.
- make install / make uninstall cycle verified.

## Architecture
- Core/ SwiftPM package: cmark-gfm (swift-cmark >= 0.9.0) → PreviewDocument (inline CSS/JS, CSP nonce).
  highlight.js 11.11.1 + 19 extra languages, included only when code is present.
- Extension: QLPreviewingController + WKWebView; mdbuddy-local: scheme serves sibling files;
  mdbuddy-remote: proxies remote images (fails in QL: no network) → JS placeholder chip.
- mdbuddy-render CLI: HTML / PNG / --eval / --list-types.

## Findings worth remembering
- QL routes by EXACT UTI in QLSupportedContentTypes (conformance ignored). gen_types.py derives
  imported types (App/Info.plist) + claimed ids (PreviewExtension/Info.plist) from LanguageMap.
- Reserved by macOS (observed on 26.6): .txt (system text preview), .ts/.mts (MPEG-2 video).
- QL extensions get no network even with network.client entitlement (tested: WebKit and URLSession both fail).
- suppressesIncrementalRendering + a hanging remote image = blank preview; removed.
- Xcode incremental builds can leave a stale seal on the SPM resource bundle → install.sh re-signs ad hoc.
- Xcode registers build/ copy with LaunchServices → duplicate entry in System Settings; install.sh unregisters it.
- User trashed QLMarkdown + Syntax Highlight; I unregistered their stale LaunchServices entries
  (lsregister -u on the Trash paths). Their UTIs (org.go.source etc.) vanished → added our own.
- qlmanage titles windows "[DEBUG] …"; README screenshots use real Finder panels (scripts/screenshots.sh).
- This Xcode 27 install prints CoreSimulator/CoreDevice plugin errors: needs `xcodebuild -runFirstLaunch` (not run).

## Possible follow-ups
- Thumbnail extension (Finder icons rendered from content).
- KaTeX math / Mermaid (would add ~300 KB–3 MB of JS; deliberately left out).

## 2026-09-24: code font size
- User asked for larger code text and whether a system preference exists.
- Only system pref: Cocoa NSFixedPitchFontSize (global domain, no Settings UI). AppKit registers a
  fallback of 11 in the registration domain, so UserDefaults.object(forKey:) returns 11 when unset;
  read persistentDomain(forName: globalDomain) instead (regression test added).
- Default code/plain-text size 14px (was 12.5/13px; markdown blocks were 85% of 15px). Pinch-zoom on.
- Verified live in Finder: default 21px rows (14px), NSFixedPitchFontSize=18 → 27px rows. Pref restored (deleted).
- install.sh/uninstall.sh now kill a running preview process (a stale one kept serving old code).
