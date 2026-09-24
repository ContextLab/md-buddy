import Cocoa
import MDBuddyCore
import QuickLookUI
import WebKit

/// Quick Look preview for Markdown, source code and plain text.
///
/// The document is converted to HTML natively (cmark-gfm) and shown in a WKWebView.
/// Relative URLs resolve against a custom `mdbuddy-local:` base URL so images next to
/// the file load straight from disk without being base64-inlined.
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var loadContinuation: CheckedContinuation<Void, Never>?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        configuration.setURLSchemeHandler(RemoteImageSchemeHandler(), forURLScheme: RemoteImageSchemeHandler.scheme)
        configuration.preferences.isElementFullscreenEnabled = false
        // Only our own nonce-tagged page script runs (enforced by the page's CSP).
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")  // avoid a white flash in dark mode
        view = webView
        preferredContentSize = NSSize(width: 860, height: 700)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let document = PreviewDocument(fileName: url.lastPathComponent, data: data)

        switch document.kind {
        case .markdown: preferredContentSize = NSSize(width: 860, height: 900)
        case .code, .plainText: preferredContentSize = NSSize(width: 900, height: 700)
        }

        let baseURL = LocalFileSchemeHandler.url(for: url.deletingLastPathComponent(), isDirectory: true)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadContinuation = continuation
            webView.loadHTMLString(document.html, baseURL: baseURL)
            // Never keep Quick Look waiting on a slow resource.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.finishLoading() }
        }
    }

    private func finishLoading() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoading() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let target = action.request.url else {
            decisionHandler(.allow)
            return
        }
        // In-page anchors (#heading, footnotes) scroll within the preview.
        if let current = webView.url, target.fragment != nil,
           target.absoluteString.hasPrefix(current.absoluteString.components(separatedBy: "#")[0] + "#") {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        // Everything else opens in its default app (browser, Mail, Finder, ...).
        if target.scheme == LocalFileSchemeHandler.scheme {
            if let fileURL = LocalFileSchemeHandler.fileURL(from: target) { NSWorkspace.shared.open(fileURL) }
        } else if let scheme = target.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(target)
        }
    }
}
