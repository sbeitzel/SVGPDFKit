import XCTest
@testable import SVGPDFKit

/// Collects diagnostics from a conversion so a test can assert on them.
///
/// `DiagnosticHandler` stores a `@Sendable` closure, so the collector has to be
/// safe to touch from wherever the handler is called — hence the lock rather
/// than a captured `var`.
private final class DiagnosticCollector: @unchecked Sendable {
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

final class SVGPDFConverterTests: XCTestCase {

    // MARK: - Helpers

    /// Fixtures are engraved by `Scripts/make-fixtures.sh`. These throw rather than
    /// force-unwrap so a missing one fails its own test with a usable message,
    /// instead of trapping and taking the whole test binary down with it.
    var testSVGURL: URL {
        get throws { try fixtureURL(named: "test-tune") }
    }

    var noPageNumberSVGURL: URL {
        get throws { try fixtureURL(named: "no-page-number") }
    }

    private func fixtureURL(named name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Resources"),
            "Missing fixture Resources/\(name).svg — regenerate it with Scripts/make-fixtures.sh"
        )
    }

    // Minimal valid inline SVG as a string
    func makeSVGString(title: String = "Test", withPageNumber: Bool = true) -> String {
        let pageNumElement = withPageNumber
            ? #"<text id="svgpdfkit-page-number" x="306" y="770" text-anchor="middle">0</text>"#
            : ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 612 792" width="612" height="792">
          <rect x="0" y="0" width="612" height="792" fill="white"/>
          <text x="306" y="400" font-size="48" text-anchor="middle">\(title)</text>
          \(pageNumElement)
        </svg>
        """
    }

    /// Options that say nothing, for the tests that deliberately convert an SVG
    /// with no placeholder and would otherwise warn on stderr.
    private func silentOptions() -> ConversionOptions {
        var options = ConversionOptions()
        options.diagnosticHandler = .silent
        return options
    }

    private func assertIsPDF(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(data.isEmpty, "PDF data is empty", file: file, line: line)
        // PDF files start with "%PDF"
        let header = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF", file: file, line: line)
    }

    // MARK: - Error cases

    func testThrowsWhenNoSourcesProvided() {
        let converter = SVGPDFConverter()
        XCTAssertThrowsError(try converter.makePDF(sources: [])) { error in
            XCTAssertEqual(error as? SVGPDFError, .noInputProvided)
        }
    }

    // MARK: - Single source

    func testConvertsSingleStringSource() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.string(makeSVGString())
        let result = try converter.makePDF(source: source)

        assertIsPDF(result.pdfData)
    }

    func testConvertsSingleFileURLSource() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.fileURL(try testSVGURL)
        let result = try converter.makePDF(source: source)

        assertIsPDF(result.pdfData)
    }

    func testConvertsFileURLSourceWithoutPageNumberElement() throws {
        let converter = SVGPDFConverter(options: silentOptions())
        let source = SVGSource.fileURL(try noPageNumberSVGURL)
        let result = try converter.makePDF(source: source)

        assertIsPDF(result.pdfData)
    }

    func testConvertsSingleDataSource() throws {
        let svgData = try XCTUnwrap(makeSVGString().data(using: .utf8))
        let converter = SVGPDFConverter()
        let result = try converter.makePDF(source: .data(svgData))

        assertIsPDF(result.pdfData)
    }

    // MARK: - Multi-page

    func testConvertsMultipleSources() throws {
        let converter = SVGPDFConverter()
        let sources = [
            SVGSource.string(makeSVGString(title: "Tune One")),
            SVGSource.string(makeSVGString(title: "Tune Two")),
            SVGSource.string(makeSVGString(title: "Tune Three"))
        ]
        let result = try converter.makePDF(sources: sources)

        assertIsPDF(result.pdfData)
    }

    // MARK: - Page number options

    func testStartingPageNumberIsRespected() throws {
        // We can't easily introspect the rendered text in a PDF without a parser,
        // but we can at least verify that conversion succeeds with a non-default
        // starting page number and the output is a valid PDF.
        var options = ConversionOptions()
        options.startingPageNumber = 12

        let converter = SVGPDFConverter(options: options)
        let result = try converter.makePDF(source: .string(makeSVGString()))

        assertIsPDF(result.pdfData)
        XCTAssertTrue(result.allPageNumbersInjected)
    }

    func testPageNumberInjectionCanBeDisabled() throws {
        var options = ConversionOptions()
        options.injectPageNumbers = false

        let converter = SVGPDFConverter(options: options)
        let result = try converter.makePDF(source: .string(makeSVGString()))

        assertIsPDF(result.pdfData)
    }

    func testSVGWithoutPageNumberElementConvertsSuccessfully() throws {
        let converter = SVGPDFConverter(options: silentOptions())
        let result = try converter.makePDF(source: .string(makeSVGString(withPageNumber: false)))

        assertIsPDF(result.pdfData)
    }

    // MARK: - Page number reporting (issue #3)

    func testReportsPageWithNoPlaceholder() throws {
        let converter = SVGPDFConverter(options: silentOptions())
        let result = try converter.makePDF(source: .string(makeSVGString(withPageNumber: false)))

        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [1])
        XCTAssertFalse(result.allPageNumbersInjected)
    }

    func testReportsNothingWhenPlaceholderIsPresent() throws {
        let converter = SVGPDFConverter()
        let result = try converter.makePDF(source: .string(makeSVGString()))

        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [])
        XCTAssertTrue(result.allPageNumbersInjected)
    }

    func testReportsNothingWhenInjectionIsDisabled() throws {
        var options = ConversionOptions()
        options.injectPageNumbers = false
        let collector = DiagnosticCollector()
        options.diagnosticHandler = collector.handler

        let converter = SVGPDFConverter(options: options)
        let result = try converter.makePDF(source: .string(makeSVGString(withPageNumber: false)))

        // Nothing was asked for, so nothing went unsatisfied.
        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [])
        XCTAssertTrue(result.allPageNumbersInjected)
        XCTAssertTrue(collector.diagnostics.isEmpty)
    }

    func testFixtureWithoutPlaceholderIsReported() throws {
        let converter = SVGPDFConverter(options: silentOptions())
        let result = try converter.makePDF(source: .fileURL(try noPageNumberSVGURL))

        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [1])
    }

    func testFixtureWithPlaceholderIsNotReported() throws {
        let converter = SVGPDFConverter()
        let result = try converter.makePDF(source: .fileURL(try testSVGURL))

        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [])
    }

    func testDiagnosticHandlerReceivesTheMiss() throws {
        var options = ConversionOptions()
        let collector = DiagnosticCollector()
        options.diagnosticHandler = collector.handler

        let converter = SVGPDFConverter(options: options)
        _ = try converter.makePDF(source: .string(makeSVGString(withPageNumber: false)))

        XCTAssertEqual(
            collector.diagnostics,
            [SVGPDFDiagnostic(page: 1, kind: .pageNumberPlaceholderNotFound(elementID: "svgpdfkit-page-number"))]
        )
    }

    func testMisconfiguredElementIDIsReportedLikeAMissingPlaceholder() throws {
        // A typo'd ID fails exactly as quietly as a missing placeholder used to —
        // which is the whole point of reporting it.
        var options = ConversionOptions()
        options.pageNumberElementID = "not-the-id-in-the-svg"
        let collector = DiagnosticCollector()
        options.diagnosticHandler = collector.handler

        let converter = SVGPDFConverter(options: options)
        let result = try converter.makePDF(source: .string(makeSVGString()))

        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [1])
        XCTAssertEqual(
            collector.diagnostics.first?.kind,
            .pageNumberPlaceholderNotFound(elementID: "not-the-id-in-the-svg")
        )
    }

    func testReportedValuesArePageNumbersNotIndices() throws {
        var options = ConversionOptions()
        options.startingPageNumber = 12
        let collector = DiagnosticCollector()
        options.diagnosticHandler = collector.handler

        let converter = SVGPDFConverter(options: options)
        let sources = [
            SVGSource.string(makeSVGString(title: "One")),
            SVGSource.string(makeSVGString(title: "Two", withPageNumber: false)),
            SVGSource.string(makeSVGString(title: "Three"))
        ]
        let result = try converter.makePDF(sources: sources)

        // The second source is page 13, not index 1.
        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [13])
        XCTAssertEqual(collector.diagnostics.map(\.page), [13])
    }

    func testDiagnosticDescriptionNamesThePageAndID() {
        let diagnostic = SVGPDFDiagnostic(
            page: 12,
            kind: .pageNumberPlaceholderNotFound(elementID: "svgpdfkit-page-number")
        )
        XCTAssertEqual(
            diagnostic.description,
            #"SVGPDFKit: page 12 — no element with id="svgpdfkit-page-number"; page number not injected"#
        )
    }

    // MARK: - Page sizes

    func testA4PageSize() throws {
        var options = ConversionOptions()
        options.pageSize = .a4

        let converter = SVGPDFConverter(options: options)
        let result = try converter.makePDF(source: .string(makeSVGString()))

        assertIsPDF(result.pdfData)
    }

    // MARK: - Write to file

    func testWritesToFileURL() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.string(makeSVGString())

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try converter.makePDF(sources: [source], to: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        assertIsPDF(try Data(contentsOf: tempURL))
        XCTAssertTrue(result.allPageNumbersInjected)
    }

    func testWriteToFileURLAlsoReportsMisses() throws {
        let converter = SVGPDFConverter(options: silentOptions())
        let source = SVGSource.string(makeSVGString(withPageNumber: false))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try converter.makePDF(sources: [source], to: tempURL)

        XCTAssertEqual(result.pagesMissingPageNumberPlaceholder, [1])
    }

    // MARK: - Invalid input

    func testThrowsForMissingFileURL() {
        let converter = SVGPDFConverter()
        let badURL = URL(fileURLWithPath: "/nonexistent/path/tune.svg")

        XCTAssertThrowsError(try converter.makePDF(source: .fileURL(badURL)))
    }

    // MARK: - Deprecated API
    //
    // These methods are scheduled for removal but must keep working until then.
    // Each test is itself marked deprecated so calling them raises no warning.

    @available(*, deprecated)
    func testDeprecatedConvertSingleSourceStillWorks() throws {
        let converter = SVGPDFConverter()
        let pdfData = try converter.convert(source: .string(makeSVGString()))

        assertIsPDF(pdfData)
    }

    @available(*, deprecated)
    func testDeprecatedConvertMultipleSourcesStillWorks() throws {
        let converter = SVGPDFConverter()
        let sources = [
            SVGSource.string(makeSVGString(title: "One")),
            SVGSource.string(makeSVGString(title: "Two"))
        ]
        let pdfData = try converter.convert(sources: sources)

        assertIsPDF(pdfData)
    }

    @available(*, deprecated)
    func testDeprecatedConvertToFileURLStillWorks() throws {
        let converter = SVGPDFConverter()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try converter.convert(sources: [.string(makeSVGString())], to: tempURL)

        assertIsPDF(try Data(contentsOf: tempURL))
    }

    @available(*, deprecated)
    func testDeprecatedConvertStillThrowsOnNoInput() {
        let converter = SVGPDFConverter()
        XCTAssertThrowsError(try converter.convert(sources: [])) { error in
            XCTAssertEqual(error as? SVGPDFError, .noInputProvided)
        }
    }
}
