import AppKit

extension NSAttributedString.Key {
    static let markdownSource = NSAttributedString.Key("SentinelMarkdownSource")
}

/// Handles WYSIWYG rendering of Markdown syntax (Headers, Bold, Italic)
/// by physically replacing the syntax strings with perfectly styled
/// `NSAttributedString` objects containing a custom `.markdownSource` attribute.
/// When the cursor enters the range, it reverts to the raw text.
final class MarkdownBlockManager {

    private var isUpdating = false

    // Matches strings that should be formatted
    // Grabs the outer shell and the inner content.
    private static let headerRegex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#, options: [.anchorsMatchLines])
    private static let boldRegex = try! NSRegularExpression(pattern: #"(\*\*)(.+?)(\*\*)"#, options: [])
    private static let italicRegex = try! NSRegularExpression(pattern: #"((?<!\*)\*(?!\*)|(?<!_)_(?!_))(.+?)(\1)"#, options: [])
    private static let listPrefixRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*]|\d+\.)[ \t]+"#, options: [.anchorsMatchLines])

    var baseFontSize: CGFloat = 15.0
    private var baseFont: NSFont { NSFont.systemFont(ofSize: baseFontSize, weight: .regular) }

    func selectionDidChange(in textView: NSTextView) {
        guard !isUpdating else { return }
        guard let textStorage = getTextStorage(from: textView) else { return }

        isUpdating = true
        defer { isUpdating = false }

        let selectedRange = textView.selectedRange()

        // Phase 1: Revert ALL WYSIWYG blocks that the cursor is touching
        revertBlocksNearSelection(selectedRange, textStorage: textStorage, textView: textView)

        // Phase 2: Convert raw markdown into WYSIWYG blocks if cursor is away
        renderBlocks(selectedRange, textStorage: textStorage, textView: textView)
    }

    func textDidChange() {}

    func forceReRenderAll(in textView: NSTextView) {
        guard let textStorage = getTextStorage(from: textView) else { return }
        
        // REVERT ALL
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var reverts: [(NSRange, String)] = []
        textStorage.enumerateAttribute(.markdownSource, in: fullRange) { value, range, _ in
            // Must query effective range like we do for regular selection to get accurate bounds
            var effectiveRange = NSRange(location: 0, length: 0)
            if let source = textStorage.attribute(.markdownSource, at: range.location, effectiveRange: &effectiveRange) as? String {
                if !reverts.contains(where: { $0.0 == effectiveRange }) {
                    reverts.append((effectiveRange, source))
                }
            }
        }
        
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]
        
        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()
        
        for (range, source) in reverts.sorted(by: { $0.0.location > $1.0.location }) {
            textStorage.beginEditing()
            let attrString = NSAttributedString(string: source, attributes: defaultAttributes)
            textStorage.replaceCharacters(in: range, with: attrString)
            textStorage.endEditing()
        }
        
        undoManager?.enableUndoRegistration()
        
        // Re-render blocks with new font sizes
        renderBlocks(textView.selectedRange(), textStorage: textStorage, textView: textView)
    }

    private func getTextStorage(from textView: NSTextView) -> NSTextStorage? {
        if let contentManager = textView.textLayoutManager?.textContentManager as? NSTextContentStorage {
            return contentManager.textStorage
        }
        return textView.textStorage
    }

    // MARK: - Phase 1: Revert

    private func revertBlocksNearSelection(_ selectedRange: NSRange, textStorage: NSTextStorage, textView: NSTextView) {
        MemoryTracker.report(location: "MarkdownBlockManager revertBlocksNearSelection start")
        let length = textStorage.length
        guard length > 0, selectedRange.length == 0 else { return }

        // We search slightly around the cursor to catch immediately adjacent blocks
        let searchStart = max(0, selectedRange.location - 1)
        let searchEnd = min(length, NSMaxRange(selectedRange) + 1)
        let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)

        var replacements: [(NSRange, String)] = []
        
        // Find exact bounds of the custom attributes
        textStorage.enumerateAttribute(.markdownSource, in: searchRange) { value, range, _ in
            guard let source = value as? String else { return }
            
            // Re-query the exact effective range of this specific attribute value
            // in case the enumeration range was clipped
            var effectiveRange = NSRange(location: 0, length: 0)
            if textStorage.attribute(.markdownSource, at: range.location, effectiveRange: &effectiveRange) != nil {
                // Ensure we don't add duplicate ranges
                if !replacements.contains(where: { $0.0 == effectiveRange }) {
                    replacements.append((effectiveRange, source))
                }
            }
        }

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]

        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()

        // Traverse backwards so ranges don't shift
        for (range, source) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            textStorage.beginEditing()
            let attrString = NSAttributedString(string: source, attributes: defaultAttributes)
            textStorage.replaceCharacters(in: range, with: attrString)
            textStorage.endEditing()
        }
        
        undoManager?.enableUndoRegistration()
    }

    // MARK: - Phase 2: Render

    private func renderBlocks(_ selectedRange: NSRange, textStorage: NSTextStorage, textView: NSTextView) {
        MemoryTracker.report(location: "MarkdownBlockManager renderBlocks start")
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

        var replacements: [(NSRange, NSAttributedString)] = []

        func isTouching(_ range: NSRange) -> Bool {
            if selectedRange.length == 0 {
                return selectedRange.location >= range.location && selectedRange.location <= NSMaxRange(range)
            }
            // Broad text selections highlight over blocks; we shouldn't consider the highlighted block 'touched for editing'
            return false
        }

        // Pre-compute raw math bounds so we don't accidentally parse LaTeX underscores as italics
        // when the cursor is inside a math block (which reverts it to raw text without attributes)
        var precomputedMathRanges: [NSRange] = []
        let mathRegex = try! NSRegularExpression(pattern: #"\$\$([\s\S]+?)\$\$|\$([^\$\n]+?)\$"#, options: [])
        mathRegex.enumerateMatches(in: textStorage.string, options: [], range: searchRange) { match, _, _ in
            if let r = match?.range { precomputedMathRanges.append(r) }
        }

        func isMath(_ range: NSRange) -> Bool {
            // Check raw string bounds first
            for mathRange in precomputedMathRanges {
                if NSIntersectionRange(range, mathRange).length > 0 { return true }
            }

            var foundMath = false
            textStorage.enumerateAttribute(.mathSource, in: range) { value, _, stop in
                if value != nil {
                    foundMath = true
                    stop.pointee = true
                }
            }
            if foundMath { return true }
            textStorage.enumerateAttribute(.attachment, in: range) { value, _, stop in
                if value as? NSTextAttachment != nil {
                    foundMath = true
                    stop.pointee = true
                }
            }
            return foundMath
        }

        // 1. Find Headers
        Self.headerRegex.enumerateMatches(in: textStorage.string, options: [], range: searchRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }
            let mRange = match.range
            if isTouching(mRange) || isMath(mRange) { return }
            // Skip if it's already a markdownSource
            if textStorage.attribute(.markdownSource, at: mRange.location, effectiveRange: nil) != nil { return }

            let hashCount = match.range(at: 1).length
            let content = nsString.substring(with: match.range(at: 2))
            let source = nsString.substring(with: mRange)

            let size = max(baseFontSize, (baseFontSize * 2.0) - CGFloat(hashCount * 3))
            let font = NSFont.systemFont(ofSize: size, weight: .bold)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .markdownSource: source
            ]
            replacements.append((mRange, NSAttributedString(string: content, attributes: attrs)))
        }

        // 2. Find Bold
        Self.boldRegex.enumerateMatches(in: textStorage.string, options: [], range: searchRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            let mRange = match.range
            if isTouching(mRange) || isMath(mRange) { return }
            if textStorage.attribute(.markdownSource, at: mRange.location, effectiveRange: nil) != nil { return }

            let content = nsString.substring(with: match.range(at: 2))
            let source = nsString.substring(with: mRange)

            let font = NSFont.systemFont(ofSize: baseFontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .markdownSource: source
            ]
            replacements.append((mRange, NSAttributedString(string: content, attributes: attrs)))
        }

        // 3. Find Italic
        Self.italicRegex.enumerateMatches(in: textStorage.string, options: [], range: searchRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            let mRange = match.range
            if isTouching(mRange) || isMath(mRange) { return }
            if textStorage.attribute(.markdownSource, at: mRange.location, effectiveRange: nil) != nil { return }

            let content = nsString.substring(with: match.range(at: 2))
            let source = nsString.substring(with: mRange)

            let fontDesk = NSFont.systemFont(ofSize: baseFontSize, weight: .regular).fontDescriptor.withSymbolicTraits(.italic)
            let font = NSFont(descriptor: fontDesk, size: baseFontSize) ?? NSFont.systemFont(ofSize: baseFontSize, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .markdownSource: source
            ]
            replacements.append((mRange, NSAttributedString(string: content, attributes: attrs)))
        }

        // 4. Find Lists
        Self.listPrefixRegex.enumerateMatches(in: textStorage.string, options: [], range: searchRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }
            let mRange = match.range
            if isTouching(mRange) || isMath(mRange) { return }
            if textStorage.attribute(.markdownSource, at: mRange.location, effectiveRange: nil) != nil { return }

            let indent = nsString.substring(with: match.range(at: 1))
            let marker = nsString.substring(with: match.range(at: 2))
            
            // Keep the exact source of just the bullet + space
            let source = nsString.substring(with: mRange)

            let pStyle = NSMutableParagraphStyle()
            let indentWidth = CGFloat(indent.count) * 8.0 
            let bulletPadding: CGFloat = 20.0
            pStyle.firstLineHeadIndent = indentWidth
            pStyle.headIndent = indentWidth + bulletPadding
            pStyle.tabStops = [NSTextTab(textAlignment: .left, location: indentWidth + bulletPadding, options: [:])]

            let isUnordered = marker == "-" || marker == "*"
            let displayMarker = isUnordered ? "•" : marker
            // Map the indentation directly to visual width, strip duplicate visual spaces
            let displayString = "\(indent)\(displayMarker)\t"

            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .markdownSource: source,
                .paragraphStyle: pStyle
            ]
            replacements.append((mRange, NSAttributedString(string: displayString, attributes: attrs)))
        }

        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()

        // Apply replacements backwards
        for (range, attrString) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: range, with: attrString)
            textStorage.endEditing()
        }
        
        undoManager?.enableUndoRegistration()
    }
}
