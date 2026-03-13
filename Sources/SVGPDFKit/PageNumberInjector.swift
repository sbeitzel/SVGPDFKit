import Foundation

/// Rewrites the page-number placeholder text element in an SVG document
/// before the SVG is handed to SwiftDraw for rendering.
///
/// The convention: ABCKit emits a `<text>` element with a specific `id`
/// attribute (configurable via `ConversionOptions.pageNumberElementID`).
/// This type finds that element and replaces its text content with the
/// actual page number string.
///
/// Example SVG fragment produced by ABCKit:
/// ```xml
/// <text id="svgpdfkit-page-number" x="306" y="780" text-anchor="middle">0</text>
/// ```
/// After injection for page 7, this becomes:
/// ```xml
/// <text id="svgpdfkit-page-number" x="306" y="780" text-anchor="middle">7</text>
/// ```
enum PageNumberInjector {

    /// Injects `pageNumber` into the SVG data, replacing the content of the
    /// element identified by `elementID`. Returns the modified SVG data.
    /// If the element is not found, the original data is returned unchanged.
    static func inject(
        pageNumber: Int,
        into svgData: Data,
        elementID: String
    ) throws -> Data {
        guard let svgString = String(data: svgData, encoding: .utf8) else {
            throw SVGPDFError.invalidSVGEncoding
        }

        let modified = rewrite(svgString: svgString, elementID: elementID, pageNumber: pageNumber)

        guard let result = modified.data(using: .utf8) else {
            throw SVGPDFError.invalidSVGEncoding
        }
        return result
    }

    // MARK: - Private

    /// Uses a simple regex-based rewrite to avoid pulling in a full XML parser.
    /// The pattern matches:
    ///   <text ... id="<elementID>" ...>anything</text>
    /// and replaces the content with the page number string.
    ///
    /// This handles the common cases produced by abcm2ps / ABCKit output.
    /// If a more complex SVG structure is needed, this can be upgraded to
    /// use XMLDocument (available on both macOS and Linux).
    private static func rewrite(
        svgString: String,
        elementID: String,
        pageNumber: Int
    ) -> String {
        // Pattern: opening <text tag containing id="elementID", capturing
        // everything up to the closing </text>, then replacing the inner text.
        let escapedID = NSRegularExpression.escapedPattern(for: elementID)
        let pattern = #"(<text\b[^>]*\bid=""# + escapedID + #""[^>]*>)[^<]*(</text>)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            // If we somehow can't compile the regex, return the original unchanged.
            return svgString
        }

        let range = NSRange(svgString.startIndex..., in: svgString)
        let replacement = "$1\(pageNumber)$2"
        return regex.stringByReplacingMatches(in: svgString, range: range, withTemplate: replacement)
    }
}
