import XCTest
@testable import SVGPDFKit

/// The bug these guard against (issue #4) is that the rsvg backend sized the
/// drawing box by the margin but never offset it, so every page sat flush
/// against the top-left corner with `2 * margin` of dead space at the right and
/// bottom — while the CoreGraphics backend centred the same document.
///
/// Both backends now place pages with `SVGPageComposer.fitRect`, and the rsvg
/// backend carries that placement in the document itself, so asserting on the
/// composed markup is asserting on where the ink lands. The rendered proof —
/// `rsvg-convert` on the composed page of the reproduction in issue #4 — puts
/// the content box at 67.77pt from the left and 67.77pt from the right of a
/// 612pt page, which is the symmetry the issue asks for.
final class SVGPageComposerTests: XCTestCase {

    // MARK: - Geometry

    func testCentresAspectFitSlackWithinTheMargins() {
        // A letter-shaped page holding a 816 × 1056 document: the width is the
        // binding constraint, so the 21.18pt of vertical slack splits in two.
        let frame = SVGPageComposer.fitRect(
            content: SVGPageComposer.Size(width: 816, height: 1056),
            pageSize: .letter,
            margin: 36
        )

        XCTAssertEqual(frame.x, 36, accuracy: 0.0001)
        XCTAssertEqual(frame.y, 46.5882, accuracy: 0.0001)
        XCTAssertEqual(frame.width, 540, accuracy: 0.0001)
        XCTAssertEqual(frame.height, 698.8235, accuracy: 0.0001)
    }

    func testLeavesEqualSpaceOnOppositeEdges() {
        let frame = SVGPageComposer.fitRect(
            content: SVGPageComposer.Size(width: 792, height: 612),
            pageSize: .letter,
            margin: 36
        )

        XCTAssertEqual(frame.x, 612 - (frame.x + frame.width), accuracy: 0.0001)
        XCTAssertEqual(frame.y, 792 - (frame.y + frame.height), accuracy: 0.0001)
    }

    /// A uniform margin does not preserve the page's proportions — 540 × 720 is
    /// not letter-shaped — so even a page-shaped document has slack to centre.
    func testCentresAPageShapedDocumentInTheMargins() {
        let frame = SVGPageComposer.fitRect(
            content: SVGPageComposer.Size(width: 612, height: 792),
            pageSize: .letter,
            margin: 36
        )

        XCTAssertEqual(frame.x, 36, accuracy: 0.0001)
        XCTAssertEqual(frame.width, 540, accuracy: 0.0001)
        XCTAssertEqual(frame.y, 792 - (frame.y + frame.height), accuracy: 0.0001)
    }

    func testFillsTheContentRectWhenTheContentHasNoSize() {
        let frame = SVGPageComposer.fitRect(
            content: SVGPageComposer.Size(width: 0, height: 0),
            pageSize: .letter,
            margin: 36
        )

        XCTAssertEqual(frame, SVGPageComposer.Rect(x: 36, y: 36, width: 540, height: 720))
    }

    func testHonoursAZeroMargin() {
        let frame = SVGPageComposer.fitRect(
            content: SVGPageComposer.Size(width: 612, height: 792),
            pageSize: .letter,
            margin: 0
        )

        XCTAssertEqual(frame, SVGPageComposer.Rect(x: 0, y: 0, width: 612, height: 792))
    }

    // MARK: - Intrinsic size

    func testReadsIntrinsicSizeFromWidthAndHeight() {
        let size = SVGPageComposer.intrinsicSize(ofRootTag: #"<svg width="816.00px" height="1056.00px">"#)
        XCTAssertEqual(size, SVGPageComposer.Size(width: 816, height: 1056))
    }

    func testReadsIntrinsicSizeInPhysicalUnits() {
        let size = SVGPageComposer.intrinsicSize(ofRootTag: #"<svg width="1in" height="2in">"#)
        XCTAssertEqual(size, SVGPageComposer.Size(width: 96, height: 192))
    }

    func testFallsBackToViewBoxWhenWidthAndHeightAreRelative() {
        let size = SVGPageComposer.intrinsicSize(
            ofRootTag: #"<svg width="100%" height="100%" viewBox="0 0 792 612">"#
        )
        XCTAssertEqual(size, SVGPageComposer.Size(width: 792, height: 612))
    }

    func testReadsViewBoxSeparatedByCommas() {
        let size = SVGPageComposer.intrinsicSize(ofRootTag: #"<svg viewBox="0,0,612,792">"#)
        XCTAssertEqual(size, SVGPageComposer.Size(width: 612, height: 792))
    }

    func testReportsNoIntrinsicSizeWhenTheRootDeclaresNone() {
        XCTAssertNil(SVGPageComposer.intrinsicSize(ofRootTag: #"<svg xmlns="http://www.w3.org/2000/svg">"#))
    }

    // MARK: - Composition

    func testPlacesTheDocumentAtItsFittedRect() {
        let composed = SVGPageComposer.compose(
            page: #"<svg xmlns="http://www.w3.org/2000/svg" width="816px" height="1056px"><rect/></svg>"#,
            pageSize: .letter,
            margin: 36
        )

        XCTAssertTrue(
            composed.contains(#"x="36" y="46.5882" width="540" height="698.8235""#),
            "Expected the fitted placement on the nested viewport, got:\n\(composed)"
        )
    }

    func testComposesAPageSizedRootElement() {
        let composed = SVGPageComposer.compose(
            page: #"<svg viewBox="0 0 612 792"/>"#,
            pageSize: .a4,
            margin: 36
        )

        XCTAssertTrue(composed.contains(#"width="595.28pt" height="841.89pt""#), composed)
        XCTAssertTrue(composed.contains(#"viewBox="0 0 595.28 841.89""#), composed)
    }

    /// The regression the issue asks for: a page-shaped document whose content is
    /// symmetric within it stays symmetric on the page, instead of being shoved
    /// into the top-left corner with `2 * margin` spare at the right and bottom.
    func testKeepsASymmetricDocumentSymmetricOnThePage() throws {
        let composed = SVGPageComposer.compose(
            page: """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 612 792" width="612" height="792">
              <rect x="36" y="36" width="540" height="720" fill="none" stroke="black" stroke-width="1"/>
            </svg>
            """,
            pageSize: .letter,
            margin: 36
        )

        // Rounded to the 4 decimal places the composer writes into the markup.
        let placement = try nestedPlacement(in: composed)
        XCTAssertEqual(placement.x, 612 - (placement.x + placement.width), accuracy: 0.001)
        XCTAssertEqual(placement.y, 792 - (placement.y + placement.height), accuracy: 0.001)
    }

    /// The other half of issue #4: one `rsvg-convert` invocation renders every
    /// page with the same arguments, so a binder mixing orientations could not be
    /// centred from the command line at all. Carrying the placement in the
    /// document centres each page on its own terms.
    func testCentresPagesOfDifferentOrientationsIndependently() throws {
        let portrait = try nestedPlacement(
            in: SVGPageComposer.compose(
                page: #"<svg viewBox="0 0 612 792" width="612" height="792"/>"#,
                pageSize: .letter,
                margin: 36
            )
        )
        let landscape = try nestedPlacement(
            in: SVGPageComposer.compose(
                page: #"<svg viewBox="0 0 792 612" width="792" height="612"/>"#,
                pageSize: .letter,
                margin: 36
            )
        )

        for (name, placement) in [("portrait", portrait), ("landscape", landscape)] {
            // Both shapes are width-constrained, so both span the margins
            // horizontally and centre whatever vertical slack is left.
            XCTAssertEqual(placement.x, 36, accuracy: 0.001, name)
            XCTAssertEqual(placement.width, 540, accuracy: 0.001, name)
            XCTAssertEqual(placement.y, 792 - (placement.y + placement.height), accuracy: 0.001, name)
        }
        // The slack differs per shape, which is exactly what one set of
        // rsvg-convert arguments could not express.
        XCTAssertEqual(portrait.y, 46.5882, accuracy: 0.001)
        XCTAssertEqual(landscape.y, 187.3636, accuracy: 0.001)
    }

    func testSynthesizesAViewBoxForADocumentSizedOnlyByWidthAndHeight() {
        let composed = SVGPageComposer.compose(
            page: #"<svg xmlns="http://www.w3.org/2000/svg" width="816px" height="1056px"/>"#,
            pageSize: .letter,
            margin: 36
        )

        XCTAssertTrue(composed.contains(#"viewBox="0 0 816 1056""#), composed)
    }

    func testKeepsTheDocumentsOwnViewBox() {
        let composed = SVGPageComposer.compose(
            page: #"<svg viewBox="10 20 612 792" width="612" height="792"/>"#,
            pageSize: .letter,
            margin: 36
        )

        XCTAssertTrue(composed.contains(#"viewBox="10 20 612 792""#), composed)
        // The page's own viewBox is the only other one; nothing was synthesized.
        XCTAssertEqual(composed.components(separatedBy: "viewBox=").count - 1, 2, composed)
    }

    func testPreservesTheDocumentBodyAndTheRootsOtherAttributes() {
        let composed = SVGPageComposer.compose(
            page: """
            <?xml version="1.0" standalone="no"?>
            <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
            <svg xmlns="http://www.w3.org/2000/svg" version="1.1"
            \txmlns:xlink="http://www.w3.org/1999/xlink"
            \tcolor="black"
            \twidth="816.00px" height="1056.00px">
            <text id="svgpdfkit-page-number">7</text>
            </svg>
            """,
            pageSize: .letter,
            margin: 36
        )

        XCTAssertTrue(composed.contains(#"<text id="svgpdfkit-page-number">7</text>"#), composed)
        XCTAssertTrue(composed.contains(#"color="black""#), composed)
        XCTAssertTrue(composed.contains(#"version="1.1""#), composed)
        // A DOCTYPE cannot survive being moved inside another element.
        XCTAssertFalse(composed.contains("DOCTYPE"), composed)
        XCTAssertEqual(composed.components(separatedBy: "<?xml").count - 1, 1,
                       "Exactly one XML declaration, at the top")
        XCTAssertTrue(composed.hasPrefix("<?xml"), composed)
    }

    func testDropsOnlyTheRootsOwnSizeAndPosition() {
        let composed = SVGPageComposer.compose(
            page: #"<svg width="100" height="100" stroke-width="3"><rect width="10" height="10"/></svg>"#,
            pageSize: .letter,
            margin: 36
        )

        XCTAssertTrue(composed.contains(#"stroke-width="3""#), composed)
        XCTAssertTrue(composed.contains(#"<rect width="10" height="10"/>"#), composed)
    }

    func testReadsSingleQuotedAttributes() {
        let composed = SVGPageComposer.compose(
            page: "<svg width='816px' height='1056px'/>",
            pageSize: .letter,
            margin: 36
        )

        XCTAssertTrue(composed.contains(#"height="698.8235""#), composed)
        XCTAssertFalse(composed.contains("816px"), "The original size should have been dropped:\n\(composed)")
    }

    func testGivesTheWholeContentRectToADocumentOfUnknownSize() throws {
        let composed = SVGPageComposer.compose(
            page: #"<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>"#,
            pageSize: .letter,
            margin: 36
        )

        let placement = try nestedPlacement(in: composed)
        XCTAssertEqual(placement, SVGPageComposer.Rect(x: 36, y: 36, width: 540, height: 720))
        XCTAssertFalse(composed.contains("viewBox=\"0 0 0 0\""), composed)
    }

    func testReturnsADocumentWithNoRootElementUnchanged() {
        let notSVG = "this is not markup"
        XCTAssertEqual(SVGPageComposer.compose(page: notSVG, pageSize: .letter, margin: 36), notSVG)
    }

    // MARK: - Helpers

    /// The x/y/width/height the composer put on the nested viewport — the second
    /// `<svg` tag in the composed document, the first being the page.
    private func nestedPlacement(
        in composed: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SVGPageComposer.Rect {
        let tags = composed.ranges(ofPattern: #"<svg\b[^>]*>"#).map { String(composed[$0]) }
        let nested = try XCTUnwrap(tags.count >= 2 ? tags[1] : nil,
                                   "Expected a nested <svg> in:\n\(composed)", file: file, line: line)

        func value(_ name: String) throws -> Double {
            let text = nested.ranges(ofPattern: name + #"="[^"]*""#)
                .first
                .map { String(nested[$0]) }
            let raw = try XCTUnwrap(text, "No \(name) on \(nested)", file: file, line: line)
                .split(separator: "\"")[1]
            return try XCTUnwrap(Double(raw), "Unreadable \(name) on \(nested)", file: file, line: line)
        }

        return SVGPageComposer.Rect(
            x: try value("x"),
            y: try value("y"),
            width: try value("width"),
            height: try value("height")
        )
    }
}

private extension String {
    func ranges(ofPattern pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self))
            .compactMap { Range($0.range, in: self) }
    }
}
