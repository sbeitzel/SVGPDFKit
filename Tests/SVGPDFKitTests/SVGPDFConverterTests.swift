import XCTest
@testable import SVGPDFKit

final class SVGPDFConverterTests: XCTestCase {

    // MARK: - Helpers

    var testSVGURL: URL {
        Bundle.module.url(forResource: "test-tune", withExtension: "svg", subdirectory: "Resources")!
    }

    var noPageNumberSVGURL: URL {
        Bundle.module.url(forResource: "no-page-number", withExtension: "svg", subdirectory: "Resources")!
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

    // MARK: - Error cases

    func testThrowsWhenNoSourcesProvided() {
        let converter = SVGPDFConverter()
        XCTAssertThrowsError(try converter.convert(sources: [])) { error in
            XCTAssertEqual(error as? SVGPDFError, .noInputProvided)
        }
    }

    // MARK: - Single source

    func testConvertsSingleStringSource() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.string(makeSVGString())
        let pdfData = try converter.convert(source: source)

        XCTAssertFalse(pdfData.isEmpty)
        // PDF files start with "%PDF"
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    func testConvertsSingleFileURLSource() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.fileURL(testSVGURL)
        let pdfData = try converter.convert(source: source)

        XCTAssertFalse(pdfData.isEmpty)
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    func testConvertsSingleDataSource() throws {
        let svgData = try XCTUnwrap(makeSVGString().data(using: .utf8))
        let converter = SVGPDFConverter()
        let source = SVGSource.data(svgData)
        let pdfData = try converter.convert(source: source)

        XCTAssertFalse(pdfData.isEmpty)
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    // MARK: - Multi-page

    func testConvertsMultipleSources() throws {
        let converter = SVGPDFConverter()
        let sources = [
            SVGSource.string(makeSVGString(title: "Tune One")),
            SVGSource.string(makeSVGString(title: "Tune Two")),
            SVGSource.string(makeSVGString(title: "Tune Three"))
        ]
        let pdfData = try converter.convert(sources: sources)

        XCTAssertFalse(pdfData.isEmpty)
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    // MARK: - Page number options

    func testStartingPageNumberIsRespected() throws {
        // We can't easily introspect the rendered text in a PDF without a parser,
        // but we can at least verify that conversion succeeds with a non-default
        // starting page number and the output is a valid PDF.
        var options = ConversionOptions()
        options.startingPageNumber = 12

        let converter = SVGPDFConverter(options: options)
        let source = SVGSource.string(makeSVGString())
        let pdfData = try converter.convert(source: source)

        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    func testPageNumberInjectionCanBeDisabled() throws {
        var options = ConversionOptions()
        options.injectPageNumbers = false

        let converter = SVGPDFConverter(options: options)
        let source = SVGSource.string(makeSVGString())
        let pdfData = try converter.convert(source: source)

        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    func testSVGWithoutPageNumberElementConvertsSuccessfully() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.string(makeSVGString(withPageNumber: false))
        let pdfData = try converter.convert(source: source)

        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    // MARK: - Page sizes

    func testA4PageSize() throws {
        var options = ConversionOptions()
        options.pageSize = .a4

        let converter = SVGPDFConverter(options: options)
        let source = SVGSource.string(makeSVGString())
        let pdfData = try converter.convert(source: source)

        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    // MARK: - Write to file

    func testWritesToFileURL() throws {
        let converter = SVGPDFConverter()
        let source = SVGSource.string(makeSVGString())

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        try converter.convert(sources: [source], to: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        let writtenData = try Data(contentsOf: tempURL)
        let header = String(data: writtenData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Invalid input

    func testThrowsForMissingFileURL() {
        let converter = SVGPDFConverter()
        let badURL = URL(fileURLWithPath: "/nonexistent/path/tune.svg")
        let source = SVGSource.fileURL(badURL)

        XCTAssertThrowsError(try converter.convert(source: source))
    }
}
