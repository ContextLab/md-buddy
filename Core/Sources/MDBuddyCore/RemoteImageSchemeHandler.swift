import Foundation
import WebKit

/// Fetches remote images for the page from the host process.
///
/// Quick Look does not give WebKit's own processes network access, so `<img src="https://…">`
/// is rewritten to `mdbuddy-remote:https://…` (see `RemoteImages.rewrite`) and fetched here
/// with URLSession instead. Only images are served, and responses are size-limited.
public final class RemoteImageSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "mdbuddy-remote"
    static let maxBytes = 16 * 1024 * 1024

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpCookieStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    override public init() { super.init() }

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let remote = URL(string: String(url.absoluteString.dropFirst(Self.scheme.count + 1))),
              let scheme = remote.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let id = ObjectIdentifier(task)
        let dataTask = session.dataTask(with: remote) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.tasks.removeValue(forKey: id) != nil else { return }  // stopped
                guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      data.count <= Self.maxBytes else {
                    task.didFailWithError(error ?? URLError(.badServerResponse))
                    return
                }
                let mime = http.mimeType ?? "application/octet-stream"
                guard mime.hasPrefix("image/") else {
                    task.didFailWithError(URLError(.cannotDecodeContentData))
                    return
                }
                task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                headerFields: ["Content-Type": mime])!)
                task.didReceive(data)
                task.didFinish()
            }
        }
        tasks[id] = dataTask
        dataTask.resume()
    }

    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }
}

public enum RemoteImages {
    private static let pattern = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\bsrc\s*=\s*["'])(https?://)"#, options: [.caseInsensitive])

    /// Points remote `<img>` sources at `RemoteImageSchemeHandler`.
    public static func rewrite(_ html: String) -> String {
        guard html.range(of: "http", options: .caseInsensitive) != nil else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return pattern.stringByReplacingMatches(in: html, range: range,
                                                withTemplate: "$1\(RemoteImageSchemeHandler.scheme):$2")
    }
}
