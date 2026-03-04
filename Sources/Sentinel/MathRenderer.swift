import AppKit
import SwiftMath

class MathTextAttachmentCell: NSTextAttachmentCell {
    var customBaselineOffset: NSPoint = .zero
    override func cellBaselineOffset() -> NSPoint {
        return customBaselineOffset
    }
    
    // Disable interactive tracking so that clicks fall through to the NSTextView 
    // and naturally move the text cursor, triggering our selection logic.
    override func wantsToTrackMouse() -> Bool {
        return false
    }
    
    override func wantsToTrackMouse(for theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int) -> Bool {
        return false
    }
    
    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        return false
    }
}

/// Renders a LaTeX string into an `NSImage` using SwiftMath.
enum MathRenderer {

    private static let oversetRegex = try! NSRegularExpression(pattern: #"\\overset\{[^\}]*\}\{([^\}]*)\}"#, options: [])

    private static func preprocessLaTeX(_ latex: String) -> String {
        var processed = latex
        // SwiftMath is extremely strict and lacks generic negation commands
        processed = processed.replacingOccurrences(of: "\\centernot\\iff", with: "\\neq ")
        processed = processed.replacingOccurrences(of: "\\centernot", with: "\\neq ")
        processed = processed.replacingOccurrences(of: "\\not \\geq", with: "< ")
        processed = processed.replacingOccurrences(of: "\\not\\geq", with: "< ")
        processed = processed.replacingOccurrences(of: "\\not", with: "\\neq ")
        
        // SwiftMath lacks \overset support. Regex strip \overset{A}{B} -> B
        processed = oversetRegex.stringByReplacingMatches(
            in: processed,
            range: NSRange(processed.startIndex..., in: processed),
            withTemplate: "$1"
        )
        
        // SwiftMath prefers standard pipe symbol for lvert/rvert delimiters
        processed = processed.replacingOccurrences(of: "\\left\\lvert", with: "\\left|")
        processed = processed.replacingOccurrences(of: "\\right\\rvert", with: "\\right|")
        processed = processed.replacingOccurrences(of: "\\lvert", with: "|")
        processed = processed.replacingOccurrences(of: "\\rvert", with: "|")
        return processed
    }

    static func render(latex: String, fontSize: CGFloat = 16, inline: Bool = false) -> (image: NSImage, descent: CGFloat)? {
        let label = MTMathUILabel()
        label.latex = preprocessLaTeX(latex)
        label.fontSize = fontSize
        label.textColor = .labelColor
        label.labelMode = inline ? .text : .display
        label.contentInsets = MTEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

        // Force layout so the math list is built
        label.frame = CGRect(origin: .zero, size: CGSize(width: 1000, height: 1000))
        label.layout()   // Triggers _layoutSubviews → builds the display list

        // On macOS, SwiftMath overrides `fittingSize`, NOT `intrinsicContentSize`
        let size = label.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }

        // Resize to the exact fitting size, re-layout, then render
        label.frame = CGRect(origin: .zero, size: size)
        label.layout()

        guard let bitmapRep = label.bitmapImageRepForCachingDisplay(in: label.bounds) else { return nil }
        label.cacheDisplay(in: label.bounds, to: bitmapRep)

        let image = NSImage(size: size)
        image.addRepresentation(bitmapRep)
        image.isTemplate = true
        
        // The exact natural descent seems to be the sweet spot. 
        // 0.75x was slightly too high, and +2 padding was too low.
        let descent = label.displayList?.descent ?? 0
        return (image, descent)
    }

    static func attachment(for latex: String, fontSize: CGFloat = 16, inline: Bool = false) -> NSTextAttachment? {
        guard let result = render(latex: latex, fontSize: fontSize, inline: inline) else { return nil }

        let attachment = NSTextAttachment()
        let cell = MathTextAttachmentCell(imageCell: result.image)
        
        // Push the image down by its typographic descent so it aligns with text baseline
        cell.customBaselineOffset = NSPoint(x: 0, y: -result.descent)
        attachment.attachmentCell = cell
        
        attachment.bounds = CGRect(
            x: 0,
            y: -result.descent,
            width: result.image.size.width,
            height: result.image.size.height
        )
        return attachment
    }
}
