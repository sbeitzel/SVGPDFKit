import CoreGraphics
import Foundation

/// Configuration options for SVG → PDF conversion.
public struct ConversionOptions: Sendable {

    /// The page size to use for each PDF page.
    /// Defaults to US Letter.
    public var pageSize: PageSize

    /// Uniform inset applied to all four edges of the SVG content within the page.
    /// Defaults to 36 points (0.5 inch).
    public var margin: CGFloat

    /// The element ID that SVGPDFKit looks for when injecting page numbers.
    /// ABCKit should emit an SVG `<text>` element with this ID as a placeholder.
    /// Defaults to `"svgpdfkit-page-number"`.
    public var pageNumberElementID: String

    /// When true, the page number placeholder element is replaced with the
    /// actual page number before rendering. When false, the SVG is rendered as-is.
    /// Defaults to `true`.
    public var injectPageNumbers: Bool

    /// The page number of the *first* page in the output PDF.
    /// This allows a personal binder starting at page 5 to produce correct footer numbers.
    /// Defaults to `1`.
    public var startingPageNumber: Int

    public init(
        pageSize: PageSize = .letter,
        margin: CGFloat = 36,
        pageNumberElementID: String = "svgpdfkit-page-number",
        injectPageNumbers: Bool = true,
        startingPageNumber: Int = 1
    ) {
        self.pageSize = pageSize
        self.margin = margin
        self.pageNumberElementID = pageNumberElementID
        self.injectPageNumbers = injectPageNumbers
        self.startingPageNumber = startingPageNumber
    }
}
