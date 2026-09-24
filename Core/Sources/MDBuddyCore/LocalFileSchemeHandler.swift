import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves files from disk to the preview under `mdbuddy-local:///absolute/path`.
///
/// Using this scheme as the page's base URL lets relative references such as
/// `![](images/plot.png)` resolve to files beside the previewed document.
public final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "mdbuddy-local"
    /// Larger files (e.g. a video referenced from Markdown) are not served.
    static let maxBytes = 64 * 1024 * 1024

    /// Tasks WebKit cancelled; replying to them afterwards raises an exception. Main thread only.
    private var stoppedTasks = Set<ObjectIdentifier>()

    override public init() { super.init() }

    public static func url(for fileURL: URL, isDirectory: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.path = fileURL.standardizedFileURL.path + (isDirectory ? "/" : "")
        return components.url
    }

    public static func fileURL(from url: URL) -> URL? {
        guard url.scheme == scheme,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path,
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url, let fileURL = Self.fileURL(from: requestURL) else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= Self.maxBytes else {
                    throw URLError(.fileDoesNotExist)
                }
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": mime,
                                                              "Content-Length": String(data.count)])!
                DispatchQueue.main.async {
                    guard self.stoppedTasks.remove(ObjectIdentifier(task)) == nil else { return }
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.stoppedTasks.remove(ObjectIdentifier(task)) == nil else { return }
                    task.didFailWithError(error)
                }
            }
        }
    }

    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(task))
    }
}
