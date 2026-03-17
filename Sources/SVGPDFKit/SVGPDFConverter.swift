import Foundation

/// Converts one or more SVG sources into a single multi-page PDF document.
///
/// Basic usage — canonical binder (all pages, numbered from 1):
/// ```swift
/// let converter = SVGPDFConverter()
/// let pdfData = try converter.convert(sources: svgSources)
/// ```
///
/// Personal binder — subset of tunes, page numbers offset to match
/// position within the member's custom binder:
/// ```swift
/// var options = ConversionOptions()
/// options.startingPageNumber = 5   // this member's binder starts at page 5
/// let converter = SVGPDFConverter(options: options)
/// let pdfData = try converter.convert(sources: selectedSVGs)
/// ```
public struct SVGPDFConverter {

    public let options: ConversionOptions

    public init(options: ConversionOptions = ConversionOptions()) {
        self.options = options
    }

    // MARK: - Public API

    /// Converts an array of `SVGSource` values into a single multi-page PDF,
    /// returning the PDF as `Data`.
    ///
    /// - Parameter sources: One or more SVG inputs. Each source becomes one PDF page.
    /// - Returns: The complete PDF document as `Data`.
    /// - Throws: `SVGPDFError` if any input cannot be read or parsed,
    ///   or if the PDF context cannot be created.
    public func convert(sources: [SVGSource]) throws -> Data {
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
    public func convert(source: SVGSource) throws -> Data {
        try convert(sources: [source])
    }

    /// Converts SVG sources and writes the result directly to a file URL.
    ///
    /// - Parameters:
    ///   - sources: One or more SVG inputs.
    ///   - destination: The file URL to write the PDF to.
    public func convert(sources: [SVGSource], to destination: URL) throws {
        let data = try convert(sources: sources)
        try data.write(to: destination, options: .atomic)
    }
}

// MARK: - macOS / CoreGraphics implementation

#if canImport(CoreGraphics)
import CoreGraphics
import SwiftDraw

extension SVGPDFConverter {

    private func convertViaCoreGraphics(sources: [SVGSource]) throws -> Data {
        let pdfData = NSMutableData()
        let pageRect = options.pageSize.cgRect

        guard let context = CGContext(
            consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
            mediaBox: nil,
            nil
        ) else {
            throw SVGPDFError.pdfContextCreationFailed
        }

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            try renderPage(source: source, pageNumber: pageNumber, pageRect: pageRect, into: context)
        }

        context.closePDF()
        return pdfData as Data
    }

    private func renderPage(
        source: SVGSource,
        pageNumber: Int,
        pageRect: CGRect,
        into context: CGContext
    ) throws {
        var svgData = try resolveSVGData(from: source)

        if options.injectPageNumbers {
            svgData = try PageNumberInjector.inject(
                pageNumber: pageNumber,
                into: svgData,
                elementID: options.pageNumberElementID
            )
        }

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

    private func convertViaRsvg(sources: [SVGSource]) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
        let runID = UUID().uuidString
        var tempInputURLs: [URL] = []
        let outputURL = tempDir.appendingPathComponent("\(runID)-output.pdf")

        defer {
            for url in tempInputURLs { try? FileManager.default.removeItem(at: url) }
            try? FileManager.default.removeItem(at: outputURL)
        }

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            let url = try prepareTempSVG(source: source, pageNumber: pageNumber,
                                         tempDir: tempDir, name: "\(runID)-page\(index).svg")
            tempInputURLs.append(url)
        }

        try runRsvgConvert(inputs: tempInputURLs.map(\.path), output: outputURL.path)

        return try Data(contentsOf: outputURL)
    }

    private func prepareTempSVG(
        source: SVGSource,
        pageNumber: Int,
        tempDir: URL,
        name: String
    ) throws -> URL {
        var svgData = try resolveSVGData(from: source)

        if options.injectPageNumbers {
            svgData = try PageNumberInjector.inject(
                pageNumber: pageNumber,
                into: svgData,
                elementID: options.pageNumberElementID
            )
        }

        let url = tempDir.appendingPathComponent(name)
        try svgData.write(to: url)
        return url
    }

    private func runRsvgConvert(inputs: [String], output: String) throws {
        let contentWidth = options.pageSize.width - 2 * options.margin
        let contentHeight = options.pageSize.height - 2 * options.margin

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsvg-convert")
        process.arguments = [
            "--format=pdf",
            "--page-width=\(options.pageSize.width)pt",
            "--page-height=\(options.pageSize.height)pt",
            "--width=\(contentWidth)pt",
            "--height=\(contentHeight)pt",
            "--keep-aspect-ratio",
            "-o", output
        ] + inputs

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            throw SVGPDFError.rsvgConvertFailed(
                exitCode: process.terminationStatus,
                stderr: stderrString
            )
        }
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
}
