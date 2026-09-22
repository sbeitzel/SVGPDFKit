import Foundation

/// A non-fatal condition noticed during conversion.
///
/// Diagnostics report things a caller asked for that could not be done, where
/// failing the whole conversion would be the wrong answer. They are delivered to
/// `ConversionOptions.diagnosticHandler` as they happen, and summarized in the
/// `ConversionResult` that `SVGPDFConverter.makePDF(sources:)` returns.
public struct SVGPDFDiagnostic: Sendable, Equatable, CustomStringConvertible {

    /// What went unsatisfied.
    public enum Kind: Sendable, Equatable {
        /// `ConversionOptions.injectPageNumbers` was true, but the page's SVG
        /// carried no `<text>` element with the configured ID, so the page
        /// number was not injected. The page renders with whatever number —
        /// or none — the source SVG already contained.
        case pageNumberPlaceholderNotFound(elementID: String)

        /// `ConversionOptions.pageSize` named a page of a different shape than
        /// the SVG was engraved for, so aspect-fitting the document scaled it by
        /// `scale` and left the difference as blank paper.
        ///
        /// This is almost always a caller who guessed the page size wrong rather
        /// than one who wanted a reduction — the failure
        /// [#5](https://github.com/sbeitzel/SVGPDFKit/issues/5) was filed for,
        /// where a `792 × 612` landscape tune on a portrait letter page came out
        /// at 68% and nothing said so. Setting `pageSize` to `nil` takes the page
        /// from the SVG and removes the guess.
        case pageSizeMismatch(svg: PageSize, page: PageSize, scale: Double)

        /// `ConversionOptions.pageSize` was `nil` — take the page from the SVG —
        /// and the document declared no `width`/`height`, so its page size was
        /// read from the `viewBox`.
        ///
        /// A `viewBox` is a coordinate system, not a physical size, so this is an
        /// assumption: its extent is read as user units, 96 to the inch, which is
        /// what every renderer does with it. A producer that means points is off
        /// by a quarter, and should say so with a `width` and `height`.
        case intrinsicPageSizeFromViewBox(size: PageSize)
    }

    /// The page number this diagnostic concerns, as assigned by
    /// `ConversionOptions.startingPageNumber` — not the index of the source.
    public let page: Int

    /// What went unsatisfied.
    public let kind: Kind

    public init(page: Int, kind: Kind) {
        self.page = page
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case .pageNumberPlaceholderNotFound(let elementID):
            return #"SVGPDFKit: page \#(page) — no element with id="\#(elementID)"; page number not injected"#
        case .pageSizeMismatch(let svg, let pageSize, let scale):
            let percent = Int((scale * 100).rounded())
            return "SVGPDFKit: page \(page) — the SVG is \(svg) but the page is \(pageSize); "
                + "the content was scaled to \(percent)% to fit. "
                + "Set ConversionOptions.pageSize = nil to give each page the size its SVG declares."
        case .intrinsicPageSizeFromViewBox(let size):
            return "SVGPDFKit: page \(page) — the SVG declares no width/height; its page size was read "
                + "from the viewBox as \(size), taking user units as 1/96 inch. "
                + "Give the root <svg> a width and height if that is not the intended size."
        }
    }
}

/// Where `SVGPDFConverter` sends its diagnostics.
///
/// The default, `.standardError`, writes one line per diagnostic to stderr. That
/// makes a page-number placeholder that never matched visible without failing the
/// conversion — the alternative is the silence that let
/// [#3](https://github.com/sbeitzel/SVGPDFKit/issues/3) go unnoticed.
///
/// ```swift
/// var options = ConversionOptions()
/// options.diagnosticHandler = .silent          // say nothing
/// options.diagnosticHandler = .init { logger.warning("\($0)") }   // route elsewhere
/// ```
public struct DiagnosticHandler: Sendable {

    private let emit: @Sendable (SVGPDFDiagnostic) -> Void

    public init(_ emit: @escaping @Sendable (SVGPDFDiagnostic) -> Void) {
        self.emit = emit
    }

    public func callAsFunction(_ diagnostic: SVGPDFDiagnostic) {
        emit(diagnostic)
    }

    /// Writes each diagnostic's `description` to standard error, newline-terminated.
    /// This is the default.
    public static let standardError = DiagnosticHandler { diagnostic in
        let line = diagnostic.description + "\n"
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }

    /// Discards every diagnostic. Use this when a source SVG is knowingly
    /// without a placeholder and the warning is just noise — though
    /// `ConversionOptions.injectPageNumbers = false` says that more precisely.
    public static let silent = DiagnosticHandler { _ in }
}
