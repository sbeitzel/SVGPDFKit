import Foundation

/// Errors that SVGPDFKit can throw during conversion.
public enum SVGPDFError: Error, CustomStringConvertible {

    /// The SVG string could not be encoded as UTF-8 data.
    case invalidSVGEncoding

    /// SwiftDraw could not parse the SVG data.
    case svgParsingFailed(underlying: Error?)

    /// A `CGPDFContext` could not be created for the given destination.
    case pdfContextCreationFailed

    /// The provided input array was empty; at least one SVGSource is required.
    case noInputProvided

    /// A file URL could not be read from disk.
    case fileReadFailed(url: URL, underlying: Error)

    /// `ConversionOptions.pageSize` was `nil` — take the page size from the SVG —
    /// but the document declares neither a `width`/`height` pair nor a usable
    /// `viewBox`, so it states no page at all.
    ///
    /// This throws rather than falling back to a default page size: a caller who
    /// asked for the SVG's own page and quietly got US Letter instead is the
    /// failure mode that [#5](https://github.com/sbeitzel/SVGPDFKit/issues/5)
    /// exists to end.
    case intrinsicPageSizeUnavailable(page: Int)

    /// The `rsvg-convert` subprocess exited with a non-zero status (Linux only).
    case rsvgConvertFailed(exitCode: Int32, stderr: String)

    /// The `rsvg-convert` subprocess could not be started (Linux only).
    case rsvgConvertLaunchFailed(reason: String)

    /// The `rsvg-convert` subprocess did not finish within
    /// `ConversionOptions.subprocessTimeout` and was killed (Linux only).
    case rsvgConvertTimedOut(seconds: TimeInterval)

    public var description: String {
        switch self {
        case .invalidSVGEncoding:
            return "SVG string could not be encoded as UTF-8."
        case .svgParsingFailed(let error):
            if let error {
                return "SVG parsing failed: \(error.localizedDescription)"
            }
            return "SVG parsing failed for an unknown reason."
        case .pdfContextCreationFailed:
            return "Could not create a CGPDFContext for the requested destination."
        case .noInputProvided:
            return "At least one SVGSource must be provided."
        case .fileReadFailed(let url, let error):
            return "Could not read file at \(url.path): \(error.localizedDescription)"
        case .intrinsicPageSizeUnavailable(let page):
            return "Page \(page): ConversionOptions.pageSize is nil, so the page size must come from "
                + "the SVG, but the document declares no width/height and no usable viewBox."
        case .rsvgConvertFailed(let exitCode, let stderr):
            return "rsvg-convert exited with code \(exitCode): \(stderr)"
        case .rsvgConvertLaunchFailed(let reason):
            return "Could not start rsvg-convert: \(reason)"
        case .rsvgConvertTimedOut(let seconds):
            return "rsvg-convert did not finish within \(seconds) seconds and was killed."
        }
    }
}
