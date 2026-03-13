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
        }
    }
}
