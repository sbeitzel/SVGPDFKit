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
