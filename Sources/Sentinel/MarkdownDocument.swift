import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}

/// Reference-based file document for `.md` files.
///
/// The `text` property is used ONLY for loading/saving.
/// During editing, the `NSTextView` is the sole source of truth —
/// we do NOT keep a duplicate of the full string in memory.
final class MarkdownDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] { [.markdownText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    typealias Snapshot = String

    /// Text loaded from disk. Cleared after handoff to the text view
    /// to avoid keeping a duplicate 24MB+ string in memory.
    @Published var text: String

    /// Incremented when a new file is loaded externally (Open/Revert).
    /// The coordinator compares this to know when to push to NSTextView.
    @Published var loadGeneration: Int = 0

    /// Weak reference to the live text view for saves.
    weak var liveTextView: NSTextView?

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> String {
        // We must extract the true source by examining the text storage's attributes
        // since the plaintext representation of the view strips out WYSIWYG syntax markers
        if let live = liveTextView {
            let textStorage: NSTextStorage
            if let contentManager = live.textLayoutManager?.textContentManager as? NSTextContentStorage,
               let storage = contentManager.textStorage {
                textStorage = storage
            } else {
                textStorage = live.textStorage ?? NSTextStorage()
            }
            
            guard textStorage.length > 0 else { return "" }
            
            var sourceText = ""
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            textStorage.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
                if let markdownSource = attrs[.markdownSource] as? String {
                    sourceText += markdownSource
                } else if let mathSource = attrs[.mathSource] as? String {
                    sourceText += mathSource
                } else {
                    let nsString = textStorage.string as NSString
                    sourceText += nsString.substring(with: range)
                }
            }
            return sourceText
        }
        return text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    /// Called by the coordinator after the text has been loaded into the
    /// text view. Releases the duplicate string from memory.
    func releaseLoadedText() {
        text = ""
    }
}
