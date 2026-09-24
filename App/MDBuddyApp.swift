import SwiftUI

/// The host app exists only to carry the Quick Look extension. Launching it once
/// registers the extension; after that it never needs to run again.
@main
struct MDBuddyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .frame(width: 520)
                .fixedSize()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("MD Buddy")
                .font(.system(size: 26, weight: .semibold))
            Text("Quick Look previews for Markdown, source code and plain text.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                step("1", "Select a .md, code or text file in Finder.")
                step("2", "Press Space to preview it.")
                step("3", "If previews don't appear, make sure MD Buddy is switched on under System Settings › General › Login Items & Extensions › Quick Look.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Open Extension Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!
                    NSWorkspace.shared.open(url)
                }
                Spacer()
                Button("Done") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
