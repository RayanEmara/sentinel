import SwiftUI
import AppKit

/// Wraps `NSTextView` using **TextKit 2** (macOS 13+ default).
///
/// CRITICAL: Never access `textView.layoutManager` — that forces TextKit 1
/// fallback, which generates glyphs for the entire document.
struct MarkdownEditorView: NSViewRepresentable {

    @AppStorage("baseFontSize") private var baseFontSize: Double = 15.0
    @ObservedObject var document: MarkdownDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PasteOptimizedTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // ── Typography ──
        textView.font = .systemFont(ofSize: CGFloat(baseFontSize), weight: .regular)
        textView.textColor = .labelColor

        // ── Appearance ──
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        
        // Required so that NSTextAttachment (math) renders and typed text observes font sizing
        textView.isRichText = true
        
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // ── Text container ──
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 20, height: 20)

        // ── Delegate ──
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // ── Scroll view ──
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        
        // ── Scroll Tracking ──
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // ── Load initial text ──
        DispatchQueue.main.async {
            if !document.text.isEmpty {
                textView.string = document.text
                // Release the duplicate string from memory
                document.releaseLoadedText()
            }
            document.liveTextView = textView
            context.coordinator.lastLoadGeneration = document.loadGeneration
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Handle font size changes (zooming)
        let fontSize = CGFloat(baseFontSize)
        let didZoom = context.coordinator.markdownManager.baseFontSize != fontSize
        if didZoom {
            context.coordinator.markdownManager.baseFontSize = fontSize
            context.coordinator.mathManager.baseFontSize = fontSize
            textView.font = .systemFont(ofSize: fontSize, weight: .regular)
        }

        // Only push SwiftUI → NSTextView when a new file was loaded externally
        let currentGen = document.loadGeneration
        if currentGen != context.coordinator.lastLoadGeneration {
            context.coordinator.lastLoadGeneration = currentGen
            if !document.text.isEmpty {
                textView.string = document.text
                document.releaseLoadedText()
            }
        } else if didZoom {
            // Re-render all blocks with new font scaling
            context.coordinator.mathManager.forceReRenderAll(in: textView)
            context.coordinator.markdownManager.forceReRenderAll(in: textView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        weak var textView: NSTextView?
        let mathManager = MathBlockManager()
        let markdownManager = MarkdownBlockManager()
        var lastLoadGeneration: Int = -1
        private var scrollDebounceWorkItem: DispatchWorkItem?
        private var selectionDebounceWorkItem: DispatchWorkItem?

        init(document: MarkdownDocument) {
            self.document = document
        }
        
        @objc func boundsDidChange(_ notification: Notification) {
            MemoryTracker.report(location: "Coordinator.boundsDidChange scroll triggered")
            scrollDebounceWorkItem?.cancel()
            
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, let textView = self.textView else { return }
                MemoryTracker.report(location: "Coordinator.boundsDidChange dispatch tick start")
                self.mathManager.selectionDidChange(in: textView)
                self.markdownManager.selectionDidChange(in: textView)
                MemoryTracker.report(location: "Coordinator.boundsDidChange dispatch tick end")
            }
            
            scrollDebounceWorkItem = workItem
            // 100ms debounce: catches pauses in scrolling to render without burning battery over 120hz frame updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }

        func textDidChange(_ notification: Notification) {
            mathManager.textDidChange()
            markdownManager.textDidChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            selectionDebounceWorkItem?.cancel()
            
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.mathManager.selectionDidChange(in: textView)
                self.markdownManager.selectionDidChange(in: textView)
            }
            
            selectionDebounceWorkItem = workItem
            // Debounce click-drag and programmatic string replacements to prevent GCD spam
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }
    }
}
