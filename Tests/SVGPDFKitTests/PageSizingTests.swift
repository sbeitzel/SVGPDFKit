import XCTest
@testable import SVGPDFKit

/// Issue #5: one `pageSize` covered every page, nothing read the SVG's own, and
/// a wrong guess was a silent down-scale. These cover the three halves of that:
/// resolving a page per source, taking it from the document, and saying so when
/// an explicit page is the wrong shape.
final class PageSizingTests: XCTestCase {

    // MARK: - Helpers

    private func svg(width: String?, height: String?, viewBox: String?) -> String {
        let attributes = [
            width.map { #"width="\#($0)""# },
            height.map { #"height="\#($0)""# },
            viewBox.map { #"viewBox="\#($0)""# }
        ].compactMap { $0 }.joined(separator: " ")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" \(attributes)>
          <text x="20" y="40" font-size="24">page</text>
        </svg>
        """
    }

    /// Portrait US Letter as abcm2ps writes it: CSS pixels, 96 to the inch.
    private var portraitLetterSVG: String {
        svg(width: "816.00px", height: "1056.00px", viewBox: nil)
    }

    /// The same page turned sideways — the shape the SVPB binders are mostly made of.
    private var landscapeLetterSVG: String {
        svg(width: "1056.00px", height: "816.00px", viewBox: nil)
    }

    private func options(pageSize: PageSize?) -> ConversionOptions {
        var options = ConversionOptions()
        options.pageSize = pageSize
        options.injectPageNumbers = false
        options.diagnosticHandler = .silent
        return options
    }

    private func layout(
        of svgString: String,
        pageSize: PageSize?,
        margin: Double = 36,
        page: Int = 1
    ) throws -> (layout: SVGPDFConverter.PageLayout, diagnostics: [SVGPDFDiagnostic]) {
        var options = self.options(pageSize: pageSize)
        options.margin = margin
        var log = DiagnosticLog(handler: .silent)
        let resolved = try SVGPDFConverter(options: options)
            .pageLayout(forDocument: svgString, pageNumber: page, log: &log)
        return (resolved, log.diagnostics)
    }

    // MARK: - Reading the page out of the document

    func testReadsPixelSizedDocumentAsPoints() {
        // 816 × 1056 CSS pixels is 8.5 × 11 inches, which is 612 × 792 points.
        // Getting this wrong by the 96/72 ratio would put every page out by a third.
        let intrinsic = SVGPageComposer.intrinsicPageSize(ofDocument: portraitLetterSVG)

        XCTAssertEqual(intrinsic?.size, .letter)
        XCTAssertEqual(intrinsic?.source, .widthAndHeight)
    }

    func testReadsPointSizedDocumentUnchanged() {
        let intrinsic = SVGPageComposer.intrinsicPageSize(
            ofDocument: svg(width: "792pt", height: "612pt", viewBox: nil)
        )

        XCTAssertEqual(intrinsic?.size.width ?? 0, 792, accuracy: 0.0001)
        XCTAssertEqual(intrinsic?.size.height ?? 0, 612, accuracy: 0.0001)
    }

    func testReadsPhysicalUnitsAsPoints() {
        let intrinsic = SVGPageComposer.intrinsicPageSize(
            ofDocument: svg(width: "210mm", height: "297mm", viewBox: nil)
        )

        // A4, to within the rounding in the `.a4` preset itself.
        XCTAssertEqual(intrinsic?.size.width ?? 0, 595.28, accuracy: 0.01)
        XCTAssertEqual(intrinsic?.size.height ?? 0, 841.89, accuracy: 0.01)
    }

    func testFallsBackToTheViewBoxAsUserUnits() {
        // A bare viewBox states a coordinate system, not a size. Reading its
        // extent as user units is what rsvg-convert does with the same document,
        // so both backends land on 594 × 459 and the guess is at least shared.
        let intrinsic = SVGPageComposer.intrinsicPageSize(
            ofDocument: svg(width: nil, height: nil, viewBox: "0 0 792 612")
        )

        XCTAssertEqual(intrinsic?.size.width ?? 0, 594, accuracy: 0.0001)
        XCTAssertEqual(intrinsic?.size.height ?? 0, 459, accuracy: 0.0001)
        XCTAssertEqual(intrinsic?.source, .viewBox)
    }

    func testReportsNoPageForADocumentThatDeclaresNone() {
        XCTAssertNil(SVGPageComposer.intrinsicPageSize(
            ofDocument: svg(width: "100%", height: "100%", viewBox: nil)
        ))
    }

    /// `compose` synthesizes a `viewBox` from `intrinsicSize`, which is in the
    /// document's own user units and must not follow the page size into points.
    func testIntrinsicSizeStaysInUserUnits() {
        let size = SVGPageComposer.intrinsicSize(
            ofRootTag: #"<svg width="816.00px" height="1056.00px">"#
        )

        XCTAssertEqual(size, SVGPageComposer.Size(width: 816, height: 1056))
    }

    // MARK: - Layout resolution

    func testIntrinsicLayoutTakesThePageFromTheDocumentAndDropsTheMargin() throws {
        let (layout, diagnostics) = try layout(of: landscapeLetterSVG, pageSize: nil)

        XCTAssertEqual(layout.pageSize, .letterLandscape)
        // The SVG's own box *is* the page, so there is nothing to inset into.
        XCTAssertEqual(layout.margin, 0)
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testIntrinsicLayoutIsPerPageNotPerDocument() throws {
        let landscape = try layout(of: landscapeLetterSVG, pageSize: nil).layout
        let portrait = try layout(of: portraitLetterSVG, pageSize: nil).layout

        XCTAssertEqual(landscape.pageSize, .letterLandscape)
        XCTAssertEqual(portrait.pageSize, .letter)
    }

    func testIntrinsicLayoutReportsAViewBoxDerivedPage() throws {
        let (layout, diagnostics) = try layout(
            of: svg(width: nil, height: nil, viewBox: "0 0 792 612"),
            pageSize: nil
        )

        XCTAssertEqual(layout.pageSize.width, 594, accuracy: 0.0001)
        XCTAssertEqual(diagnostics.count, 1)
        guard case .intrinsicPageSizeFromViewBox(let size) = diagnostics.first?.kind else {
            return XCTFail("expected a viewBox diagnostic, got \(diagnostics)")
        }
        XCTAssertEqual(size.width, 594, accuracy: 0.0001)
    }

    func testIntrinsicLayoutThrowsWhenTheDocumentDeclaresNoPage() {
        XCTAssertThrowsError(
            try layout(of: svg(width: "100%", height: "100%", viewBox: nil), pageSize: nil, page: 7)
        ) { error in
            XCTAssertEqual(error as? SVGPDFError, .intrinsicPageSizeUnavailable(page: 7))
        }
    }

    func testExplicitLayoutKeepsThePageSizeAndTheMargin() throws {
        let (layout, diagnostics) = try layout(of: portraitLetterSVG, pageSize: .letter)

        XCTAssertEqual(layout.pageSize, .letter)
        XCTAssertEqual(layout.margin, 36)
        // The ordinary case — a letter document on a letter page — stays quiet
        // even though the 36pt margin means it is scaled to 88%.
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testExplicitLayoutSizesADocumentThatDeclaresNoPage() throws {
        // Nothing to compare against is not a mismatch; explicit sizing is the
        // one mode that works without the document saying anything.
        let (layout, diagnostics) = try layout(
            of: svg(width: "100%", height: "100%", viewBox: nil),
            pageSize: .a4
        )

        XCTAssertEqual(layout.pageSize, .a4)
        XCTAssertTrue(diagnostics.isEmpty)
    }

    // MARK: - The 68% that cost an afternoon

    func testReportsALandscapeDocumentOnAPortraitPage() throws {
        let (_, diagnostics) = try layout(of: landscapeLetterSVG, pageSize: .letter, margin: 36)

        guard case .pageSizeMismatch(let svg, let page, let scale) = diagnostics.first?.kind else {
            return XCTFail("expected a page-size mismatch, got \(diagnostics)")
        }
        XCTAssertEqual(svg, .letterLandscape)
        XCTAssertEqual(page, .letter)
        // 540 / 792 — the number from the issue.
        XCTAssertEqual(scale, 540.0 / 792, accuracy: 0.0001)
    }

    func testMismatchDescriptionQuotesBothPagesAndTheScale() {
        let diagnostic = SVGPDFDiagnostic(
            page: 4,
            kind: .pageSizeMismatch(svg: .letterLandscape, page: .letter, scale: 540.0 / 792)
        )

        XCTAssertEqual(
            diagnostic.description,
            "SVGPDFKit: page 4 — the SVG is 792 × 612 pt but the page is 612 × 792 pt; "
                + "the content was scaled to 68% to fit. "
                + "Set ConversionOptions.pageSize = nil to give each page the size its SVG declares."
        )
    }

    func testMismatchIsToleratedWithinRoundingOfThePageShape() throws {
        // A producer that writes 611.9 × 792.1 meant letter. Firing there would
        // make the diagnostic worthless.
        let (_, diagnostics) = try layout(
            of: svg(width: "815.87px", height: "1056.13px", viewBox: nil),
            pageSize: .letter
        )

        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testA4DocumentOnALetterPageIsReported() throws {
        let (_, diagnostics) = try layout(
            of: svg(width: "210mm", height: "297mm", viewBox: nil),
            pageSize: .letter
        )

        guard case .pageSizeMismatch = diagnostics.first?.kind else {
            return XCTFail("expected a page-size mismatch, got \(diagnostics)")
        }
    }

    func testMismatchIsNotReportedWhenThePageComesFromTheSVG() throws {
        // Nothing to mismatch: the page *is* the document's shape.
        let (_, diagnostics) = try layout(of: landscapeLetterSVG, pageSize: nil)

        XCTAssertTrue(diagnostics.isEmpty)
    }

    // MARK: - End to end

    func testMismatchReachesTheResultAndTheHandler() throws {
        var options = self.options(pageSize: .letter)
        let seen = SeenDiagnostics()
        options.diagnosticHandler = seen.handler

        let converter = SVGPDFConverter(options: options)
        let result = try converter.makePDF(sources: [
            .string(portraitLetterSVG),
            .string(landscapeLetterSVG)
        ])

        XCTAssertEqual(result.diagnostics.map(\.page), [2])
        XCTAssertEqual(seen.diagnostics, result.diagnostics)
        // A mismatch is not a missing placeholder; the older accessor is unmoved.
        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [])
        XCTAssertTrue(result.allPageNumbersInjected)
    }

    func testIntrinsicConversionThrowsOnASizelessDocument() {
        let converter = SVGPDFConverter(options: options(pageSize: nil))

        XCTAssertThrowsError(
            try converter.makePDF(sources: [
                .string(portraitLetterSVG),
                .string(svg(width: nil, height: nil, viewBox: nil))
            ])
        ) { error in
            XCTAssertEqual(error as? SVGPDFError, .intrinsicPageSizeUnavailable(page: 2))
        }
    }

#if canImport(CoreGraphics)
    // MARK: - Media boxes in the produced PDF (CoreGraphics backend)

    private func mediaBoxes(of pdfData: Data) throws -> [CGSize] {
        let provider = try XCTUnwrap(CGDataProvider(data: pdfData as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))

        return try (1...document.numberOfPages).map { number in
            let page = try XCTUnwrap(document.page(at: number))
            return page.getBoxRect(.mediaBox).size
        }
    }

    func testMixedOrientationBinderKeepsEachPagesOwnSize() throws {
        let converter = SVGPDFConverter(options: options(pageSize: nil))
        let result = try converter.makePDF(sources: [
            .string(landscapeLetterSVG),
            .string(portraitLetterSVG),
            .string(landscapeLetterSVG)
        ])

        XCTAssertEqual(
            try mediaBoxes(of: result.pdfData),
            [CGSize(width: 792, height: 612),
             CGSize(width: 612, height: 792),
             CGSize(width: 792, height: 612)]
        )
    }

    func testAnExplicitPageSizeStillCoversEveryPage() throws {
        let converter = SVGPDFConverter(options: options(pageSize: .letter))
        let result = try converter.makePDF(sources: [
            .string(landscapeLetterSVG),
            .string(portraitLetterSVG)
        ])

        XCTAssertEqual(
            try mediaBoxes(of: result.pdfData),
            [CGSize(width: 612, height: 792), CGSize(width: 612, height: 792)]
        )
    }

    /// Rasterizes page 1 and returns the extent of the ink, in points from the
    /// bottom-left of the media box.
    ///
    /// Asserting on a media box says where the paper is; the point of issue #5
    /// is where the *music* landed on it, and only rendering answers that.
    private func inkExtent(of pdfData: Data) throws -> CGRect {
        let provider = try XCTUnwrap(CGDataProvider(data: pdfData as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))

        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width.rounded())
        let height = Int(box.height.rounded())

        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)

        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }

        XCTAssertGreaterThanOrEqual(maxX, 0, "nothing was drawn")
        return CGRect(x: Double(minX), y: Double(minY),
                      width: Double(maxX - minX + 1), height: Double(maxY - minY + 1))
    }

    /// A page-filling black rectangle, so the ink extent *is* the placement.
    private func filledSVG(width: Double, height: Double) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)px" height="\(height)px">
          <rect x="0" y="0" width="\(width)" height="\(height)" fill="black"/>
        </svg>
        """
    }

    func testAnIntrinsicallySizedPageIsDrawnAtOneToOne() throws {
        let converter = SVGPDFConverter(options: options(pageSize: nil))
        let result = try converter.makePDF(source: .string(filledSVG(width: 1056, height: 816)))

        XCTAssertEqual(try mediaBoxes(of: result.pdfData), [CGSize(width: 792, height: 612)])
        // Full bleed: 1056 × 816 CSS pixels is 792 × 612 pt, and that is the
        // whole page, with no margin taken out and nothing scaled to fit.
        XCTAssertEqual(try inkExtent(of: result.pdfData),
                       CGRect(x: 0, y: 0, width: 792, height: 612))
    }

    /// The failure from the issue, in the one form that proves it: a landscape
    /// page on portrait letter, rendered, measured. 540/792 of the engraved
    /// width, with the rest of the sheet blank.
    func testAMismatchedPageSizeShrinksTheContentToSixtyEightPercent() throws {
        let converter = SVGPDFConverter(options: options(pageSize: .letter))
        let result = try converter.makePDF(source: .string(filledSVG(width: 1056, height: 816)))

        let ink = try inkExtent(of: result.pdfData)
        XCTAssertEqual(ink.width, 540, accuracy: 1)
        XCTAssertEqual(ink.height, 540 * 612 / 792, accuracy: 1)
        // Centred, so the blank paper is shared between top and bottom.
        XCTAssertEqual(ink.minY, 792 - ink.maxY, accuracy: 1)
    }
#else
    // MARK: - rsvg-convert arguments (Linux backend)

    /// One `rsvg-convert` run carries one `--page-width`, so per-page sizes have
    /// to come from somewhere else. They come from nowhere: given no geometry
    /// arguments, rsvg-convert gives each page in the PDF the size its own input
    /// declared, which is why a mixed binder still needs only one invocation.
    ///
    /// The media boxes themselves are cairo's to write, so they are asserted on
    /// the CoreGraphics backend, where the PDF can be read back without a parser.
    /// The rendered proof on this side: `rsvg-convert` on a `1056 × 816px`, an
    /// `816 × 1056px` and a `viewBox="0 0 792 612"` document, in that order and
    /// with no geometry arguments, produces media boxes `[0 0 792 612]`,
    /// `[0 0 612 792]` and `[0 0 594 459]` — the same three pages
    /// `intrinsicPageSize` computes — on librsvg 2.58 and 2.62 alike.
    func testIntrinsicSizingPassesNoGeometryArguments() {
        XCTAssertEqual(SVGPDFConverter.sizeArguments(for: nil), [])
    }

    func testExplicitSizingPassesThePageAndDrawingBox() {
        XCTAssertEqual(
            SVGPDFConverter.sizeArguments(for: PageSize(width: 612, height: 792)),
            ["--page-width=612.0pt", "--page-height=792.0pt",
             "--width=612.0pt", "--height=792.0pt", "--keep-aspect-ratio"]
        )
    }

    /// An intrinsically sized page skips `SVGPageComposer.compose` — wrapping the
    /// document in a page-sized root would throw away the size that is the whole
    /// answer — so this is the one path where rsvg-convert is handed the
    /// producer's own markup. It has to survive that.
    func testMixedOrientationBinderConverts() throws {
        let converter = SVGPDFConverter(options: options(pageSize: nil))
        let result = try converter.makePDF(sources: [
            .string(landscapeLetterSVG),
            .string(portraitLetterSVG),
            .string(landscapeLetterSVG)
        ])

        XCTAssertEqual(String(data: result.pdfData.prefix(4), encoding: .ascii), "%PDF")
    }
#endif
}

/// `DiagnosticHandler` stores a `@Sendable` closure, so collecting what it emits
/// needs a lock rather than a captured `var`.
private final class SeenDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SVGPDFDiagnostic] = []

    var diagnostics: [SVGPDFDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var handler: DiagnosticHandler {
        DiagnosticHandler { [self] diagnostic in
            lock.lock()
            defer { lock.unlock() }
            storage.append(diagnostic)
        }
    }
}
