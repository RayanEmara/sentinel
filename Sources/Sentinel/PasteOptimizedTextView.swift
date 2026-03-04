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

    // MARK: - Raw-Source Copy / Cut

    override func copy(_ sender: Any?) {
        guard let textStorage = self.textContentStorage?.textStorage else {
            super.copy(sender)
            return
        }

        let sel = selectedRange()
        guard sel.length > 0 else { super.copy(sender); return }

        // Walk the selected range and rebuild the string using raw source attributes
        var result = ""
        var i = sel.location
        let end = NSMaxRange(sel)

        while i < end {
            var effectiveRange = NSRange(location: 0, length: 0)

            // Math source (rendered as a single attachment character)
            if let mathSrc = textStorage.attribute(.mathSource, at: i, effectiveRange: &effectiveRange) as? String {
                let overlap = NSIntersectionRange(effectiveRange, sel)
                result += mathSrc
                i = NSMaxRange(overlap)
                continue
            }

            // Markdown source (bold, italic, header, list)
            if let mdSrc = textStorage.attribute(.markdownSource, at: i, effectiveRange: &effectiveRange) as? String {
                let overlap = NSIntersectionRange(effectiveRange, sel)
                result += mdSrc
                i = NSMaxRange(overlap)
                continue
            }

            // Plain text — take as-is
            let plainEnd = min(NSMaxRange(effectiveRange), end)
            let plainRange = NSRange(location: i, length: plainEnd - i)
            result += (textStorage.string as NSString).substring(with: plainRange)
            i = plainEnd
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result, forType: .string)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        deleteBackward(sender)
    }

    // MARK: - Formatting Shortcuts (Cmd+B / I / J / K)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift),
              !event.modifierFlags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "b": wrapWithDelimiter("**"); return true
        case "i": wrapWithDelimiter("*");  return true
        case "j": wrapWithDelimiter("$");  return true
        case "k": wrapWithDelimiter("$$"); return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }

    /// Toggles `delimiter` around the current selection or word under cursor.
    ///
    /// - Already wrapped → removes the delimiters (toggle OFF)
    /// - Not wrapped     → adds the delimiters   (toggle ON)
    ///
    /// For single-char delimiters (`*`, `$`) we verify the surrounding chars
    /// aren't part of the double-char variant (`**`, `$$`).
    private func wrapWithDelimiter(_ delimiter: String) {
        guard let textStorage = self.textContentStorage?.textStorage else { return }

        let sel = selectedRange()
        let nsString = textStorage.string as NSString
        let total = nsString.length
        let dLen = (delimiter as NSString).length        // delimiter length in UTF-16

        if sel.length > 0 {
            // --- Mode 1: Selection ---
            if isWrapped(nsString, start: sel.location, end: NSMaxRange(sel), delimiter: delimiter, total: total) {
                // UNWRAP — remove outer delimiters, keep inner text
                let fullRange = NSRange(location: sel.location - dLen, length: sel.length + dLen * 2)
                let inner = nsString.substring(with: sel)
                insertText(inner, replacementRange: fullRange)
                setSelectedRange(NSRange(location: sel.location - dLen, length: sel.length))
            } else {
                // WRAP
                let selected = nsString.substring(with: sel)
                let wrapped = delimiter + selected + delimiter
                insertText(wrapped, replacementRange: sel)
                let newPos = sel.location + wrapped.utf16.count
                setSelectedRange(NSRange(location: newPos, length: 0))
            }
            return
        }

        // --- Mode 2: Word under cursor ---
        let cursor = sel.location

        var wordStart = cursor
        while wordStart > 0 {
            let ch = nsString.character(at: wordStart - 1)
            guard let scalar = Unicode.Scalar(ch) else { break }
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                wordStart -= 1
            } else { break }
        }

        var wordEnd = cursor
        while wordEnd < total {
            let ch = nsString.character(at: wordEnd)
            guard let scalar = Unicode.Scalar(ch) else { break }
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                wordEnd += 1
            } else { break }
        }

        if wordStart < wordEnd {
            if isWrapped(nsString, start: wordStart, end: wordEnd, delimiter: delimiter, total: total) {
                // UNWRAP
                let fullRange = NSRange(location: wordStart - dLen, length: (wordEnd - wordStart) + dLen * 2)
                let word = nsString.substring(with: NSRange(location: wordStart, length: wordEnd - wordStart))
                insertText(word, replacementRange: fullRange)
                setSelectedRange(NSRange(location: max(0, cursor - dLen), length: 0))
            } else {
                // WRAP
                let wordRange = NSRange(location: wordStart, length: wordEnd - wordStart)
                let word = nsString.substring(with: wordRange)
                let wrapped = delimiter + word + delimiter
                insertText(wrapped, replacementRange: wordRange)
                setSelectedRange(NSRange(location: wordStart + wrapped.utf16.count, length: 0))
            }
        } else {
            // --- Mode 3: No word — insert empty delimiters ---
            let paired = delimiter + delimiter
            insertText(paired, replacementRange: sel)
            setSelectedRange(NSRange(location: cursor + dLen, length: 0))
        }
    }

    /// Returns `true` when the text region `[start, end)` is immediately
    /// surrounded by `delimiter` on both sides.
    ///
    /// For single-char delimiters (`*`, `$`) the check also verifies
    /// that no additional delimiter char sits just outside — which would
    /// indicate the double-char variant (`**`, `$$`) instead.
    private func isWrapped(_ nsString: NSString, start: Int, end: Int, delimiter: String, total: Int) -> Bool {
        let dLen = (delimiter as NSString).length
        guard start >= dLen, end + dLen <= total else { return false }

        let leading  = nsString.substring(with: NSRange(location: start - dLen, length: dLen))
        let trailing = nsString.substring(with: NSRange(location: end, length: dLen))
        guard leading == delimiter && trailing == delimiter else { return false }

        // Disambiguate single-char from double-char variants (* vs **, $ vs $$)
        if dLen == 1 {
            let extraBefore = (start - dLen - 1 >= 0)
                ? nsString.substring(with: NSRange(location: start - dLen - 1, length: 1))
                : ""
            let extraAfter = (end + dLen < total)
                ? nsString.substring(with: NSRange(location: end + dLen, length: 1))
                : ""
            if extraBefore == delimiter || extraAfter == delimiter { return false }
        }

        return true
    }

    // MARK: - Optimised Paste

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
