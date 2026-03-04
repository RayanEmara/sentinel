import SwiftUI
import AppKit

// MARK: - Focused Value for Cmd+F

private struct SearchPresentedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isSearchPresented: Binding<Bool>? {
        get { self[SearchPresentedKey.self] }
        set { self[SearchPresentedKey.self] = newValue }
    }
}

@main
struct SentinelApp: App {
    @FocusedValue(\.isSearchPresented) private var isSearchPresented

    init() {
        // When launched from `swift run`, the process has no Info.plist
        // so macOS treats it as a background app. Force it to be a regular
        // foreground app with its own menu bar and Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            SearchableEditorView(document: file.document)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            // Cmd+F → open toolbar search
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    isSearchPresented?.wrappedValue = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }

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

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Searchable Editor Wrapper

struct SearchableEditorView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchWorkItem: DispatchWorkItem?

    var body: some View {
        MarkdownEditorView(document: document)
            .searchable(text: $searchText, isPresented: $isSearching, placement: .toolbar, prompt: "Search")
            .focusedValue(\.isSearchPresented, $isSearching)
            .onSubmit(of: .search) {
                performSearch(searchText)
            }
            .onChange(of: searchText) {
                // Debounce incremental search to avoid per-keystroke full-document scans
                searchWorkItem?.cancel()
                let query = searchText
                let item = DispatchWorkItem { performSearch(query) }
                searchWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
            }
    }

    private func performSearch(_ query: String) {
        guard !query.isEmpty, let textView = document.liveTextView else { return }

        let content = textView.string
        let searchRange = NSRange(location: 0, length: content.utf16.count)
        let range = (content as NSString).range(of: query, options: [.caseInsensitive], range: searchRange)
        if range.location != NSNotFound {
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }
    }
}
