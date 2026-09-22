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
/// Mixed-orientation binder — each page keeps the size its own SVG declares,
/// at 1:1, so landscape tunes get landscape pages and portrait tunes portrait
/// ones in the same document:
/// ```swift
/// var options = ConversionOptions()
/// options.pageSize = nil           // take the page from the SVG
/// let converter = SVGPDFConverter(options: options)
/// let result = try converter.makePDF(sources: svgSources)
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

        // `mediaBox: nil` leaves the document without a default page size, which
        // is what lets `beginPage(mediaBox:)` give each page its own — the whole
        // point of a mixed-orientation binder (issue #5).
        guard let context = CGContext(
            consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
            mediaBox: nil,
            nil
        ) else {
            throw SVGPDFError.pdfContextCreationFailed
        }

        var log = DiagnosticLog(handler: options.diagnosticHandler)

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            try renderPage(
                source: source,
                pageNumber: pageNumber,
                into: context,
                log: &log
            )
        }

        context.closePDF()
        return ConversionResult(pdfData: pdfData as Data, diagnostics: log.diagnostics)
    }

    private func renderPage(
        source: SVGSource,
        pageNumber: Int,
        into context: CGContext,
        log: inout DiagnosticLog
    ) throws {
        let svgData = try applyPageNumber(
            to: try resolveSVGData(from: source),
            pageNumber: pageNumber,
            log: &log
        )

        let layout = try pageLayout(forDocument: svgData, pageNumber: pageNumber, log: &log)
        let image = try parseImage(from: svgData)

        var mediaBox = layout.pageSize.cgRect
        context.beginPage(mediaBox: &mediaBox)

        let drawRect = pageFrame(for: image.size, layout: layout)

        // Flip the coordinate system (PDF origin is bottom-left, CGContext drawing is top-left)
        context.saveGState()
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)

        let flippedRect = CGRect(
            x: drawRect.origin.x,
            y: mediaBox.height - drawRect.origin.y - drawRect.height,
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

    /// Where an image of `imageSize` sits on the page: aspect-fitted inside the
    /// margins and centred. `SVGPageComposer` owns the arithmetic so that the
    /// rsvg backend, which has to bake this placement into the document itself,
    /// cannot drift from what is drawn here.
    ///
    /// On an intrinsically sized page the margin is zero and the page is the
    /// document's own, so the fit is the identity and the draw is 1:1. Going
    /// through `fitRect` anyway costs nothing and keeps a document whose size
    /// SwiftDraw reads differently from us centred rather than stretched.
    private func pageFrame(for imageSize: CGSize, layout: PageLayout) -> CGRect {
        let frame = SVGPageComposer.fitRect(
            content: SVGPageComposer.Size(width: imageSize.width, height: imageSize.height),
            pageSize: layout.pageSize,
            margin: layout.margin
        )
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
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

        var log = DiagnosticLog(handler: options.diagnosticHandler)

        for (index, source) in sources.enumerated() {
            let pageNumber = options.startingPageNumber + index
            let url = try prepareTempSVG(source: source, pageNumber: pageNumber,
                                         tempDir: tempDir, name: "\(runID)-page\(index).svg",
                                         log: &log)
            tempInputURLs.append(url)
        }

        try runRsvgConvert(inputs: tempInputURLs.map(\.path), output: outputURL.path)

        return ConversionResult(
            pdfData: try Data(contentsOf: outputURL),
            diagnostics: log.diagnostics
        )
    }

    private func prepareTempSVG(
        source: SVGSource,
        pageNumber: Int,
        tempDir: URL,
        name: String,
        log: inout DiagnosticLog
    ) throws -> URL {
        let svgData = try applyPageNumber(
            to: try resolveSVGData(from: source),
            pageNumber: pageNumber,
            log: &log
        )

        guard let svgString = String(data: svgData, encoding: .utf8) else {
            throw SVGPDFError.invalidSVGEncoding
        }

        // Reading the layout is what validates an intrinsically sized page and
        // reports a mismatched explicit one, so it runs on both branches even
        // though only the explicit one needs the numbers.
        let layout = try pageLayout(forDocument: svgString, pageNumber: pageNumber, log: &log)

        // An intrinsically sized page is handed to rsvg-convert untouched: with
        // no `--page-*`/`--width`/`--height` arguments it takes each input's own
        // declared size as that page's media box, which is exactly what was
        // asked for, and wrapping the document in a page-sized root would only
        // throw that size away.
        let rewritten = options.pageSize == nil
            ? svgString
            : SVGPageComposer.compose(page: svgString,
                                      pageSize: layout.pageSize,
                                      margin: layout.margin)

        guard let rewrittenData = rewritten.data(using: .utf8) else {
            throw SVGPDFError.invalidSVGEncoding
        }

        let url = tempDir.appendingPathComponent(name)
        try rewrittenData.write(to: url)
        return url
    }

    static let rsvgConvertPath = "/usr/bin/rsvg-convert"

    /// The page-geometry arguments for one `rsvg-convert` run.
    ///
    /// With an explicit `pageSize`, every input has already been composed to
    /// exactly that size with its content placed inside the margins, so the
    /// drawing box is the whole page and rsvg-convert has no placement left to
    /// get wrong. Shrinking the box by the margin here instead would put all of
    /// it on the right and bottom edges, because `--left`/`--top` default to
    /// zero and `--keep-aspect-ratio` fits to the top-left corner (issue #4).
    ///
    /// With no `pageSize` the arguments are simply absent, and that is the whole
    /// mechanism: one run can carry only one `--page-width`, but given none,
    /// rsvg-convert gives every page in the PDF the size its own input declared,
    /// converting CSS pixels to points as it goes. A mixed-orientation binder
    /// therefore still needs exactly one invocation and no PDF merge step
    /// (issue #5).
    static func sizeArguments(for pageSize: PageSize?) -> [String] {
        guard let pageSize else { return [] }
        return [
            "--page-width=\(pageSize.width)pt",
            "--page-height=\(pageSize.height)pt",
            "--width=\(pageSize.width)pt",
            "--height=\(pageSize.height)pt",
            "--keep-aspect-ratio"
        ]
    }

    private func runRsvgConvert(inputs: [String], output: String) throws {
        let arguments = ["--format=pdf"] + Self.sizeArguments(for: options.pageSize)
            + ["-o", output] + inputs

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
    /// is not silent either: the miss goes into `log`, which both reports it live
    /// and carries it into the `ConversionResult`. Both platform paths go through
    /// here, so a miss is reported identically on macOS and Linux.
    func applyPageNumber(
        to svgData: Data,
        pageNumber: Int,
        log: inout DiagnosticLog
    ) throws -> Data {
        guard options.injectPageNumbers else { return svgData }

        let outcome = try PageNumberInjector.inject(
            pageNumber: pageNumber,
            into: svgData,
            elementID: options.pageNumberElementID
        )

        if outcome.replacements == 0 {
            log.report(page: pageNumber,
                       .pageNumberPlaceholderNotFound(elementID: options.pageNumberElementID))
        }

        return outcome.data
    }

    /// The page one source lands on: its media box, and the inset its content
    /// gets inside it.
    struct PageLayout: Equatable {
        var pageSize: PageSize
        var margin: Double
    }

    /// Resolves the page for one source and reports what resolving it revealed.
    ///
    /// With an explicit `options.pageSize` the answer is that size and
    /// `options.margin`, and the only work here is noticing that the document is
    /// a different shape than the page — which means aspect-fitting is about to
    /// shrink it, the silent 68% reduction of issue #5.
    ///
    /// With `options.pageSize == nil` the page is the one the document declares,
    /// and the margin is zero: the SVG's own box *is* the page, so there is
    /// nowhere to inset the content to without scaling it, and not scaling it is
    /// the point. A document that declares no size at all cannot answer the
    /// question and throws rather than quietly getting a default.
    ///
    /// Both backends resolve through here, so a PDF built on macOS has the same
    /// media boxes as one built on Linux.
    func pageLayout(
        forDocument svgString: String,
        pageNumber: Int,
        log: inout DiagnosticLog
    ) throws -> PageLayout {
        let intrinsic = SVGPageComposer.intrinsicPageSize(ofDocument: svgString)

        guard let requested = options.pageSize else {
            guard let intrinsic else {
                throw SVGPDFError.intrinsicPageSizeUnavailable(page: pageNumber)
            }
            if intrinsic.source == .viewBox {
                log.report(page: pageNumber, .intrinsicPageSizeFromViewBox(size: intrinsic.size))
            }
            return PageLayout(pageSize: intrinsic.size, margin: 0)
        }

        if let intrinsic {
            let content = SVGPageComposer.Size(width: intrinsic.size.width,
                                               height: intrinsic.size.height)
            if SVGPageComposer.isDifferentShape(content: content, from: requested) {
                let scale = SVGPageComposer.fitScale(content: content,
                                                     pageSize: requested,
                                                     margin: options.margin)
                log.report(page: pageNumber,
                           .pageSizeMismatch(svg: intrinsic.size, page: requested, scale: scale))
            }
        }

        return PageLayout(pageSize: requested, margin: options.margin)
    }

    /// `pageLayout(forDocument:pageNumber:log:)` for a backend holding `Data`.
    ///
    /// The decoding is lossy on purpose. Only the root `<svg …>` tag is read, and
    /// that is ASCII in every SVG there is; a document in some other encoding
    /// still renders, so refusing to size it would be a new way to fail on input
    /// that used to work.
    func pageLayout(
        forDocument svgData: Data,
        pageNumber: Int,
        log: inout DiagnosticLog
    ) throws -> PageLayout {
        try pageLayout(
            forDocument: String(decoding: svgData, as: UTF8.self),
            pageNumber: pageNumber,
            log: &log
        )
    }
}
