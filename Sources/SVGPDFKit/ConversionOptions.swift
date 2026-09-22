import Foundation

/// Configuration options for SVG → PDF conversion.
public struct ConversionOptions: Sendable {

    /// The page size to use for each PDF page.
    /// Defaults to US Letter.
    public var pageSize: PageSize

    /// Uniform inset applied to all four edges of the SVG content within the page.
    /// Defaults to 36 points (0.5 inch).
    public var margin: Double

    /// The element ID that SVGPDFKit looks for when injecting page numbers.
    ///
    /// The contract is producer-agnostic: whatever renders the SVG emits a
    /// `<text>` element carrying this ID, wherever the page number should
    /// appear, and SVGPDFKit replaces its content at render time. ABCKit emits
    /// the default ID; any other producer can adopt the contract by pointing
    /// this option at the ID it emits.
    ///
    /// The ID is configurable, but the element name is not — the match requires
    /// a literal `<text>` element whose content is plain text. See
    /// `PageNumberInjector` for the full limits.
    ///
    /// Defaults to `"svgpdfkit-page-number"`.
    public var pageNumberElementID: String

    /// When true, the page number placeholder element is replaced with the
    /// actual page number before rendering. When false, the SVG is rendered as-is.
    ///
    /// A placeholder that is not found does *not* fail the conversion. It is
    /// reported — to `diagnosticHandler` as it happens, and in the
    /// `ConversionResult` returned by `SVGPDFConverter.makePDF(sources:)`. Set
    /// this to `false` for SVGs that carry their own correct page numbers, which
    /// suppresses both the search and the report.
    ///
    /// Defaults to `true`.
    public var injectPageNumbers: Bool

    /// The page number of the *first* page in the output PDF.
    /// This allows a personal binder starting at page 5 to produce correct footer numbers.
    /// Defaults to `1`.
    public var startingPageNumber: Int

    /// How long to wait for the `rsvg-convert` subprocess before giving up and
    /// throwing `SVGPDFError.rsvgConvertTimedOut`. A conversion that stalls then
    /// fails the caller instead of blocking forever.
    /// Defaults to 120 seconds. Only used on platforms without CoreGraphics (Linux);
    /// the CoreGraphics path spawns no subprocess.
    public var subprocessTimeout: TimeInterval

    /// Where non-fatal conditions noticed during conversion are sent.
    ///
    /// Defaults to `.standardError`, which writes one line per diagnostic to
    /// stderr, so a page-number placeholder that never matched is visible
    /// without failing the conversion. Use `.silent` to suppress that, or
    /// supply your own handler to route diagnostics into a logger.
    public var diagnosticHandler: DiagnosticHandler

    public init(
        pageSize: PageSize = .letter,
        margin: Double = 36,
        pageNumberElementID: String = "svgpdfkit-page-number",
        injectPageNumbers: Bool = true,
        startingPageNumber: Int = 1,
        subprocessTimeout: TimeInterval = 120,
        diagnosticHandler: DiagnosticHandler = .standardError
    ) {
        self.pageSize = pageSize
        self.margin = margin
        self.pageNumberElementID = pageNumberElementID
        self.injectPageNumbers = injectPageNumbers
        self.startingPageNumber = startingPageNumber
        self.subprocessTimeout = subprocessTimeout
        self.diagnosticHandler = diagnosticHandler
    }
}
