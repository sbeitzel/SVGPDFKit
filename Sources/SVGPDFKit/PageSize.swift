import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The physical dimensions of a PDF page, in points (1 point = 1/72 inch).
public struct PageSize: Sendable {
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
