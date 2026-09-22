# SVGPDFKit

A Swift package that converts SVG documents into PDF files, with support for multi-page output and page number injection. Built on top of [SwiftDraw](https://github.com/swhitty/SwiftDraw), SVGPDFKit provides the PDF output layer that SwiftDraw doesn't.

Works on **macOS** and **Linux** (Swift 6.2+).

> **Linux requirement:** On Linux, SVGPDFKit uses `rsvg-convert` (from the `librsvg` package) to render SVGs. Install it before use:
> ```sh
> # Debian/Ubuntu
> sudo apt-get install librsvg2-bin
>
> # Fedora/RHEL
> sudo dnf install librsvg2-tools
> ```

## Features

- Convert one or more SVG sources into a single multi-page PDF
- Accept SVGs from file URLs, `Data`, or strings
- Inject page numbers into a designated placeholder element before rendering, and report the pages where no placeholder was found
- Configurable page size (US Letter, A4, A3, landscape variants, or custom)
- Configurable margins
- `startingPageNumber` offset — personal binders can number pages independently of the canonical binder

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/SVGPDFKit.git", from: "0.4.0")
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
let result = try converter.makePDF(source: .fileURL(svgURL))
try result.pdfData.write(to: outputURL)
```

`makePDF` returns a `ConversionResult`: the PDF, plus the pages whose page-number
placeholder was not found. See [Page number diagnostics](#page-number-diagnostics).

### Multi-page — full binder

```swift
let sources = tuneSVGURLs.map { SVGSource.fileURL($0) }
let result = try converter.makePDF(sources: sources)
try result.pdfData.write(to: outputURL)
```

Or write straight to disk, which reports the same way:

```swift
try converter.makePDF(sources: sources, to: outputURL)
```

### Personal binder with page number offset

The pipe major's canonical binder has 60 pages. A member playing only
5 specific tunes wants a binder where those tunes are numbered 1–5 (or
whatever pages they fall on within their personal selection):

```swift
var options = ConversionOptions()
options.startingPageNumber = 1  // or whatever page this member's binder starts on

let converter = SVGPDFConverter(options: options)
let result = try converter.makePDF(sources: selectedSources)
try result.pdfData.write(to: outputURL)
```

### Page number placeholder convention

The contract is producer-agnostic: whatever renders the SVG emits a `<text>` element
carrying the ID that `ConversionOptions.pageNumberElementID` names, wherever the page
number should appear, and SVGPDFKit replaces its content at render time.

```xml
<text id="svgpdfkit-page-number"
      x="306" y="780"
      font-size="10"
      text-anchor="middle"
      font-family="serif">0</text>
```

The `0` is a placeholder — SVGPDFKit replaces it at render time. ABCKit emits the
default ID, `svgpdfkit-page-number`; any other producer that controls its own SVG
output can adopt the contract by pointing `pageNumberElementID` at the ID it emits.

#### Limits

The ID is configurable. The element name and the shape of its content are not.

- **The element must be literally `<text>`.** A marker on any other element — a
  `<g id="…">` wrapper, say — will not be found under any ID.
- **Its content must be plain text.** A `<text>` that wraps a `<tspan>` will not
  match, because the match stops at the first `<`.
- **Outlined text cannot be reached at all.** A renderer that converts glyphs to path
  geometry emits no `<text>` element, so no ID will find one. A consumer in that
  position wants the number correct when the page is engraved — CeolKit's
  `%%ceolkit:pagenumber`, for instance — and should set `injectPageNumbers = false`
  to say so.

### Page number diagnostics

A placeholder that is not found does not fail the conversion — the page renders with
whatever number, or none, the source SVG already carried. But it is not silent either,
because a `startingPageNumber` that quietly does nothing is worse than a loud one
([#3](https://github.com/sbeitzel/SVGPDFKit/issues/3)). Every miss is reported twice:

```swift
let result = try converter.makePDF(sources: sources)

if !result.allPageNumbersInjected {
    print("no placeholder on pages \(result.pagesMissingPageNumberPlaceholder)")
}
```

`pagesMissingPageNumberPlaceholder` holds page *numbers*, as assigned by
`startingPageNumber` — not indices into `sources`. A mismatched or typo'd
`pageNumberElementID` is reported the same way as a missing placeholder, since from
here they are the same thing.

Independently, each miss goes to `ConversionOptions.diagnosticHandler`, which by
default writes one line per page to stderr:

```
SVGPDFKit: page 1 — no element with id="svgpdfkit-page-number"; page number not injected
```

```swift
options.diagnosticHandler = .silent                            // say nothing
options.diagnosticHandler = .init { logger.warning("\($0)") }  // route elsewhere
```

For SVGs that carry their own correct page numbers, `injectPageNumbers = false` is the
better answer than silencing the handler: it suppresses the search and the report
together, and records the intent.

## Options

```swift
var options = ConversionOptions()
options.pageSize = .a4               // default: .letter
options.margin = 36                  // points; default: 36 (0.5 inch)
options.startingPageNumber = 1       // default: 1
options.injectPageNumbers = true     // default: true
options.pageNumberElementID = "svgpdfkit-page-number"  // default
options.subprocessTimeout = 120      // seconds; default: 120 (Linux only)
options.diagnosticHandler = .standardError             // default
```

`subprocessTimeout` bounds the `rsvg-convert` run that backs conversion on Linux. A
child that outlives it is sent `SIGTERM`, then `SIGKILL`, and the conversion throws
`SVGPDFError.rsvgConvertTimedOut` rather than blocking its caller. The CoreGraphics
path spawns no subprocess and ignores the setting.

`diagnosticHandler` is where non-fatal conditions go — currently, a page-number
placeholder that was asked for and not found. See
[Page number diagnostics](#page-number-diagnostics).

## Deprecations

`convert(source:)`, `convert(sources:)` and `convert(sources:to:)` are deprecated as of
0.4.0 in favour of `makePDF(source:)`, `makePDF(sources:)` and `makePDF(sources:to:)`.
The old methods still work and still return `Data`; they just cannot tell a caller that
the page numbers they asked for were never injected. They will be removed in a future
release.

```swift
// before
let pdfData = try converter.convert(sources: sources)

// after
let pdfData = try converter.makePDF(sources: sources).pdfData
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

## Testing on Linux under Docker Desktop

`swift test` hangs unpredictably in Linux containers on Docker Desktop for Mac — usually
partway through a suite, in XCTest's teardown. That is a Foundation bug, not a SVGPDFKit
one: Docker Desktop's VM kernel reports a 1 ms `CLOCK_MONOTONIC` resolution, which corrupts
CoreFoundation's timebase and leaves every `RunLoop` deadline unenforced, so any wait built
on one blocks forever. It is [fixed upstream](https://github.com/swiftlang/swift-corelibs-foundation/pull/5485)
but not in a released toolchain yet.

`Scripts/fineres.c` works around it until then:

```bash
clang -shared -fPIC -o /tmp/fineres.so Scripts/fineres.c
LD_PRELOAD=/tmp/fineres.so swift test
```

Native Linux hosts (CI runners, cloud VMs, bare metal) report a 1 ns resolution and are
unaffected, so this is only needed for local container testing.

## License

MIT
