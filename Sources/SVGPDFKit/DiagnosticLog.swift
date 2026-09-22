import Foundation

/// Accumulates the diagnostics a conversion notices while also handing each one
/// straight to the caller's `DiagnosticHandler`.
///
/// Diagnostics are reported twice by design — live, so a long conversion says
/// something as it goes, and in the `ConversionResult`, so a caller who installed
/// no handler can still find out. Routing both through one `report` is what keeps
/// the two from drifting apart.
struct DiagnosticLog {

    private let handler: DiagnosticHandler
    private(set) var diagnostics: [SVGPDFDiagnostic] = []

    init(handler: DiagnosticHandler) {
        self.handler = handler
    }

    mutating func report(page: Int, _ kind: SVGPDFDiagnostic.Kind) {
        let diagnostic = SVGPDFDiagnostic(page: page, kind: kind)
        diagnostics.append(diagnostic)
        handler(diagnostic)
    }
}
