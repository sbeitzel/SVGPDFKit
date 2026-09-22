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

    /// True when nothing was asked for, or everything asked for was done.
    public var allPageNumbersInjected: Bool {
        pagesMissingPageNumberPlaceholder.isEmpty
    }

    public init(pdfData: Data, pagesMissingPageNumberPlaceholder: [Int]) {
        self.pdfData = pdfData
        self.pagesMissingPageNumberPlaceholder = pagesMissingPageNumberPlaceholder
    }
}
