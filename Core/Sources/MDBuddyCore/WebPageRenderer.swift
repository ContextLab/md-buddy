import AppKit
import WebKit

/// Loads a `PreviewDocument` into an off-screen WKWebView configured exactly like the
/// Quick Look extension's, so pages can be inspected (JavaScript) or snapshotted (PNG)
/// outside Quick Look. Used by the `mdbuddy-render` tool and the WebKit tests.
@MainActor
public final class WebPageRenderer: NSObject, WKNavigationDelegate {
    public let webView: WKWebView
    private let window: NSWindow
    private var continuation: CheckedContinuation<Void, Error>?

    public init(width: CGFloat = 860, height: CGFloat = 900, appearance: NSAppearance.Name? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        configuration.setURLSchemeHandler(RemoteImageSchemeHandler(), forURLScheme: RemoteImageSchemeHandler.scheme)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        if let appearance { webView.appearance = NSAppearance(named: appearance) }
        // WebKit only lays out and paints views that live in a window.
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads the document for `fileURL` and waits for the page (including images) to finish.
    public func load(fileURL: URL,
                     codeFontSize: Double = PreviewDocument.defaultCodeFontSize) async throws -> PreviewDocument {
        let data = try Data(contentsOf: fileURL)
        let document = PreviewDocument(fileName: fileURL.lastPathComponent, data: data, codeFontSize: codeFontSize)
        let base = LocalFileSchemeHandler.url(for: fileURL.deletingLastPathComponent(), isDirectory: true)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(document.html, baseURL: base)
        }
        return document
    }

    public func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    /// Captures the page. With `fullHeight`, the view is grown to the document's height first.
    public func snapshot(fullHeight: Bool) async throws -> NSImage {
        if fullHeight, let height = try await evaluate("document.documentElement.scrollHeight") as? Double {
            var frame = webView.frame
            frame.size.height = CGFloat(height)
            window.setContentSize(frame.size)
            webView.frame = frame
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        return try await webView.takeSnapshot(configuration: configuration)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
