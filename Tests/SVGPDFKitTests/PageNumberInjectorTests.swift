import XCTest
@testable import SVGPDFKit

final class PageNumberInjectorTests: XCTestCase {

    // MARK: - Basic injection

    func testInjectsPageNumberIntoPlaceholderElement() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="svgpdfkit-page-number" x="306" y="770">0</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let result = try PageNumberInjector.inject(pageNumber: 7, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: result, encoding: .utf8))

        XCTAssertTrue(resultString.contains(">7<"), "Expected page number 7 in output, got:\n\(resultString)")
        XCTAssertFalse(resultString.contains(">0<"), "Old placeholder value should be replaced")
    }

    func testInjectsLargePageNumber() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="svgpdfkit-page-number">1</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let result = try PageNumberInjector.inject(pageNumber: 142, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: result, encoding: .utf8))

        XCTAssertTrue(resultString.contains(">142<"))
    }

    func testReturnsUnchangedDataWhenElementNotFound() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="some-other-id">hello</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let result = try PageNumberInjector.inject(pageNumber: 5, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: result, encoding: .utf8))

        // Should be unchanged
        XCTAssertTrue(resultString.contains("some-other-id"))
        XCTAssertTrue(resultString.contains(">hello<"))
    }

    func testCustomElementID() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="my-custom-page-num">99</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let result = try PageNumberInjector.inject(pageNumber: 3, into: data, elementID: "my-custom-page-num")
        let resultString = try XCTUnwrap(String(data: result, encoding: .utf8))

        XCTAssertTrue(resultString.contains(">3<"))
        XCTAssertFalse(resultString.contains(">99<"))
    }

    func testAttributesOnTextElementArePreserved() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="svgpdfkit-page-number" x="306" y="770" font-size="12" text-anchor="middle">0</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let result = try PageNumberInjector.inject(pageNumber: 4, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: result, encoding: .utf8))

        XCTAssertTrue(resultString.contains("x=\"306\""))
        XCTAssertTrue(resultString.contains("text-anchor=\"middle\""))
        XCTAssertTrue(resultString.contains(">4<"))
    }

    // MARK: - Edge cases

    func testThrowsOnNonUTF8Data() {
        // Create data that is not valid UTF-8
        let badData = Data([0xFF, 0xFE, 0x00])
        XCTAssertThrowsError(
            try PageNumberInjector.inject(pageNumber: 1, into: badData, elementID: "svgpdfkit-page-number")
        ) { error in
            XCTAssertEqual(error as? SVGPDFError, .invalidSVGEncoding)
        }
    }
}

extension SVGPDFError: Equatable {
    public static func == (lhs: SVGPDFError, rhs: SVGPDFError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidSVGEncoding, .invalidSVGEncoding): return true
        case (.pdfContextCreationFailed, .pdfContextCreationFailed): return true
        case (.noInputProvided, .noInputProvided): return true
        case (.svgParsingFailed, .svgParsingFailed): return true
        default: return false
        }
    }
}
