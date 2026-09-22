# Changelog

All notable changes to SVGPDFKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[TOC]

---

## [0.4.0]

### Added
- `ConversionOptions.pageSize` accepts `nil`, meaning "give each page the size its own SVG declares" ([#5](https://github.com/sbeitzel/SVGPDFKit/issues/5)). Each page's media box is then the page the document states for itself — its root `width`/`height` converted to points, or failing that its `viewBox` read as user units — and the SVG is rendered onto it at 1:1. A mixed-orientation binder is one conversion: landscape tunes get landscape pages and portrait tunes portrait ones, in one PDF, with nothing scaled to fit a size the caller had to guess. `margin` does not apply in this mode, because the SVG's own box *is* the page and insetting the content into it would mean scaling it.
- `SVGPDFDiagnostic.Kind.pageSizeMismatch(svg:page:scale:)`. With an explicit `pageSize`, an SVG whose proportions differ from the page's is now reported, with the scale the aspect-fit forced on it. The comparison is against the page rather than the page less its margins, with a 2% tolerance, so a letter document on a letter page inside 36pt margins stays quiet while a landscape page on a portrait one does not.
- `SVGPDFDiagnostic.Kind.intrinsicPageSizeFromViewBox(size:)`, reported when `pageSize` is `nil` and the document declared no `width`/`height`, so its page had to come from the `viewBox`. A `viewBox` is a coordinate system rather than a physical size, so its extent is read as user units, 96 to the inch — `viewBox="0 0 792 612"` is a 594 × 459 pt page, not 792 × 612 — which is what `rsvg-convert` does with the same document. A producer that means points should say so with a `width` and a `height`.
- `ConversionResult.diagnostics`, carrying every diagnostic the conversion emitted in order, for a caller who would rather inspect them afterwards than install a handler. `pagesMissingPageNumberPlaceholder` is still the slice of it that it always was.
- `SVGPDFError.intrinsicPageSizeUnavailable(page:)`, thrown when `pageSize` is `nil` and a document declares neither `width`/`height` nor a usable `viewBox`. A caller who asked for the SVG's own page and quietly got US Letter instead is the failure this whole change exists to end, so this throws rather than falling back.
- `PageSize` conforms to `Equatable`, `Hashable` and `CustomStringConvertible` (`"792 × 612 pt"`).

- `SVGPDFConverter.makePDF(source:)`, `makePDF(sources:)` and `makePDF(sources:to:)`, returning a new `ConversionResult`. Alongside the PDF, the result carries `pagesMissingPageNumberPlaceholder` — the pages where `injectPageNumbers` was asked for but no placeholder element was found — and `allPageNumbersInjected`. The reported values are page *numbers*, as assigned by `startingPageNumber`, not indices into the source array.
- `SVGPDFDiagnostic` and `DiagnosticHandler`, plus `ConversionOptions.diagnosticHandler` (default `.standardError`). Non-fatal conditions noticed during conversion are delivered here as they happen. `.silent` discards them; a custom handler routes them into a logger.

### Changed

- **Source-breaking:** `ConversionOptions.pageSize` is now `PageSize?` rather than `PageSize`. Assignment and the initializer are unaffected — `options.pageSize = .a4` and `ConversionOptions(pageSize: .a4)` both still compile, and the default is still `.letter`, so an existing conversion produces the same PDF it did before. Code that *reads* the property into a non-optional needs an unwrap.
- **Behavior change:** a page-number placeholder that `injectPageNumbers` asked for and did not find now writes a warning to stderr instead of passing silently ([#3](https://github.com/sbeitzel/SVGPDFKit/issues/3)). The conversion still succeeds — an SVG with no placeholder renders as-is, as before — but `startingPageNumber` can no longer be a setter that does nothing without saying so. That silence is how [SVPB/svpb-tools#19](https://github.com/SVPB/svpb-tools/issues/19) went unnoticed: every tune in an assembled binder restarted its footer at 1, with no throw, no warning and no log line. A mismatched or typo'd `pageNumberElementID` is now reported the same way, since from the converter's side it is the same thing.

  To suppress the warning, set `options.diagnosticHandler = .silent`. For SVGs that carry their own correct page numbers, `options.injectPageNumbers = false` is the better answer: it suppresses the search and the report together, and records the intent.

### Deprecated

- `convert(source:)`, `convert(sources:)` and `convert(sources:to:)`, in favour of the `makePDF` family. The old methods still work and still return `Data`; they simply cannot tell a caller that the page numbers they asked for were never injected. They will be removed in a future release. Migration is `try converter.convert(sources:)` → `try converter.makePDF(sources:).pdfData`.

### Fixed

- A document is no longer limited to one page size throughout ([#5](https://github.com/sbeitzel/SVGPDFKit/issues/5)). `pageSize` was hoisted out of the page loop and, on Linux, passed to `rsvg-convert` as one `--page-width`/`--page-height` pair covering every input, so a binder of landscape and portrait tunes could only be had by converting once per orientation and stitching the PDFs together with something else. The CoreGraphics backend now calls `beginPage(mediaBox:)` with the page resolved for that source, and the Linux backend, given no geometry arguments at all, lets `rsvg-convert` take each input's own declared size as that page's media box — so a mixed binder is still exactly one invocation and needs no PDF merge step.
- Guessing the page size wrong is no longer silent. Nothing consulted the SVG's intrinsic size, and both backends aspect-fit whatever arrived, so handing a `792 × 612` landscape page to `pageSize: .letter` scaled it by `540/792` and left the bottom five inches blank with no throw, no warning and no log line. That is how [SVPB/svpb-tools#62](https://github.com/SVPB/svpb-tools/issues/62) shipped a season's binder with every landscape tune at 68%. Both backends now read the document's own page and report the mismatch through `diagnosticHandler`.
- The page-number placeholder contract is no longer documented as ABCKit-specific. `pageNumberElementID` has always been configurable, so the contract is "emit a `<text>` element with the ID you configured"; ABCKit is one example producer rather than the definition. Corrected in `PageNumberInjector`, `ConversionOptions` and the README.
- The docs now state the limits of the match, which were previously left implicit: the element must be literally `<text>` (the ID is configurable, the element name is not), and its content must be plain text, so a `<text>` wrapping a `<tspan>` will not match. Text that a renderer has converted to path geometry leaves no `<text>` element at all and cannot be reached under any ID — a consumer in that position wants the number correct at engrave time and should set `injectPageNumbers = false`.

---

## [0.3.0]

### Fixed

- Linux: `convert` could hang indefinitely after `rsvg-convert` had already exited successfully and written a complete PDF ([#1](https://github.com/sbeitzel/SVGPDFKit/issues/1)). The subprocess is now spawned with `posix_spawn` and waited on with `waitpid`, instead of Foundation's `Process`, whose `waitUntilExit()` polls `RunLoop.run(mode:before:)`. That deadline is not enforced on hosts where `clock_getres(CLOCK_MONOTONIC)` is coarser than 1 ns — notably Docker Desktop's VM kernel, which reports 1 ms — because `CFDate.c` derives its timebase from that resolution ([swift-corelibs-foundation#5485](https://github.com/swiftlang/swift-corelibs-foundation/pull/5485), fixed upstream but not in the 6.3 or 6.4 release branches). Waiting on our own child with `waitpid` does not involve a `RunLoop` at all.
- Linux: an `rsvg-convert` run that wrote more than the pipe buffer (~64 KB) to stderr could deadlock, because nothing drained the pipe while the parent waited for the child to exit. Captured stderr now goes to a temporary file, which has no capacity limit. Long stderr is truncated in the resulting error message.

### Added

- `ConversionOptions.subprocessTimeout` (default 120 seconds): a stalled `rsvg-convert` is now sent `SIGTERM`, then `SIGKILL`, and the conversion fails instead of blocking its caller forever. Linux only; the CoreGraphics path spawns no subprocess.
- New `SVGPDFError` cases `rsvgConvertTimedOut(seconds:)` and `rsvgConvertLaunchFailed(reason:)`.

---

## [0.2.0]

### Added

- Linux support via `rsvg-convert` subprocess. On Linux (where CoreGraphics is unavailable), `SVGPDFConverter` shells out to `rsvg-convert --format=pdf` to produce the PDF. The macOS CoreGraphics path is unchanged.
- New `SVGPDFError.rsvgConvertFailed(exitCode:stderr:)` case for Linux subprocess failures.

### Changed

- `PageSize.width` and `PageSize.height` are now `Double` instead of `CGFloat` (`CGFloat` is `typealias CGFloat = Double` on all supported Apple platforms, so this is source-compatible).
- `ConversionOptions.margin` is now `Double` instead of `CGFloat` (same reasoning).
- `PageSize.cgRect` is now conditionally compiled (`#if canImport(CoreGraphics)`) and unavailable on Linux.

---

## 0.1.1

### Fixed

- Updated `SwiftDraw` API usage: `SwiftDraw.Image` was renamed to `SwiftDraw.SVG`, and the draw call was updated from `image.draw(in:rect:)` to `context.draw(_:in:)` to match the current SwiftDraw API, restoring the build.

[0.3.0]: https://github.com/sbeitzel/SVGPDFKit/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/sbeitzel/SVGPDFKit/compare/0.1.1...0.2.0
