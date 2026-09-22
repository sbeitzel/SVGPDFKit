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
        let outcome = try PageNumberInjector.inject(pageNumber: 7, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: outcome.data, encoding: .utf8))

        XCTAssertEqual(outcome.replacements, 1)
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
        let outcome = try PageNumberInjector.inject(pageNumber: 142, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: outcome.data, encoding: .utf8))

        XCTAssertEqual(outcome.replacements, 1)
        XCTAssertTrue(resultString.contains(">142<"))
    }

    func testReportsZeroReplacementsAndUnchangedDataWhenElementNotFound() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="some-other-id">hello</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let outcome = try PageNumberInjector.inject(pageNumber: 5, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: outcome.data, encoding: .utf8))

        // The miss is reported rather than swallowed — this is issue #3.
        XCTAssertEqual(outcome.replacements, 0)

        // Should be unchanged
        XCTAssertEqual(outcome.data, data)
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
        let outcome = try PageNumberInjector.inject(pageNumber: 3, into: data, elementID: "my-custom-page-num")
        let resultString = try XCTUnwrap(String(data: outcome.data, encoding: .utf8))

        XCTAssertEqual(outcome.replacements, 1)
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
        let outcome = try PageNumberInjector.inject(pageNumber: 4, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: outcome.data, encoding: .utf8))

        XCTAssertEqual(outcome.replacements, 1)
        XCTAssertTrue(resultString.contains("x=\"306\""))
        XCTAssertTrue(resultString.contains("text-anchor=\"middle\""))
        XCTAssertTrue(resultString.contains(">4<"))
    }

    // MARK: - Documented limits
    //
    // These pin what the mechanism deliberately does not match, so the
    // documentation in PageNumberInjector and the README stays honest.

    func testDoesNotMatchMarkerOnAnotherElement() throws {
        // A renderer that marks its page number with a group — CeolKit's
        // <g id="ceolkit-tag-pagenumber"> — is out of reach for any element ID.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <g id="ceolkit-tag-pagenumber" data-ceolkit-tag="pagenumber"><path d="M0 0"/></g>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let outcome = try PageNumberInjector.inject(pageNumber: 5, into: data, elementID: "ceolkit-tag-pagenumber")

        XCTAssertEqual(outcome.replacements, 0)
        XCTAssertEqual(outcome.data, data)
    }

    func testDoesNotMatchTextWrappingATspan() throws {
        // The content pattern stops at the first '<', so nested markup misses.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="svgpdfkit-page-number"><tspan>0</tspan></text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let outcome = try PageNumberInjector.inject(pageNumber: 5, into: data, elementID: "svgpdfkit-page-number")

        XCTAssertEqual(outcome.replacements, 0)
        XCTAssertEqual(outcome.data, data)
    }

    // MARK: - Edge cases

    func testReportsEveryPlaceholderItRewrites() throws {
        // Two elements share the ID — invalid XML, but the rewrite is textual,
        // and the reported count should describe what actually happened.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text id="svgpdfkit-page-number">0</text>
          <text id="svgpdfkit-page-number">0</text>
        </svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let outcome = try PageNumberInjector.inject(pageNumber: 8, into: data, elementID: "svgpdfkit-page-number")
        let resultString = try XCTUnwrap(String(data: outcome.data, encoding: .utf8))

        XCTAssertEqual(outcome.replacements, 2)
        XCTAssertFalse(resultString.contains(">0<"))
    }

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
        case (.intrinsicPageSizeUnavailable(let lhs), .intrinsicPageSizeUnavailable(let rhs)):
            return lhs == rhs
        default: return false
        }
    }
}
