# Changelog

All notable changes to SVGPDFKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[TOC]

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

[0.2.0]: https://github.com/sbeitzel/SVGPDFKit/compare/0.1.1...0.2.0
