# Changelog

All notable changes to SVGPDFKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[TOC]

---

## [Unreleased]

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

[Unreleased]: https://github.com/sbeitzel/SVGPDFKit/compare/0.2.0...HEAD
[0.2.0]: https://github.com/sbeitzel/SVGPDFKit/compare/0.1.1...0.2.0
