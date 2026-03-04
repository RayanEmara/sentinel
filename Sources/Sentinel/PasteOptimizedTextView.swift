import AppKit

/// Custom `NSTextView` subclass that optimizes large paste operations.
///
/// When a paste exceeds `pasteThreshold` characters, this view:
/// 1. Disables undo registration (avoids storing the full paste in the undo buffer)
/// 2. Batches the text insertion inside `beginEditing()`/`endEditing()`
/// 3. Temporarily suspends the rendering attributes validator
///
/// This prevents the UI from freezing during large pastes.
final class PasteOptimizedTextView: NSTextView {

    /// Pastes larger than this bypass undo and batch CoreText processing.
    private static let pasteThreshold = 4096

    override func paste(_ sender: Any?) {
        guard let pasteboard = NSPasteboard.general.string(forType: .string) else { return }
        
        if pasteboard.count <= Self.pasteThreshold {
            // Small paste — force plain text insertion using native handlers to inherit paragraph styles cleanly
            pasteAsPlainText(sender)
            return
        }

        // --- Large paste: optimize ---

        // 1. Disable undo for this operation (avoids huge undo buffer)
        let undoManager = self.undoManager
        undoManager?.disableUndoRegistration()

        // 2. Temporarily disable the rendering attributes validator
        let savedValidator = textLayoutManager?.renderingAttributesValidator
        textLayoutManager?.renderingAttributesValidator = nil

        // 3. Insert the text, replacing the current selection
        let insertionRange = selectedRange()
        if let textStorage = self.textContentStorage?.textStorage {
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: insertionRange, with: pasteboard)
            textStorage.endEditing()
        } else {
            // Fallback: use insertText
            insertText(pasteboard, replacementRange: insertionRange)
        }

        // 4. Move cursor to end of pasted text
        let newCursorPos = insertionRange.location + pasteboard.count
        setSelectedRange(NSRange(location: newCursorPos, length: 0))

        // 5. Restore undo and validator
        undoManager?.enableUndoRegistration()
        textLayoutManager?.renderingAttributesValidator = savedValidator

        // 6. Trigger a display refresh so visible text gets highlighted
        needsDisplay = true
    }

    // MARK: - Smart List Continuations

    override func insertNewline(_ sender: Any?) {
        guard let textStorage = self.textContentStorage?.textStorage else {
            super.insertNewline(sender)
            clearCenteredTypingAttributes()
            return
        }

        let cursorBefore = selectedRange().location
        let textBefore = textStorage.string as NSString
        guard cursorBefore > 0 else {
            super.insertNewline(sender)
            clearCenteredTypingAttributes()
            return
        }
        
        let previousCharIdx = cursorBefore - 1
        let lineRange = textBefore.lineRange(for: NSRange(location: previousCharIdx, length: 0))
        let line = textBefore.substring(with: lineRange)
        
        // Regex for unordered (*, -) and ordered (1., 2.) lists with leading spaces
        let listRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*]|\d+\.)[ \t]+"#)
        
        var matchPrefix: String? = nil
        var isEmptyItem = false
        var deleteLength = 0
        
        // 1. Check if the line has already been visually transformed into a bullet
        if lineRange.length > 0 {
            var effectiveRange = NSRange(location: 0, length: 0)
            if let source = textStorage.attribute(.markdownSource, at: lineRange.location, effectiveRange: &effectiveRange) as? String {
                if let match = listRegex.firstMatch(in: source, range: NSRange(location: 0, length: source.utf16.count)) {
                    matchPrefix = (source as NSString).substring(with: match.range)
                    let lineLengthWithoutNewlines = line.replacingOccurrences(of: "\n", with: "").utf16.count
                    
                    // If the visual element ONLY contains the bullet and whitespace
                    if lineLengthWithoutNewlines <= effectiveRange.length {
                        isEmptyItem = true
                        deleteLength = effectiveRange.length
                    }
                }
            }
        }
        
        // 2. Fallback to raw text matching if the cursor is near and it's physically raw text
        if matchPrefix == nil {
            if let match = listRegex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
                let prefix = (line as NSString).substring(with: match.range)
                matchPrefix = prefix
                
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine == prefix.trimmingCharacters(in: .whitespacesAndNewlines) {
                    isEmptyItem = true
                    deleteLength = prefix.utf16.count
                }
            }
        }
        
        // 3. Apply the results natively
        if let prefix = matchPrefix {
            let cleanPrefix = prefix.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            
            if isEmptyItem {
                // Break the list -> they hit enter twice. Let's delete the marker
                textStorage.beginEditing()
                let deleteRange = NSRange(location: lineRange.location, length: deleteLength)
                textStorage.replaceCharacters(in: deleteRange, with: "")
                textStorage.endEditing()
                
                // Fallback to inserting the standard \n
                super.insertNewline(sender)
                clearCenteredTypingAttributes()
                return 
            }
            
            // Continue list sequence natively
            super.insertNewline(sender)
            let newCursor = selectedRange().location
            insertText(cleanPrefix, replacementRange: NSRange(location: newCursor, length: 0))
            clearCenteredTypingAttributes()
            return
        }

        super.insertNewline(sender)
        clearCenteredTypingAttributes()
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        // Shift-Enter always performs a normal line break without list continuation
        super.insertNewline(sender)
        clearCenteredTypingAttributes()
    }
    
    private func clearCenteredTypingAttributes() {
        // NSTextView natively pulls the paragraph style of the preceding character when creating a new line.
        // If we hit enter at the end of a centered math block, the new empty line inherits that centering.
        // We intercept it immediately after the insertion and force the typing attributes back to default.
        var attrs = self.typingAttributes
        if let pStyle = attrs[.paragraphStyle] as? NSParagraphStyle, pStyle.alignment == .center {
            attrs[.paragraphStyle] = NSParagraphStyle.default
            self.typingAttributes = attrs
        }
    }

    override func pasteAsRichText(_ sender: Any?) {
        // Block explicitly requested rich text pastes too
        pasteAsPlainText(sender)
    }
}
