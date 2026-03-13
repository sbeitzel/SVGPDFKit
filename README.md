# SVGPDFKit

A Swift package that converts SVG documents into PDF files, with support for multi-page output and page number injection. Built on top of [SwiftDraw](https://github.com/swhitty/SwiftDraw), SVGPDFKit provides the PDF output layer that SwiftDraw doesn't.

Works on **macOS** and **Linux** (Swift 6.2+).

## Features

- Convert one or more SVG sources into a single multi-page PDF
- Accept SVGs from file URLs, `Data`, or strings
- Inject page numbers into a designated placeholder element before rendering
- Configurable page size (US Letter, A4, A3, landscape variants, or custom)
- Configurable margins
- `startingPageNumber` offset — personal binders can number pages independently of the canonical binder

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/SVGPDFKit.git", from: "0.1.0")
],
targets: [
    .target(name: "YourTarget", dependencies: ["SVGPDFKit"])
]
```

## Usage

### Basic — single SVG to PDF

```swift
import SVGPDFKit

let converter = SVGPDFConverter()
let pdfData = try converter.convert(source: .fileURL(svgURL))
try pdfData.write(to: outputURL)
```

### Multi-page — full binder

```swift
let sources = tuneSVGURLs.map { SVGSource.fileURL($0) }
let pdfData = try converter.convert(sources: sources)
```

### Personal binder with page number offset

The pipe major's canonical binder has 60 pages. A member playing only
5 specific tunes wants a binder where those tunes are numbered 1–5 (or
whatever pages they fall on within their personal selection):

```swift
var options = ConversionOptions()
options.startingPageNumber = 1  // or whatever page this member's binder starts on

let converter = SVGPDFConverter(options: options)
let pdfData = try converter.convert(sources: selectedSources)
```

### Page number placeholder convention

SVGPDFKit looks for a `<text>` element with `id="svgpdfkit-page-number"` in each
SVG and replaces its text content with the correct page number before rendering.
ABCKit (or any SVG producer) should emit this element wherever page numbers should appear:

```xml
<text id="svgpdfkit-page-number"
      x="306" y="780"
      font-size="10"
      text-anchor="middle"
      font-family="serif">0</text>
```

The `0` is a placeholder — SVGPDFKit replaces it at render time. If no such element
is present in the SVG, conversion proceeds normally without page numbers.

The element ID is configurable via `ConversionOptions.pageNumberElementID`.

## Options

```swift
var options = ConversionOptions()
options.pageSize = .a4               // default: .letter
options.margin = 36                  // points; default: 36 (0.5 inch)
options.startingPageNumber = 1       // default: 1
options.injectPageNumbers = true     // default: true
options.pageNumberElementID = "svgpdfkit-page-number"  // default
```

## Page Size Presets

| Preset | Dimensions |
|--------|-----------|
| `.letter` | 8.5 × 11 in (612 × 792 pt) |
| `.letterLandscape` | 11 × 8.5 in |
| `.a4` | 210 × 297 mm (595 × 842 pt) |
| `.a4Landscape` | 297 × 210 mm |
| `.a3` | 297 × 420 mm |
| `PageSize(width:height:)` | Custom, in points |

## License

MIT
