# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run a single test (by name)
swift test --filter SVGPDFConverterTests/testMultiPageConversion
```

## Architecture

SVGPDFKit is a Swift Package (macOS 12+, Linux-compatible) that converts SVG files into multi-page PDF documents. It has one external dependency: [SwiftDraw](https://github.com/swhitty/SwiftDraw) for SVG parsing via CoreGraphics.

**Data flow:**

```
SVGSource (.fileURL | .data | .string)
    → resolveData()          — reads to raw SVG Data
    → PageNumberInjector      — optional regex rewrite of a <text id="..."> element
    → SwiftDraw.Image(data:)  — parse SVG
    → CGContext (PDF)         — aspect-fit + coordinate-flip into page rect
    → Data                   — PDF bytes returned to caller
```

**Key types:**

- `SVGPDFConverter` — main entry point; accepts `[SVGSource]` or a single source plus `ConversionOptions`
- `SVGSource` — input enum: `.fileURL(URL)`, `.data(Data)`, `.string(String)`
- `ConversionOptions` — page size, margin (pts), page number element ID, injection toggle, starting page number
- `PageSize` — points-based size with static presets (`.letter`, `.a4`, `.a3`, landscape variants)
- `PageNumberInjector` — internal namespace; rewrites `<text id="svgpdfkit-page-number">` text content before rendering
- `SVGPDFError` — typed errors for encoding failures, parse failures, missing file, no input, PDF context failure

## Tests

Tests are in `Tests/SVGPDFKitTests/`. Two files use XCTest (`SVGPDFConverterTests.swift`, `PageNumberInjectorTests.swift`); the third (`SVGPDFKitTests.swift`) is an empty Swift Testing stub.

`SVGPDFConverterTests` requires two SVG fixture files in `Tests/SVGPDFKitTests/Resources/`: `test-tune.svg` and `no-page-number.svg`. The `Resources/` directory currently exists but is empty, so those tests will fail without the fixtures.
