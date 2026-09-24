import UniformTypeIdentifiers
import XCTest
@testable import MDBuddyCore

/// Quick Look routes a file to an extension only when the file's type identifier appears
/// *exactly* in the extension's QLSupportedContentTypes (conformance is not enough).
/// This checks, on this Mac, that every extension MD Buddy knows how to render resolves
/// to a type we claim. Types come from LaunchServices, so the app must be installed.
final class RoutingTests: XCTestCase {
    /// Left to macOS: types it reserves for its own previewers (.ts, .txt, .html, ...), which no
    /// third-party extension receives, or previews better itself (.csv, .svg, .plist).
    /// See README "Limitations".
    static let reserved: Set<String> = ["ts", "mts", "txt", "text", "html", "htm", "xhtml", "svg", "plist", "",
                                        "csv", "tsv", "rtx", "out", "xml", "storyboard", "xib",
                                        "entitlements", "csproj", "vcxproj", "xsd", "xsl", "xslt", "rss",
                                        "atom", "scpt", "ipynb", "env"]

    func testEveryKnownExtensionIsClaimed() throws {
        let root = examplesDir.deletingLastPathComponent()
        let plist = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("PreviewExtension/Info.plist")))
        let attributes = try XCTUnwrap((plist["NSExtension"] as? NSDictionary)?["NSExtensionAttributes"] as? NSDictionary)
        let claimed = Set(try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String]))

        guard UTType("org.contextlab.mdbuddy.source") != nil else {
            throw XCTSkip("MD Buddy is not installed, so its imported types are not registered")
        }

        let extensions = Set(LanguageMap.byExtension.keys).union(DocumentKind.markdownExtensions)
            .union(DocumentKind.plainTextExtensions)
        var unclaimed: [String] = []
        for ext in extensions.sorted() where !Self.reserved.contains(ext) {
            guard let type = UTType(filenameExtension: ext) else { continue }
            if !claimed.contains(type.identifier) { unclaimed.append(".\(ext) → \(type.identifier)") }
        }
        XCTAssertTrue(unclaimed.isEmpty, "Not routed to MD Buddy:\n" + unclaimed.joined(separator: "\n"))
    }
}
