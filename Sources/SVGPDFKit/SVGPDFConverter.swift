import CoreGraphics
import Foundation
import SwiftDraw

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

        let pdfData = NSMutableData()
        let pageRect = options.pageSize.cgRect

        guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                      mediaBox: nil,
                                      nil) else {
            throw SVGPDFError.pdfContextCreationFailed
        }

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            try renderPage(source: source, pageNumber: pageNumber, pageRect: pageRect, into: context)
        }

        context.closePDF()
        return pdfData as Data
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

    // MARK: - Private

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

        // Begin a new PDF page
        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)

        // Calculate the content rect respecting margins
        let contentRect = pageRect.insetBy(dx: options.margin, dy: options.margin)

        // Scale the SVG to fit within the content rect while preserving aspect ratio
        let drawRect = aspectFitRect(imageSize: image.size, in: contentRect)

        // Flip the coordinate system (PDF origin is bottom-left, CGContext drawing is top-left)
        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)

        // Adjust drawRect for the flipped coordinate system
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

    private func resolveSVGData(from source: SVGSource) throws -> Data {
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
