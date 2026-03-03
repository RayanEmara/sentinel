# Sentinel

Sentinel is a fast, lightweight, and modern WYSIWYG Markdown editor for macOS built with Swift and TextKit 2. It features seamless, zero-friction editing by rendering Markdown elements—like bold text, headers, lists, and LaTeX math blocks—directly inline as you type, swapping them back to raw source code only when the cursor is positioned on them.

## Features

- **Blazing Fast WYSIWYG Engine**: Sentinel uses a highly optimized `NSAttributedString` replacement pipeline that directly injects formatted text attributes and `NSImage` attachments natively into the document as you scroll and type.
- **Native TextKit 2 Rendering**: Relies on macOS 13+'s zero-allocation layout pipelines (`textViewportLayoutController.viewportRange`) for uncompromised typing performance even in 1,000+ line documents.
- **Dynamic Math Support (LaTeX)**: 
  - Uses [SwiftMath](https://github.com/mgriebling/SwiftMath) to instantly compile inline (`$e^{i\pi} + 1 = 0$`) and display-mode (`$$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$$`) LaTeX into perfectly aligned template images perfectly colored by macOS UI themes.
- **Smart Paste Optimization**: Intercepts rich-text clipboard payloads (like HTML from Chrome) and forces a rapid plain-text downgrade so formatting never invisibly corrupts the editor.
- **Markdown Highlighting**: Dynamically transforms markdown bold (`**`), italic (`_`), headers (`#`), and unordered lists (`-`) into styled UI fonts. 

## Requirements

- macOS 13.0 or higher
- Swift 5.8+

## Building and Running

Sentinel is managed as a standard Swift Package Manager executable.

```bash
swift build
swift run
```

## Known Issues

- Off-screen rendering memory optimization is currently undergoing debugging. Fast scrolling on massive documents may induce memory surges or temporary engine UI application crashes.
