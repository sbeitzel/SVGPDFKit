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
- Configurable page size (US Letter, A4, A3, landscape variants, or custom), or one page size per
  page taken from each SVG — a mixed-orientation binder in one document, nothing scaled to fit
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
options.pageSize = .a4               // default: .letter; nil takes the page from each SVG
options.margin = 36                  // points; default: 36 (0.5 inch)
options.startingPageNumber = 1       // default: 1
options.injectPageNumbers = true     // default: true
options.pageNumberElementID = "svgpdfkit-page-number"  // default
options.subprocessTimeout = 120      // seconds; default: 120 (Linux only)
options.diagnosticHandler = .standardError             // default
```

`margin` is an inset on all four edges. Each page is scaled to fit inside what is
left of the page, preserving its aspect ratio, and centred in whatever slack the fit
leaves over — identically on macOS and Linux, so a PDF built on either platform puts
the same page in the same place. It does not apply when `pageSize` is `nil`; see
[Page size](#page-size).

`subprocessTimeout` bounds the `rsvg-convert` run that backs conversion on Linux. A
child that outlives it is sent `SIGTERM`, then `SIGKILL`, and the conversion throws
`SVGPDFError.rsvgConvertTimedOut` rather than blocking its caller. The CoreGraphics
path spawns no subprocess and ignores the setting.

`diagnosticHandler` is where non-fatal conditions go: a page-number placeholder that
was asked for and not found, and a page being scaled to fit a `pageSize` it was not
engraved for. See [Page number diagnostics](#page-number-diagnostics) and
[Page size](#page-size).

## Page size

`pageSize` has two modes.

**One size for the whole document** — `pageSize` is a `PageSize`. Every page is that
size, and each SVG is aspect-fitted inside it less `margin` and centred. This is the
default, `.letter`.

**One size per page, taken from the SVG** — `pageSize` is `nil`. Each page's media box
is the page its own SVG declares, and the document is rendered onto it at 1:1:

```swift
var options = ConversionOptions()
options.pageSize = nil
let result = try SVGPDFConverter(options: options).makePDF(sources: svgSources)
```

A binder of landscape and portrait tunes then comes out as a single PDF with landscape
and portrait pages, each at the size it was engraved, with nothing scaled to fit a size
the caller had to guess. `margin` does not apply in this mode: the SVG's own box *is*
the page, so there is nowhere to inset the content to without scaling it, and not
scaling it is the point. An SVG that wants margins should be engraved with them.

The size comes from the root `<svg>` element's `width` and `height`, converted to
points — `width="816px" height="1056px"` is a 612 × 792 pt page, because a CSS pixel is
1/96 inch and a point is 1/72. A document with no `width`/`height` falls back to the
extent of its `viewBox`, read as user units, and that fallback is reported as
`intrinsicPageSizeFromViewBox`, because a `viewBox` states a coordinate system rather
than a physical size: `viewBox="0 0 792 612"` becomes a 594 × 459 pt page, not 792 × 612.
A producer that means points should say so with a `width` and a `height`. A document
that declares neither throws `SVGPDFError.intrinsicPageSizeUnavailable`.

### Mismatch reporting

With an explicit `pageSize`, an SVG whose proportions differ from the page's is reported
to `diagnosticHandler` and carried in `ConversionResult.diagnostics`:

```
SVGPDFKit: page 4 — the SVG is 792 × 612 pt but the page is 612 × 792 pt; the content
was scaled to 68% to fit. Set ConversionOptions.pageSize = nil to give each page the
size its SVG declares.
```

Aspect-fitting a landscape page onto a portrait one is legal and silent, and the result
is music 32% smaller than it was engraved with five inches of blank paper underneath. It
takes measuring the PDF to notice, which is how
[SVPB/svpb-tools](https://github.com/SVPB/svpb-tools) shipped a season's binder that way
([#5](https://github.com/sbeitzel/SVGPDFKit/issues/5)). The comparison is against the
page rather than the page less its margins, with a 2% tolerance, so the ordinary case —
a letter document on a letter page inside 36pt margins — stays quiet.

```swift
for diagnostic in result.diagnostics {
    if case .pageSizeMismatch = diagnostic.kind { … }
}
```

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
| `nil` | Per page, from each SVG — see [Page size](#page-size) |

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
