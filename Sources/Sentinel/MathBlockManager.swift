import AppKit

extension NSAttributedString.Key {
    static let mathSource = NSAttributedString.Key("SentinelMathSource")
}

/// Manages Obsidian-style math block rendering:
/// - Cursor **outside** `$...$` → show rendered equation image
/// - Cursor **inside** `$...$` → show raw LaTeX source
final class MathBlockManager {

    var baseFontSize: CGFloat = 15.0
    private var isUpdating = false

    private static let mathRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\$\$([\s\S]+?)\$\$|\$([^\$\n]+?)\$"#,
            options: []
        )
    }()

    // MARK: - Public API

    func selectionDidChange(in textView: NSTextView) {
        guard !isUpdating else { return }

        // Access textStorage through the TextKit 2 content manager path
        guard let textStorage = getTextStorage(from: textView) else { return }

        isUpdating = true
        defer { isUpdating = false }

        let selectedRange = textView.selectedRange()

        // Phase 1: Revert any rendered attachments the cursor is touching
        revertAttachmentsNearCursor(selectedRange: selectedRange, textStorage: textStorage, textView: textView)

        // Phase 2: Render source-mode math blocks the cursor is NOT inside
        renderSourceBlocks(selectedRange: selectedRange, textStorage: textStorage, textView: textView)
    }

    func textDidChange() {
    }

    func forceReRenderAll(in textView: NSTextView) {
        guard let textStorage = getTextStorage(from: textView) else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var replacements: [(NSRange, NSAttributedString)] = []
        
        textStorage.enumerateAttribute(.mathSource, in: fullRange) { value, range, _ in
            guard let source = value as? String else { return }
            if textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil {
                let isInline = !source.hasPrefix("$$")
                let latex: String
                if source.hasPrefix("$$") && source.hasSuffix("$$") {
                    latex = String(source.dropFirst(2).dropLast(2))
                } else {
                    latex = String(source.dropFirst(1).dropLast(1))
                }
                
                let renderedFontSize = isInline ? baseFontSize : baseFontSize * 1.15
                guard let attachment = MathRenderer.attachment(for: latex, fontSize: renderedFontSize, inline: isInline) else { return }
                
                let attachmentString = NSMutableAttributedString(attachment: attachment)
                attachmentString.addAttribute(.mathSource, value: source, range: NSRange(location: 0, length: attachmentString.length))
                if !isInline {
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    paragraphStyle.paragraphSpacing = baseFontSize * 0.75
                    paragraphStyle.paragraphSpacingBefore = baseFontSize * 0.75
                    attachmentString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attachmentString.length))
                }
                replacements.append((range, attachmentString))
            }
        }
        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()
        let reversed = replacements.reversed()
        if !reversed.isEmpty {
            textStorage.beginEditing()
            for (range, attrString) in reversed {
                textStorage.replaceCharacters(in: range, with: attrString)
            }
            textStorage.endEditing()
        }
        undoManager?.enableUndoRegistration()
    }

    // MARK: - TextStorage Access

    private func getTextStorage(from textView: NSTextView) -> NSTextStorage? {
        // Try TextKit 2 path first (avoids forcing TextKit 1 fallback)
        if let contentManager = textView.textLayoutManager?.textContentManager as? NSTextContentStorage {
            return contentManager.textStorage
        }
        // Fallback to direct access
        return textView.textStorage
    }

    // MARK: - Phase 1: Revert Rendered → Source

    private func revertAttachmentsNearCursor(selectedRange: NSRange, textStorage: NSTextStorage, textView: NSTextView) {
        MemoryTracker.report(location: "MathBlockManager revertAttachmentsNearCursor start")
        let length = textStorage.length
        let cursorPos = selectedRange.location
        guard cursorPos <= length, length > 0, selectedRange.length == 0 else { return }

        let checkStart = max(0, cursorPos - 1)
        let checkEnd = min(cursorPos + 1, length)
        let checkRange = NSRange(location: checkStart, length: checkEnd - checkStart)
        guard checkRange.length > 0 else { return }

        var replacements: [(Int, String)] = []
        textStorage.enumerateAttribute(.mathSource, in: checkRange) { value, range, _ in
            guard let source = value as? String else { return }
            // Only revert if the cursor is actually touching that specific attachment
            if NSIntersectionRange(NSRange(location: cursorPos, length: 0), range).length > 0 ||
               cursorPos == range.location || cursorPos == NSMaxRange(range) {
                replacements.append((range.location, source))
            }
        }

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(10, baseFontSize - 1), weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]

        var newSelectionRange: NSRange? = nil

        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()

        let sorted = replacements.sorted(by: { $0.0 > $1.0 })
        if !sorted.isEmpty {
            textStorage.beginEditing()
            for (location, source) in sorted {
                let attrString = NSAttributedString(string: source, attributes: defaultAttributes)
                textStorage.replaceCharacters(
                    in: NSRange(location: location, length: 1),
                    with: attrString
                )

                // Check if the cursor was on or immediately adjacent to this attachment
                let attachmentRangeBeforeReversion = NSRange(location: location, length: 1)
                let touched = NSIntersectionRange(selectedRange, attachmentRangeBeforeReversion).length > 0 ||
                              selectedRange.location == location || selectedRange.location == location + 1

                if touched {
                    let prefixLen = source.hasPrefix("$$") ? 2 : 1
                    let suffixLen = source.hasSuffix("$$") ? 2 : 1
                    let innerLen = (source as NSString).length - prefixLen - suffixLen
                    if innerLen > 0 {
                        newSelectionRange = NSRange(location: location + prefixLen, length: innerLen)
                    }
                }
            }
            textStorage.endEditing()
        }

        undoManager?.enableUndoRegistration()
        
        if let targetRange = newSelectionRange {
            DispatchQueue.main.async {
                textView.setSelectedRange(targetRange)
            }
        }
        MemoryTracker.report(location: "MathBlockManager revertAttachmentsNearCursor end")
    }

    // MARK: - Phase 2: Render Source → Attachment

    private func renderSourceBlocks(selectedRange: NSRange, textStorage: NSTextStorage, textView: NSTextView) {
        MemoryTracker.report(location: "MathBlockManager renderSourceBlocks start")
        let nsString = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        
        // Scope our search to the visible rect if possible, plus a buffer
        var searchRange = fullRange
        if let textLayoutManager = textView.textLayoutManager,
           let contentManager = textLayoutManager.textContentManager,
           let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange {
           
            let startLoc = contentManager.offset(from: contentManager.documentRange.location, to: viewportRange.location)
            let length = contentManager.offset(from: viewportRange.location, to: viewportRange.endLocation)
            
            // In TextKit 2, extending the text range is simpler mathematically on integers.
            // We use a 4000-character symmetric buffer (~1.5 full screens of text on average)
            let buffer = 4000
            let start = max(0, startLoc - buffer)
            let end = min(fullRange.length, startLoc + length + buffer)
            searchRange = NSRange(location: start, length: end - start)
        }

        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()

        // Memory Culling: Un-render any math attachments that have completely scrolled off-screen
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(10, baseFontSize - 1), weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        
        var culledRanges: [(NSRange, NSAttributedString)] = []
        textStorage.enumerateAttribute(.mathSource, in: fullRange) { value, range, _ in
            guard let source = value as? String else { return }
            // If the block is completely outside the active search viewport...
            if NSIntersectionRange(searchRange, range).length == 0 {
                // ...and it is currently rendered as an active memory attachment
                if textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil {
                    let attrString = NSAttributedString(string: source, attributes: defaultAttributes)
                    culledRanges.append((range, attrString))
                }
            }
        }
        
        let sortedCulled = culledRanges.sorted(by: { $0.0.location > $1.0.location })
        if !sortedCulled.isEmpty {
            textStorage.beginEditing()
            for (range, attrString) in sortedCulled {
                textStorage.replaceCharacters(in: range, with: attrString)
            }
            textStorage.endEditing()
        }

        undoManager?.enableUndoRegistration()

        var matches: [(range: NSRange, latex: String, source: String)] = []

        Self.mathRegex.enumerateMatches(
            in: textStorage.string, options: [], range: searchRange
        ) { match, _, _ in
            guard let matchRange = match?.range else { return }

            if selectedRange.length == 0 {
                // Skip if cursor is inside or adjacent
                if selectedRange.location >= matchRange.location &&
                   selectedRange.location <= NSMaxRange(matchRange) { return }
            } else {
                // Skip if the broad selection intersects the math block
                if NSIntersectionRange(selectedRange, matchRange).length > 0 { return }
            }

            let source = nsString.substring(with: matchRange)
            let latex: String
            if source.hasPrefix("$$") && source.hasSuffix("$$") {
                latex = String(source.dropFirst(2).dropLast(2))
            } else {
                latex = String(source.dropFirst(1).dropLast(1))
            }

            guard !latex.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            matches.append((matchRange, latex, source))
        }

        undoManager?.disableUndoRegistration()

        // Pre-build replacement pairs, then apply in a single editing session
        var renderReplacements: [(NSRange, NSAttributedString)] = []
        for match in matches.reversed() {
            let isInline = !match.source.hasPrefix("$$")
            let renderedFontSize = isInline ? baseFontSize : baseFontSize * 1.15
            guard let attachment = MathRenderer.attachment(for: match.latex, fontSize: renderedFontSize, inline: isInline) else { continue }

            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttribute(.mathSource, value: match.source, range: NSRange(location: 0, length: attachmentString.length))

            if !isInline {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                paragraphStyle.paragraphSpacing = baseFontSize * 0.75
                paragraphStyle.paragraphSpacingBefore = baseFontSize * 0.75
                attachmentString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attachmentString.length))
            }

            renderReplacements.append((match.range, attachmentString))
        }

        if !renderReplacements.isEmpty {
            textStorage.beginEditing()
            for (range, attrString) in renderReplacements {
                textStorage.replaceCharacters(in: range, with: attrString)
            }
            textStorage.endEditing()
        }
        
        undoManager?.enableUndoRegistration()
        MemoryTracker.report(location: "MathBlockManager renderSourceBlocks end")
    }
}
