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
    → SVGPageComposer         — Linux only; rewrites the page to carry its own placement
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
- `SVGPageComposer` — internal namespace; owns page placement. `fitRect` is the aspect-fit-and-centre arithmetic *both* backends use. `compose` is the Linux half: rsvg-convert sizes its drawing box but always fits to the top-left of it, and one invocation renders every input with one set of arguments, so offsets cannot be passed per page — instead each document is wrapped in a page-sized root `<svg>` with the original as a nested viewport at its fitted rect (issue #4)
- `RsvgSubprocess` — internal, Linux only; runs `rsvg-convert` via `posix_spawn`/`waitpid` with a timeout. Foundation's `Process` is deliberately avoided: its `waitUntilExit()` relies on `RunLoop` deadlines, which are never enforced on hosts reporting a coarse `clock_getres(CLOCK_MONOTONIC)` (e.g. Docker Desktop), so it can block forever after the child has exited (issue #1)
- `SVGPDFError` — typed errors for encoding failures, parse failures, missing file, no input, PDF context failure

## Tests

Tests are in `Tests/SVGPDFKitTests/`, all XCTest: `SVGPDFConverterTests.swift`, `PageNumberInjectorTests.swift`, `SVGPageComposerTests.swift`, and `RsvgSubprocessTests.swift` (Linux only — the file compiles to nothing where CoreGraphics exists).

`Tests/SVGPDFKitTests/Resources/` holds the fixtures: `hanas_wedding.abc` is the source tune, and `test-tune.svg` / `no-page-number.svg` are engraved from it by `Scripts/make-fixtures.sh` (needs `abcm2ps`) — one with the page-number placeholder ABCKit emits, one without. The script normalizes abcm2ps's date stamps, so regenerating an unchanged tune produces no diff.

`swift test` hangs partway through in Linux containers on Docker Desktop; that is a Foundation bug, not this package's. See the README for `Scripts/fineres.c`, which works around it.
