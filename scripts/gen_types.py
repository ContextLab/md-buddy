#!/usr/bin/env python3
"""Regenerate the file types MD Buddy declares and claims, from Core's LanguageMap.

Quick Look routes a file to an extension only when the file's exact type identifier is
listed in QLSupportedContentTypes. This script asks macOS (via `mdbuddy-render --list-types`)
what each known extension resolves to and then:

* App/Info.plist            -- UTImportedTypeDeclarations for extensions with no declared
                               type (otherwise they get unroutable "dyn.*" identifiers);
* PreviewExtension/Info.plist -- QLSupportedContentTypes listing every identifier in use.

Run after changing LanguageMap, then reinstall and run the RoutingTests.
Usage: scripts/gen_types.py
"""
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OURS = "org.contextlab.mdbuddy."
MARKDOWN_ID = OURS + "markdown"
SOURCE_ID = OURS + "source"

# Left to macOS: types it reserves for its own previewers (.ts, .txt, .html, ...) or previews
# better itself (.csv tables, .svg, .plist). Keep in sync with RoutingTests.reserved.
RESERVED = {"ts", "mts", "txt", "text", "html", "htm", "xhtml", "svg", "plist", "", "csv", "tsv", "rtx",
            "out", "xml", "storyboard", "xib", "entitlements", "csproj", "vcxproj", "xsd", "xsl",
            "xslt", "rss", "atom", "scpt", "ipynb", "env"}

# Always claimed, whatever this Mac resolves: common identifiers other apps declare.
BASE_TYPES = [
    "net.daringfireball.markdown", MARKDOWN_ID, SOURCE_ID,
    "com.rstudio.rmarkdown", "org.quarto.qmarkdown",
    "public.plain-text", "public.source-code", "public.script", "public.shell-script",
    "public.log", "com.apple.log",
    "org.go.source", "org.rust-lang.rust", "org.julialang.julia", "com.microsoft.typescript",
]


def main() -> None:
    subprocess.run(["swift", "build", "-c", "release"], cwd=ROOT / "Core", check=True, capture_output=True)
    bin_dir = subprocess.run(["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT / "Core",
                             check=True, capture_output=True, text=True).stdout.strip()
    rows = subprocess.run([f"{bin_dir}/mdbuddy-render", "--list-types"], check=True,
                          capture_output=True, text=True).stdout.splitlines()

    markdown_exts, source_exts, claimed = [], [], list(BASE_TYPES)
    for row in rows:
        kind, ext, identifier, state = row.split("\t")
        if ext in RESERVED or ext == "md":
            continue
        if state == "dynamic" or identifier.startswith(OURS):
            (markdown_exts if kind == "markdown" else source_exts).append(ext)
        elif identifier not in claimed:
            claimed.append(identifier)

    def declaration(identifier, description, conforms, exts):
        return {"UTTypeIdentifier": identifier, "UTTypeDescription": description,
                "UTTypeConformsTo": conforms,
                "UTTypeTagSpecification": {"public.filename-extension": sorted(exts)}}

    app_plist = ROOT / "App" / "Info.plist"
    app = plistlib.loads(app_plist.read_bytes())
    app["UTImportedTypeDeclarations"] = [
        declaration(MARKDOWN_ID, "Markdown document", ["net.daringfireball.markdown", "public.plain-text"],
                    markdown_exts),
        declaration(SOURCE_ID, "Source code", ["public.source-code", "public.plain-text"], source_exts),
    ]
    app_plist.write_bytes(plistlib.dumps(app))

    ext_plist = ROOT / "PreviewExtension" / "Info.plist"
    ext = plistlib.loads(ext_plist.read_bytes())
    ext["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"] = claimed
    ext_plist.write_bytes(plistlib.dumps(ext))

    print(f"imported: {len(markdown_exts)} markdown + {len(source_exts)} source extensions; "
          f"claimed: {len(claimed)} type identifiers")


if __name__ == "__main__":
    main()
