import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The physical dimensions of a PDF page, in points (1 point = 1/72 inch).
public struct PageSize: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

#if canImport(CoreGraphics)
    public var cgRect: CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }
#endif

    /// `"792 × 612 pt"` — the form diagnostics quote a page in.
    public var description: String {
        "\(Self.format(width)) × \(Self.format(height)) pt"
    }

    /// Two decimal places, no trailing zeroes, no locale: enough to tell 595.28
    /// from 612 without printing `841.890000` for A4.
    private static func format(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

// MARK: - Standard Presets

extension PageSize {
    /// US Letter: 8.5 × 11 inches
    public static let letter = PageSize(width: 612, height: 792)

    /// US Letter landscape: 11 × 8.5 inches
    public static let letterLandscape = PageSize(width: 792, height: 612)

    /// A4: 210 × 297 mm
    public static let a4 = PageSize(width: 595.28, height: 841.89)

    /// A4 landscape: 297 × 210 mm
    public static let a4Landscape = PageSize(width: 841.89, height: 595.28)

    /// A3: 297 × 420 mm
    public static let a3 = PageSize(width: 841.89, height: 1190.55)
}
