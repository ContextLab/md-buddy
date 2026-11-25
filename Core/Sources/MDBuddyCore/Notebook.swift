import Foundation

/// A Jupyter notebook, reduced to what a static preview shows.
///
/// Reads nbformat 4 and, best effort, nbformat 3 (cells under `worksheets`, older field
/// names). Notebook files in the wild are loose, so every field is optional: a missing
/// `source`, `outputs` or `metadata` is empty, and an unknown cell type is shown as raw text.
struct Notebook {
    /// The notebook's language as a highlight.js name; "python" when it does not say.
    let language: String
    let cells: [Cell]

    enum Cell {
        /// `attachments` maps a file name to its MIME bundle (MIME type → base64 data).
        case markdown(source: String, attachments: [String: [String: String]])
        case code(source: String, executionCount: Int?, outputs: [Output])
        case raw(source: String)
    }

    enum Output {
        /// `name` is "stdout" or "stderr".
        case stream(name: String, text: String)
        /// `display_data` and `execute_result`; only the latter has an execution count.
        case data(bundle: [String: Any], metadata: [String: Any], executionCount: Int?)
        case error(name: String, value: String, traceback: [String])
    }

    /// Returns nil when `data` is not a JSON object holding a list of cells (nbformat 4) or
    /// of worksheets (nbformat 3).
    static func parse(_ data: Data) -> Notebook? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let rawCells: [Any]
        if let cells = root["cells"] as? [Any] {
            rawCells = cells
        } else if let worksheets = root["worksheets"] as? [Any] {
            rawCells = worksheets.flatMap { ($0 as? [String: Any])?["cells"] as? [Any] ?? [] }
        } else {
            return nil
        }
        let metadata = root["metadata"] as? [String: Any] ?? [:]
        return Notebook(language: language(from: metadata),
                        cells: rawCells.compactMap { $0 as? [String: Any] }.map(cell))
    }

    /// A MIME value or source as text: a string as is, a list of strings joined.
    static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let lines = value as? [String] { return lines.joined() }
        return nil
    }

    private static func language(from metadata: [String: Any]) -> String {
        let named = (metadata["language_info"] as? [String: Any])?["name"] as? String
            ?? (metadata["kernelspec"] as? [String: Any])?["language"] as? String
        guard let name = named?.lowercased(), !name.isEmpty,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+#.-_".contains($0)) }) else {
            return "python"
        }
        switch name {
        case "ir": return "r"
        case "ipython", "ipython3", "python3": return "python"
        default: return name
        }
    }

    private static func cell(_ json: [String: Any]) -> Cell {
        // nbformat 3 keeps code in `input`.
        let source = text(json["source"]) ?? text(json["input"]) ?? ""
        switch json["cell_type"] as? String {
        case "markdown":
            var attachments: [String: [String: String]] = [:]
            for (name, bundle) in json["attachments"] as? [String: Any] ?? [:] {
                var entry: [String: String] = [:]
                for (mime, value) in bundle as? [String: Any] ?? [:] {
                    if let data = text(value) { entry[mime] = data }
                }
                attachments[name] = entry
            }
            return .markdown(source: source, attachments: attachments)
        case "heading":  // nbformat 3
            let level = min(max(json["level"] as? Int ?? 1, 1), 6)
            return .markdown(source: String(repeating: "#", count: level) + " " + source, attachments: [:])
        case "code":
            let count = json["execution_count"] as? Int ?? json["prompt_number"] as? Int
            let outputs = (json["outputs"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap(output)
            return .code(source: source, executionCount: count, outputs: outputs)
        default:
            return .raw(source: source)
        }
    }

    /// nbformat 3 output keys and the MIME types nbformat 4 uses for them.
    private static let legacyMimeTypes: [String: String] = [
        "text": "text/plain", "html": "text/html", "png": "image/png", "jpeg": "image/jpeg",
        "svg": "image/svg+xml", "latex": "text/latex", "json": "application/json",
        "javascript": "application/javascript", "pdf": "application/pdf",
    ]

    private static func output(_ json: [String: Any]) -> Output? {
        switch json["output_type"] as? String {
        case "stream":
            let name = json["name"] as? String ?? json["stream"] as? String ?? "stdout"
            return .stream(name: name == "stderr" ? "stderr" : "stdout", text: text(json["text"]) ?? "")
        case "error", "pyerr":
            return .error(name: json["ename"] as? String ?? "", value: json["evalue"] as? String ?? "",
                          traceback: json["traceback"] as? [String] ?? [])
        case "display_data", "execute_result", "pyout":
            var bundle = json["data"] as? [String: Any] ?? [:]
            if json["data"] == nil {  // nbformat 3: the bundle is spread over short keys
                for (key, mime) in legacyMimeTypes {
                    if let value = json[key] { bundle[mime] = value }
                }
            }
            return .data(bundle: bundle, metadata: json["metadata"] as? [String: Any] ?? [:],
                         executionCount: json["execution_count"] as? Int ?? json["prompt_number"] as? Int)
        default:
            return nil
        }
    }
}
