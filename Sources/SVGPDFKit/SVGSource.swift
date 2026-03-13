import Foundation

/// Represents a single SVG input to be rendered as a PDF page.
public enum SVGSource {
    /// A file URL pointing to an `.svg` file on disk.
    case fileURL(URL)

    /// Raw SVG data (e.g. as produced in-memory by ABCKit).
    case data(Data)

    /// An SVG document as a UTF-8 string.
    case string(String)
}

extension SVGSource {
    /// Resolves the source to raw `Data`, performing any necessary I/O.
    func resolveData() throws -> Data {
        switch self {
        case .fileURL(let url):
            return try Data(contentsOf: url)
        case .data(let data):
            return data
        case .string(let string):
            guard let data = string.data(using: .utf8) else {
                throw SVGPDFError.invalidSVGEncoding
            }
            return data
        }
    }
}
