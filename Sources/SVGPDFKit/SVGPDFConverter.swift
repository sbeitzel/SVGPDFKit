import Foundation

/// Converts one or more SVG sources into a single multi-page PDF document.
///
/// Basic usage — canonical binder (all pages, numbered from 1):
/// ```swift
/// let converter = SVGPDFConverter()
/// let result = try converter.makePDF(sources: svgSources)
/// try result.pdfData.write(to: outputURL)
/// ```
///
/// Personal binder — subset of tunes, page numbers offset to match
/// position within the member's custom binder:
/// ```swift
/// var options = ConversionOptions()
/// options.startingPageNumber = 5   // this member's binder starts at page 5
/// let converter = SVGPDFConverter(options: options)
/// let result = try converter.makePDF(sources: selectedSVGs)
/// ```
///
/// Asking for page numbers is not the same as getting them: an SVG that carries
/// no placeholder cannot be stamped. That is reported rather than thrown, so
/// check the result when it matters:
/// ```swift
/// if !result.allPageNumbersInjected {
///     print("no placeholder on pages \(result.pagesMissingPageNumberPlaceholder)")
/// }
/// ```
public struct SVGPDFConverter {

    public let options: ConversionOptions

    public init(options: ConversionOptions = ConversionOptions()) {
        self.options = options
    }

    // MARK: - Public API

    /// Converts an array of `SVGSource` values into a single multi-page PDF.
    ///
    /// - Parameter sources: One or more SVG inputs. Each source becomes one PDF page.
    /// - Returns: A `ConversionResult` carrying the PDF and the pages whose
    ///   page-number placeholder was not found.
    /// - Throws: `SVGPDFError` if any input cannot be read or parsed,
    ///   or if the PDF context cannot be created.
    public func makePDF(sources: [SVGSource]) throws -> ConversionResult {
        guard !sources.isEmpty else {
            throw SVGPDFError.noInputProvided
        }
#if canImport(CoreGraphics)
        return try convertViaCoreGraphics(sources: sources)
#else
        return try convertViaRsvg(sources: sources)
#endif
    }

    /// Convenience overload for a single SVG source producing a single-page PDF.
    public func makePDF(source: SVGSource) throws -> ConversionResult {
        try makePDF(sources: [source])
    }

    /// Converts SVG sources and writes the result directly to a file URL.
    ///
    /// - Parameters:
    ///   - sources: One or more SVG inputs.
    ///   - destination: The file URL to write the PDF to.
    /// - Returns: The same `ConversionResult` as `makePDF(sources:)`, so a
    ///   caller writing straight to disk still learns about missing placeholders.
    @discardableResult
    public func makePDF(sources: [SVGSource], to destination: URL) throws -> ConversionResult {
        let result = try makePDF(sources: sources)
        try result.pdfData.write(to: destination, options: .atomic)
        return result
    }

    // MARK: - Deprecated API

    /// Converts an array of `SVGSource` values into a single multi-page PDF,
    /// returning the PDF as `Data`.
    @available(*, deprecated, message: "Use makePDF(sources:), which reports the pages whose page-number placeholder was not found. This method will be removed in a future release.")
    public func convert(sources: [SVGSource]) throws -> Data {
        try makePDF(sources: sources).pdfData
    }

    /// Convenience overload for a single SVG source producing a single-page PDF.
    @available(*, deprecated, message: "Use makePDF(source:), which reports whether the page-number placeholder was found. This method will be removed in a future release.")
    public func convert(source: SVGSource) throws -> Data {
        try makePDF(sources: [source]).pdfData
    }

    /// Converts SVG sources and writes the result directly to a file URL.
    @available(*, deprecated, message: "Use makePDF(sources:to:), which reports the pages whose page-number placeholder was not found. This method will be removed in a future release.")
    public func convert(sources: [SVGSource], to destination: URL) throws {
        _ = try makePDF(sources: sources, to: destination)
    }
}

// MARK: - macOS / CoreGraphics implementation

#if canImport(CoreGraphics)
import CoreGraphics
import SwiftDraw

extension SVGPDFConverter {

    private func convertViaCoreGraphics(sources: [SVGSource]) throws -> ConversionResult {
        let pdfData = NSMutableData()
        let pageRect = options.pageSize.cgRect

        guard let context = CGContext(
            consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
            mediaBox: nil,
            nil
        ) else {
            throw SVGPDFError.pdfContextCreationFailed
        }

        var missingPages: [Int] = []

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            try renderPage(
                source: source,
                pageNumber: pageNumber,
                pageRect: pageRect,
                into: context,
                missingPages: &missingPages
            )
        }

        context.closePDF()
        return ConversionResult(
            pdfData: pdfData as Data,
            pagesMissingPageNumberPlaceholder: missingPages
        )
    }

    private func renderPage(
        source: SVGSource,
        pageNumber: Int,
        pageRect: CGRect,
        into context: CGContext,
        missingPages: inout [Int]
    ) throws {
        let svgData = try applyPageNumber(
            to: try resolveSVGData(from: source),
            pageNumber: pageNumber,
            missingPages: &missingPages
        )

        let image = try parseImage(from: svgData)

        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)

        let contentRect = pageRect.insetBy(dx: options.margin, dy: options.margin)
        let drawRect = aspectFitRect(imageSize: image.size, in: contentRect)

        // Flip the coordinate system (PDF origin is bottom-left, CGContext drawing is top-left)
        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)

        let flippedRect = CGRect(
            x: drawRect.origin.x,
            y: pageRect.height - drawRect.origin.y - drawRect.height,
            width: drawRect.width,
            height: drawRect.height
        )

        context.draw(image, in: flippedRect)
        context.restoreGState()
        context.endPage()
    }

    private func parseImage(from data: Data) throws -> SwiftDraw.SVG {
        guard let image = SwiftDraw.SVG(data: data) else {
            throw SVGPDFError.svgParsingFailed(underlying: nil)
        }
        return image
    }

    /// Returns a rect that fits `imageSize` within `containerRect`,
    /// preserving aspect ratio and centering the result.
    private func aspectFitRect(imageSize: CGSize, in containerRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return containerRect
        }

        let widthRatio = containerRect.width / imageSize.width
        let heightRatio = containerRect.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        let x = containerRect.origin.x + (containerRect.width - scaledWidth) / 2
        let y = containerRect.origin.y + (containerRect.height - scaledHeight) / 2

        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }
}
#endif

// MARK: - Linux / rsvg-convert implementation

#if !canImport(CoreGraphics)
extension SVGPDFConverter {

    private func convertViaRsvg(sources: [SVGSource]) throws -> ConversionResult {
        let tempDir = FileManager.default.temporaryDirectory
        let runID = UUID().uuidString
        var tempInputURLs: [URL] = []
        let outputURL = tempDir.appendingPathComponent("\(runID)-output.pdf")

        defer {
            for url in tempInputURLs { try? FileManager.default.removeItem(at: url) }
            try? FileManager.default.removeItem(at: outputURL)
        }

        var missingPages: [Int] = []

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            let url = try prepareTempSVG(source: source, pageNumber: pageNumber,
                                         tempDir: tempDir, name: "\(runID)-page\(index).svg",
                                         missingPages: &missingPages)
            tempInputURLs.append(url)
        }

        try runRsvgConvert(inputs: tempInputURLs.map(\.path), output: outputURL.path)

        return ConversionResult(
            pdfData: try Data(contentsOf: outputURL),
            pagesMissingPageNumberPlaceholder: missingPages
        )
    }

    private func prepareTempSVG(
        source: SVGSource,
        pageNumber: Int,
        tempDir: URL,
        name: String,
        missingPages: inout [Int]
    ) throws -> URL {
        let svgData = try applyPageNumber(
            to: try resolveSVGData(from: source),
            pageNumber: pageNumber,
            missingPages: &missingPages
        )

        let url = tempDir.appendingPathComponent(name)
        try svgData.write(to: url)
        return url
    }

    static let rsvgConvertPath = "/usr/bin/rsvg-convert"

    private func runRsvgConvert(inputs: [String], output: String) throws {
        let contentWidth = options.pageSize.width - 2 * options.margin
        let contentHeight = options.pageSize.height - 2 * options.margin

        let arguments = [
            "--format=pdf",
            "--page-width=\(options.pageSize.width)pt",
            "--page-height=\(options.pageSize.height)pt",
            "--width=\(contentWidth)pt",
            "--height=\(contentHeight)pt",
            "--keep-aspect-ratio",
            "-o", output
        ] + inputs

        // The child's stderr goes to a file rather than a `Pipe`. Nothing can drain
        // a pipe while we are waiting for the child, so a document that makes
        // rsvg-convert emit more than the pipe buffer (~64 KB on Linux — one warning
        // per element is easy to reach) would deadlock: the child blocked in write(),
        // the parent blocked waiting for the child.
        let stderrPath = output + ".stderr"
        defer { try? FileManager.default.removeItem(atPath: stderrPath) }

        let outcome: RsvgSubprocess.Outcome
        do {
            outcome = try RsvgSubprocess.run(
                executable: Self.rsvgConvertPath,
                arguments: arguments,
                stderrPath: stderrPath,
                timeout: options.subprocessTimeout
            )
        } catch RsvgSubprocess.Failure.timedOut {
            throw SVGPDFError.rsvgConvertTimedOut(seconds: options.subprocessTimeout)
        } catch RsvgSubprocess.Failure.launchFailed(let reason) {
            throw SVGPDFError.rsvgConvertLaunchFailed(reason: reason)
        }

        let stderrText = readStderr(atPath: stderrPath)

        switch outcome {
        case .exited(let code) where code == 0:
            return
        case .exited(let code):
            throw SVGPDFError.rsvgConvertFailed(exitCode: code, stderr: stderrText)
        case .signalled(let signal):
            // Foundation's convention: a signal is reported as a negative exit code.
            throw SVGPDFError.rsvgConvertFailed(exitCode: -signal, stderr: stderrText)
        case .statusUnavailable:
            // We never saw an exit status, so judge the child by what it produced.
            let attributes = try? FileManager.default.attributesOfItem(atPath: output)
            guard let size = attributes?[.size] as? Int, size > 0 else {
                throw SVGPDFError.rsvgConvertFailed(exitCode: -1, stderr: stderrText)
            }
        }
    }

    /// Reads captured stderr, truncating it so a pathological document cannot turn
    /// an error message into megabytes of warnings.
    private func readStderr(atPath path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path) else { return "" }

        let limit = 8 * 1024
        guard data.count > limit else {
            return String(decoding: data, as: UTF8.self)
        }
        let head = String(decoding: data.prefix(limit), as: UTF8.self)
        return head + "\n… (\(data.count - limit) further bytes of rsvg-convert output suppressed)"
    }
}
#endif

// MARK: - Shared helpers

extension SVGPDFConverter {
    func resolveSVGData(from source: SVGSource) throws -> Data {
        do {
            return try source.resolveData()
        } catch let svgPDFError as SVGPDFError {
            throw svgPDFError
        } catch {
            if case .fileURL(let url) = source {
                throw SVGPDFError.fileReadFailed(url: url, underlying: error)
            }
            throw error
        }
    }

    /// Stamps `pageNumber` into the placeholder element, if the caller asked for
    /// that and the document has one.
    ///
    /// A document with no placeholder is not an error — it renders as-is — but it
    /// is not silent either: the page is recorded in `missingPages` and reported
    /// to `options.diagnosticHandler`. Both platform paths go through here, so a
    /// miss is reported identically on macOS and Linux.
    func applyPageNumber(
        to svgData: Data,
        pageNumber: Int,
        missingPages: inout [Int]
    ) throws -> Data {
        guard options.injectPageNumbers else { return svgData }

        let outcome = try PageNumberInjector.inject(
            pageNumber: pageNumber,
            into: svgData,
            elementID: options.pageNumberElementID
        )

        if outcome.replacements == 0 {
            missingPages.append(pageNumber)
            options.diagnosticHandler(
                SVGPDFDiagnostic(
                    page: pageNumber,
                    kind: .pageNumberPlaceholderNotFound(elementID: options.pageNumberElementID)
                )
            )
        }

        return outcome.data
    }
}
