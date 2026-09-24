import AppKit
import MDBuddyCore

/// mdbuddy-render — render a file the way the Quick Look extension does.
///
///   mdbuddy-render FILE                         print the generated HTML page
///   mdbuddy-render FILE --png OUT.png [options] save a snapshot
///       --width N          viewport width in points (default 860)
///       --height N         viewport height (default 900)
///       --full             capture the whole document height
///       --appearance light|dark
///   mdbuddy-render FILE --eval 'JS expression'  print the result of evaluating JS on the page
let usage = "usage: mdbuddy-render FILE [--png OUT.png [--width N] [--height N] [--full] [--appearance light|dark]] [--eval JS]"

var args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, !path.hasPrefix("-") else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
args.removeFirst()

var pngPath: String?
var evalScript: String?
var width: CGFloat = 860
var height: CGFloat = 900
var fullHeight = false
var appearance: NSAppearance.Name?
while !args.isEmpty {
    let flag = args.removeFirst()
    func value() -> String {
        guard !args.isEmpty else { FileHandle.standardError.write(Data("\(flag) needs a value\n".utf8)); exit(2) }
        return args.removeFirst()
    }
    switch flag {
    case "--png": pngPath = value()
    case "--eval": evalScript = value()
    case "--width": width = CGFloat(Double(value()) ?? 860)
    case "--height": height = CGFloat(Double(value()) ?? 900)
    case "--full": fullHeight = true
    case "--appearance": appearance = value() == "dark" ? .darkAqua : .aqua
    default:
        FileHandle.standardError.write(Data("unknown option \(flag)\n\(usage)\n".utf8))
        exit(2)
    }
}

let fileURL = URL(fileURLWithPath: path).standardizedFileURL

if pngPath == nil && evalScript == nil {
    do {
        let data = try Data(contentsOf: fileURL)
        print(PreviewDocument(fileName: fileURL.lastPathComponent, data: data).html)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

Task { @MainActor in
    do {
        let renderer = WebPageRenderer(width: width, height: height, appearance: appearance)
        _ = try await renderer.load(fileURL: fileURL)
        if let evalScript {
            let result = try await renderer.evaluate(evalScript)
            print(result.map { "\($0)" } ?? "null")
        }
        if let pngPath {
            // Give decoded images a moment to paint.
            try await Task.sleep(nanoseconds: 300_000_000)
            let image = try await renderer.snapshot(fullHeight: fullHeight)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: URL(fileURLWithPath: pngPath))
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}
app.run()
