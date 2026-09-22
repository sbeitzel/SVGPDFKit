import Foundation

/// The PDF produced by a conversion, plus what the conversion could not do.
///
/// Returned by `SVGPDFConverter.makePDF(sources:)`. The type is deliberately not
/// `@discardableResult`-able at its call sites: a caller who asked for page
/// numbers and did not get them finds out by reading
/// `pagesMissingPageNumberPlaceholder`, or from the stderr line that
/// `ConversionOptions.diagnosticHandler` writes by default.
public struct ConversionResult: Sendable {

    /// The complete PDF document.
    public let pdfData: Data

    /// The pages whose SVG carried no page-number placeholder, so no page number
    /// was injected into them.
    ///
    /// These are page *numbers* — as assigned by
    /// `ConversionOptions.startingPageNumber` — not indices into the source
    /// array. With a starting page number of 12, a miss on the second source is
    /// reported as `13`.
    ///
    /// Empty when every page was injected, and also when
    /// `ConversionOptions.injectPageNumbers` is `false`, since nothing was asked
    /// for in that case.
    public let pagesMissingPageNumberPlaceholder: [Int]

    /// Every non-fatal condition the conversion noticed, in the order it noticed
    /// them — the same values `ConversionOptions.diagnosticHandler` was handed as
    /// the conversion ran, kept for a caller who would rather inspect them
    /// afterwards than install a handler.
    ///
    /// `pagesMissingPageNumberPlaceholder` is the one long-standing slice of
    /// this; a caller who also wants to know that a page was scaled down to fit
    /// `ConversionOptions.pageSize` reads it from here:
    ///
    /// ```swift
    /// for diagnostic in result.diagnostics {
    ///     if case .pageSizeMismatch = diagnostic.kind { … }
    /// }
    /// ```
    public let diagnostics: [SVGPDFDiagnostic]

    /// True when nothing was asked for, or everything asked for was done.
    public var allPageNumbersInjected: Bool {
        pagesMissingPageNumberPlaceholder.isEmpty
    }

    /// Builds a result from the diagnostics a conversion collected, deriving
    /// `pagesMissingPageNumberPlaceholder` from them.
    public init(pdfData: Data, diagnostics: [SVGPDFDiagnostic]) {
        self.pdfData = pdfData
        self.diagnostics = diagnostics
        self.pagesMissingPageNumberPlaceholder = diagnostics.compactMap { diagnostic in
            guard case .pageNumberPlaceholderNotFound = diagnostic.kind else { return nil }
            return diagnostic.page
        }
    }

    /// Builds a result from a bare list of pages. `diagnostics` comes out empty,
    /// since a page number alone does not say which element ID was looked for;
    /// prefer `init(pdfData:diagnostics:)`.
    public init(pdfData: Data, pagesMissingPageNumberPlaceholder: [Int]) {
        self.pdfData = pdfData
        self.pagesMissingPageNumberPlaceholder = pagesMissingPageNumberPlaceholder
        self.diagnostics = []
    }
}
