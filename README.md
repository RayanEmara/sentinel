# Sentinel

Sentinel is a *BLAZINGLY* fast markdown WYSIWYG editor with LaTeX support.

## Features
A lot of features ! Most don't work realiably yet.

- **Native TextKit 2 Rendering**: Relies on macOS 13+'s zero-allocation layout pipelines (`textViewportLayoutController.viewportRange`) for uncompromised typing performance even in 1,000+ line documents.
- **Dynamic Math Support (LaTeX)**: 
  - Uses [SwiftMath](https://github.com/mgriebling/SwiftMath) to compile and render inline (`$e^{i\pi} + 1 = 0$`) and display-mode (`$$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$$`) LaTeX.
- **Markdown Highlighting**: Dynamically transforms markdown bold (`**`), italic (`_`), headers (`#`), and unordered lists (`-`) into styled UI fonts, following obsidians implementation.
- **Stochastic crashing**: The app will randomly crash, this is a feature.


## Requirements

- macOS 13.0 or higher
- Swift 5.8+

## Building and Running

Sentinel is managed as a standard Swift Package Manager executable.

```bash
swift build
swift run
```

