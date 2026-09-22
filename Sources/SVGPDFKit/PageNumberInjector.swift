import Foundation

/// Rewrites the page-number placeholder text element in an SVG document
/// before the SVG is handed off for rendering.
///
/// The convention is producer-agnostic: whatever draws the SVG emits a `<text>`
/// element whose `id` matches `ConversionOptions.pageNumberElementID`, and this
/// type replaces that element's text content with the actual page number.
/// ABCKit is one such producer — it emits the default
/// `id="svgpdfkit-page-number"` — but any producer that controls its own SVG
/// output can adopt the contract by pointing the option at the ID it emits.
///
/// Example placeholder:
/// ```xml
/// <text id="svgpdfkit-page-number" x="306" y="780" text-anchor="middle">0</text>
/// ```
/// After injection for page 7, this becomes:
/// ```xml
/// <text id="svgpdfkit-page-number" x="306" y="780" text-anchor="middle">7</text>
/// ```
///
/// ## Limits of the match
///
/// The ID is configurable; the element name and the shape of its content are not.
///
/// - The element must be literally `<text>`. A marker on any other element —
///   `<g id="…">`, say — will not be found under any ID.
/// - Its content must be plain text. A `<text>` that wraps a `<tspan>` will not
///   match, because the content pattern stops at the first `<`.
/// - A renderer that converts glyphs to path geometry (outlined text) emits no
///   `<text>` element at all, so no ID can reach it. A consumer in that position
///   wants the number correct when the page is drawn, and should set
///   `ConversionOptions.injectPageNumbers` to `false`.
///
/// A miss is not an error. `inject` reports how many elements it rewrote, and
/// `SVGPDFConverter` surfaces a count of zero through
/// `ConversionOptions.diagnosticHandler` and `ConversionResult`.
enum PageNumberInjector {

    /// What a single `inject` call did.
    struct Outcome {
        /// The SVG data to render — rewritten if a placeholder was found,
        /// byte-identical to the input if not.
        let data: Data

        /// How many placeholder elements were rewritten. Zero means the
        /// document carried no element with the requested ID, so the page
        /// number was *not* injected and `data` is the unmodified input.
        let replacements: Int
    }

    /// Injects `pageNumber` into the SVG data, replacing the content of every
    /// element identified by `elementID`.
    ///
    /// - Returns: An `Outcome` carrying the (possibly unchanged) SVG data and
    ///   the number of elements rewritten.
    /// - Throws: `SVGPDFError.invalidSVGEncoding` if the data is not UTF-8.
    static func inject(
        pageNumber: Int,
        into svgData: Data,
        elementID: String
    ) throws -> Outcome {
        guard let svgString = String(data: svgData, encoding: .utf8) else {
            throw SVGPDFError.invalidSVGEncoding
        }

        let (modified, replacements) = rewrite(
            svgString: svgString,
            elementID: elementID,
            pageNumber: pageNumber
        )

        guard let result = modified.data(using: .utf8) else {
            throw SVGPDFError.invalidSVGEncoding
        }
        return Outcome(data: result, replacements: replacements)
    }

    // MARK: - Private

    /// Uses a simple regex-based rewrite to avoid pulling in a full XML parser.
    /// The pattern matches:
    ///   <text ... id="<elementID>" ...>anything-but-a-tag</text>
    /// and replaces the content with the page number string.
    ///
    /// See the type-level documentation for what this deliberately does not match.
    /// If a more complex SVG structure is needed, this can be upgraded to
    /// use XMLDocument (available on both macOS and Linux).
    private static func rewrite(
        svgString: String,
        elementID: String,
        pageNumber: Int
    ) -> (result: String, replacements: Int) {
        // Pattern: opening <text tag containing id="elementID", capturing
        // everything up to the closing </text>, then replacing the inner text.
        let escapedID = NSRegularExpression.escapedPattern(for: elementID)
        let pattern = #"(<text\b[^>]*\bid=""# + escapedID + #""[^>]*>)[^<]*(</text>)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            // If we somehow can't compile the regex, report having done nothing.
            return (svgString, 0)
        }

        let range = NSRange(svgString.startIndex..., in: svgString)
        let matches = regex.numberOfMatches(in: svgString, range: range)
        guard matches > 0 else {
            return (svgString, 0)
        }

        let replacement = "$1\(pageNumber)$2"
        let result = regex.stringByReplacingMatches(in: svgString, range: range, withTemplate: replacement)
        return (result, matches)
    }
}
