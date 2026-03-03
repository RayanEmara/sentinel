import SwiftUI
import AppKit

@main
struct SentinelApp: App {

    init() {
        // When launched from `swift run`, the process has no Info.plist
        // so macOS treats it as a background app. Force it to be a regular
        // foreground app with its own menu bar and Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            MarkdownEditorView(document: file.document)
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandMenu("View") {
                Button("Zoom In") {
                    let current = UserDefaults.standard.double(forKey: "baseFontSize")
                    let val = current == 0 ? 15.0 : current
                    UserDefaults.standard.set(val + 2.0, forKey: "baseFontSize")
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Zoom Out") {
                    let current = UserDefaults.standard.double(forKey: "baseFontSize")
                    let val = current == 0 ? 15.0 : current
                    UserDefaults.standard.set(max(8.0, val - 2.0), forKey: "baseFontSize")
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Actual Size") {
                    UserDefaults.standard.set(15.0, forKey: "baseFontSize")
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
