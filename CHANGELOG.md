# Changelog

All notable changes to SVGPDFKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[TOC]

---

## 0.1.1

### Fixed

- Updated `SwiftDraw` API usage: `SwiftDraw.Image` was renamed to `SwiftDraw.SVG`, and the draw call was updated from `image.draw(in:rect:)` to `context.draw(_:in:)` to match the current SwiftDraw API, restoring the build.

